// uart_shim.sv
// Bridges UART to the systolic array design for Basys3 testing
// Protocol:
//   RX: 0xAB (start) + 32 bytes (A then B, row-major) + 0xFF (trigger)
//   TX: 48 bytes (16 results x 3 bytes each, 20-bit big-endian)
// 100MHz clk, 115200 baud

module uart_shim (
    input  logic        clk,        // 100MHz
    input  logic        btn_rst,    // active-high reset (btnC on Basys3)
    input  logic        rx,         // UART RX from PC
    output logic        tx,         // UART TX to PC
    // status LEDs
    output logic        led_load_done,
    output logic        led_comp_done,
    output logic        led_uart_done
);

    // Invert btnC (active-high) to active-low rst_n for all submodules
    logic rst_n;
    assign rst_n = ~btn_rst;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    // UART RX
    logic [7:0] rx_data;
    logic       rx_valid;

    // UART TX
    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;

    // Matrix storage
    logic [7:0] a_mat [4][4];
    logic [7:0] b_mat [4][4];
    logic [19:0] acc  [4][4];

    // Systolic control
    logic clear, start, comp_done;

    // RX state machine
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_WAIT_START,
        RX_CLEAR,
        RX_RECV_DATA,
        RX_WAIT_END,
        RX_COMPUTE,
        RX_CLEAR_PRE,
        RX_WAIT_COMP,
        RX_SEND,
        RX_WAIT_TX
    } rx_state_t;
    rx_state_t rx_state;
    

    logic [5:0] byte_idx;   // 0-31 for 32 data bytes
    logic [5:0] tx_idx;     // 0-47 for 48 output bytes
    logic       load_done;
    logic       tx_started;
    logic [2:0] clear_cnt;  // holds clear for 4 cycles

    // -------------------------------------------------------------------------
    // UART RX
    // -------------------------------------------------------------------------
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (rx),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // -------------------------------------------------------------------------
    // UART TX
    // -------------------------------------------------------------------------
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx       (tx)
    );

    // -------------------------------------------------------------------------
    // Systolic array
    // -------------------------------------------------------------------------
    systolic_array_4x4 u_systolic (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .start    (start),
        .a_in     (a_mat),
        .b_in     (b_mat),
        .acc      (acc),
        .comp_done(comp_done)
    );

    // -------------------------------------------------------------------------
    // RX / control state machine
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            byte_idx   <= 6'd0;
            tx_idx     <= 6'd0;
            load_done  <= 1'b0;
            clear      <= 1'b0;
            start      <= 1'b0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
            tx_started <= 1'b0;
            clear_cnt  <= 3'd0;
        end else begin
            // defaults
            clear    <= 1'b0;
            start    <= 1'b0;
            tx_start <= 1'b0;

            case (rx_state)

                RX_IDLE: begin
                    load_done <= 1'b0;
                    byte_idx  <= 6'd0;
                    tx_idx    <= 6'd0;
                    clear     <= 1'b1;
                    clear_cnt <= 3'd0;
                    rx_state  <= RX_CLEAR;
                end

                RX_CLEAR: begin
                    clear <= 1'b1;
                    clear_cnt <= clear_cnt + 1;
                    if (clear_cnt == 3'd7)
                        rx_state <= RX_WAIT_START;
                end

                RX_WAIT_START: begin
                    if (rx_valid && rx_data == 8'hAB)
                        rx_state <= RX_RECV_DATA;
                end

                RX_RECV_DATA: begin
                    if (rx_valid) begin
                        // store row-major: first 16 bytes = A, next 16 = B
                        if (byte_idx < 16) begin
                            a_mat[byte_idx[3:2]][byte_idx[1:0]] <= rx_data;
                        end else begin
                            b_mat[(byte_idx - 6'd16) >> 2][(byte_idx - 6'd16) & 2'b11] <= rx_data;
                        end
                        byte_idx <= byte_idx + 1;
                        if (byte_idx == 6'd31) begin
                            load_done <= 1'b1;
                            rx_state  <= RX_WAIT_END;
                        end
                    end
                end

                RX_WAIT_END: begin
                    if (rx_valid && rx_data == 8'hFF) begin
                        rx_state <= RX_COMPUTE;
                    end
                end

                RX_COMPUTE: begin
                    
                    rx_state <= RX_WAIT_COMP;
                end

                RX_CLEAR_PRE: begin
                    clear <= 1'b1;
                    clear_cnt <= clear_cnt + 1;
                    if (clear_cnt == 3'd7) begin
                        start    <= 1'b1;    // single pulse after clear
                        rx_state <= RX_WAIT_COMP;
                    end
                end

                RX_WAIT_COMP: begin
                    start <= 1'b1;
                    // start is default 0 here
                    if (comp_done) begin
                        tx_idx   <= 6'd0;
                        rx_state <= RX_SEND;
                    end
                end

                RX_SEND: begin
                    begin
                        automatic logic [5:0] ridx = tx_idx / 3;
                        automatic logic [1:0] bidx = tx_idx % 3;
                        automatic logic [1:0] row  = ridx[3:2];
                        automatic logic [1:0] col  = ridx[1:0];
                        automatic logic [19:0] val = acc[row][col];
                        case (bidx)
                            2'd0: tx_data <= {4'b0, val[19:16]};
                            2'd1: tx_data <= val[15:8];
                            2'd2: tx_data <= val[7:0];
                            default: tx_data <= 8'd0;
                        endcase
                    end
                    tx_start   <= 1'b1;
                    tx_started <= 1'b0;  // reset flag, wait for busy to rise
                    rx_state   <= RX_WAIT_TX;
                end

                RX_WAIT_TX: begin
                    if (tx_busy)
                        tx_started <= 1'b1;  // tx has started
                    if (tx_started && !tx_busy) begin
                        // tx finished
                        tx_idx <= tx_idx + 1;
                        if (tx_idx == 6'd47)
                            rx_state <= RX_IDLE;
                        else
                            rx_state <= RX_SEND;
                    end
                end

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Status LEDs
    // -------------------------------------------------------------------------
    assign led_load_done = load_done;
    assign led_comp_done = comp_done;
    assign led_uart_done = (rx_state == RX_IDLE) && load_done;

endmodule: uart_shim


// =============================================================================
// UART RX
// =============================================================================
module uart_rx #(parameter CLKS_PER_BIT = 868) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [9:0]  clk_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  shift;
    logic        rx_sync1, rx_sync2;

    // two-flop synchronizer
    always_ff @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            clk_cnt <= '0;
            bit_idx <= '0;
            rx_data <= '0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (!rx_sync2) begin  // start bit detected
                        clk_cnt <= 10'd1;
                        state   <= START;
                    end
                end
                START: begin
                    if (clk_cnt == CLKS_PER_BIT/2) begin
                        // sample in middle of start bit
                        if (!rx_sync2) begin
                            clk_cnt <= '0;
                            bit_idx <= '0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE;  // false start
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt        <= '0;
                        shift[bit_idx] <= rx_sync2;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_valid <= 1'b1;
                        rx_data  <= shift;
                        clk_cnt  <= '0;
                        state    <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule: uart_rx


// =============================================================================
// UART TX
// =============================================================================
module uart_tx #(parameter CLKS_PER_BIT = 868) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx
);
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [9:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            tx      <= 1'b1;
            tx_busy <= 1'b0;
            clk_cnt <= '0;
            bit_idx <= '0;
            shift   <= '0;
        end else begin
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift   <= tx_data;
                        tx_busy <= 1'b1;
                        clk_cnt <= '0;
                        state   <= START;
                    end
                end
                START: begin
                    tx <= 1'b0;  // start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        bit_idx <= '0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                DATA: begin
                    tx <= shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                STOP: begin
                    tx <= 1'b1;  // stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule: uart_tx