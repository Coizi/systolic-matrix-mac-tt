
module pe 
    (input logic clk, 
    input logic rst_n, clear,
    input logic [7:0] a_in, b_in,
    output logic [7:0] a_out, b_out,
    output logic [19:0] acc);

    logic [7:0] a_reg, b_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= 8'b0;
            b_reg <= 8'b0;
            acc <= 20'b0;
        end else if (clear) begin
            acc <= 20'b0;
        end else begin
            a_reg <= a_in;
            b_reg <= b_in;
            acc <= acc + (a_reg * b_reg);
        end
    end

    assign a_out = a_reg;
    assign b_out = b_reg;

endmodule: pe

module systolic_array_4x4
    (input logic clk,
    input logic rst_n, clear,
    input logic start,
    input logic [7:0] a_in [4][4], 
    input logic [7:0] b_in [4][4],
    output logic [19:0] acc [4][4],
    output logic comp_done);
    
    logic [7:0] a_wire [4][4];
    logic [7:0] b_wire [4][4];

    logic [7:0] boundary_a [3:0];
    logic [7:0] boundary_b [3:0];

    logic [3:0] cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 4'd0;
        else if (clear)
            cnt <= 4'd0;
        else if (start)
            cnt <= cnt + 4'd1;
    end

    genvar k;
    generate
        for (k = 0; k < 4; k++) begin : gen_boundary_a
            assign boundary_a[k] = (cnt >= k && cnt - k < 4) ? a_in[k][cnt-k] : 8'd0;
        end
        for (k = 0; k < 4; k++) begin : gen_boundary_b
            assign boundary_b[k] = (cnt >= k && cnt - k < 4) ? b_in[cnt-k][k] : 8'd0;
        end
    endgenerate

    assign done = (cnt == 4'd7);


    genvar i, j;
    generate
         for (i = 0; i < 4; i++) begin : gen_row
            for (j = 0; j < 4; j++) begin : gen_col
                pe leaf (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(clear),
                    .a_in(j == 0 ? boundary_a[i] : a_wire[i][j-1]),
                    .b_in(i == 0 ? boundary_b[j] : b_wire[i-1][j]),
                    .a_out(a_wire[i][j]),
                    .b_out(b_wire[i][j]),
                    .acc(acc[i][j])
                );
            end : gen_col
         end : gen_row
    endgenerate

endmodule: systolic_array_4x4


module control_fsm 
    (input logic clk, rst_n,
    input logic load_done, out_done, comp_done,
    output logic clear, start,
    output logic spi_tx_en
    );

typedef enum logic [1:0] {IDLE, LOAD, COMPUTE, DRAIN} state_t;
state_t currState, nextState;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) currState <= IDLE;
    else currState <= nextState;
end

always_comb begin
    nextState = currState;
    clear = 1'b0;
    start = 1'b0;
    spi_tx_en =  1'b0;

    case (currState)
        IDLE: begin
            if (load_done) begin
                nextState = LOAD;
            end
        end
        LOAD: begin
            clear = 1'b1;
            start = 1'b1;
            nextState = COMPUTE;
        end
        COMPUTE : begin
            if (comp_done) nextState = DRAIN;
        end
        DRAIN : begin
            spi_tx_en = 1'b1;
            if (out_done) nextState = IDLE;
        end
    endcase
end

endmodule: control_fsm

module spi_slave 
    (input logic clk, rst_n,
     input logic sck, mosi, cs,
     output logic [7:0] a_out [4][4],
     output logic [7:0] b_out [4][4],
     output logic load_done
    );


    logic sck_sync, mosi_sync, cs_sync;  // synchronizer outputs
    logic sck_prev, sck_curr;             // edge detection
    logic rising_edge;                    // SCK rising edge pulse
    logic [7:0] shift_reg;               // incoming bit accumulator
    logic [2:0] bit_cnt;                 // counts 0-7 within a byte
    logic [5:0] byte_cnt;                // counts 0-32 across the frame
    logic cs_prev;

    assign rising_edge = sck_curr & ~sck_prev;

    Synchronizer s0 (.async(sck), .clk(clk), .sync(sck_sync)),
                 s1 (.async(mosi), .clk(clk), .sync(mosi_sync)),
                 s2 (.async(cs), .clk(clk), .sync(cs_sync));
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'd0;
            byte_cnt <= 6'd0;
            shift_reg <= 8'd0;
            load_done <= 1'd0;
        end  else begin
            sck_prev <= sck_curr;
            sck_curr <= sck_sync;

        cs_prev <= cs_sync;
        if (cs_sync && !cs_prev) begin
            bit_cnt <= 3'd0;
            byte_cnt <= 6'd0;
            load_done <= 1'd0;
        end

        if (rising_edge && !cs_sync) begin

            shift_reg[7:0] <= {shift_reg[6:0], mosi_sync};
            bit_cnt <= bit_cnt + 1;


            if (byte_cnt == 32) load_done <= 1'b1;

            //write bytes
            if (bit_cnt == 3'd7) begin
                byte_cnt <= byte_cnt + 1;
            
                if (byte_cnt == 0) begin
                    // ignore
                end else if (byte_cnt < 17) begin
                    a_out[(byte_cnt - 1) / 4][(byte_cnt - 1) % 4] <= shift_reg;
                end else if (byte_cnt >= 17) begin
                    b_out[(byte_cnt - 17) / 4][(byte_cnt - 17) % 4] <= shift_reg;
                end
            end
        end
    end
    end


endmodule: spi_slave



module spi_tx(
    input logic clk, rst_n,
    input logic sck, cs,
    input logic spi_tx_en,
    input logic [19:0] acc [4][4],
    output logic miso,
    output logic spi_done
);
    logic sck_curr, sck_prev, cs_prev, cs_curr;
    logic sck_sync, cs_sync;
    logic falling_edge;
    logic [2:0] bit_cnt;
    logic [3:0] byte_cnt;
    logic [15:0] shift_reg; //truncates the 20-bit acc to

    assign falling_edge = ~sck_curr & sck_prev;

    Synchronizer s0 (.async(sck), .clk(clk), .sync(sck_sync)),
                 s1 (.async(cs), .clk(clk), .sync(cs_sync));

    assign miso = shift_reg[15];
    always_ff @(posedge clk or negedge rst_n) begin  
        
        if (!rst_n) begin
            bit_cnt <= 3'd0;
            byte_cnt <= 4'd0;
            shift_reg <= 16'd0;
            spi_done <= 1'b0;
          
        end else begin
            sck_prev <= sck_curr;
            sck_curr <= sck_sync;
            cs_prev <= cs_sync;

            if (cs_sync && !cs_prev) begin
            bit_cnt <= 3'd0;
            byte_cnt <= 4'd0;
         
            end
        



        if (falling_edge && !cs_sync && spi_tx_en) begin
            
            shift_reg[15:0] <= {shift_reg[14:0], 1'd0};
            bit_cnt <= bit_cnt + 1;
            if (bit_cnt == 0) begin
                shift_reg <= acc[byte_cnt / 4][byte_cnt % 4][15:0];
            end else begin
                shift_reg <= {shift_reg[14:0], 1'b0};
            end

        
            if (bit_cnt == 7) begin
                byte_cnt <= byte_cnt + 1;
            end

            if ((bit_cnt == 7) && (byte_cnt == 15)) begin
                spi_done <= 1'b1;
            end
        end


        end
    end


endmodule: spi_tx




module DFlipFlop
  (input  logic d,
   input  logic preset_L, reset_L, clk,
   output logic q);

  always_ff @(posedge clk, negedge preset_L, negedge reset_L)
    if (~preset_L & reset_L)
      q <= 1'b1;
    else if (~reset_L & preset_L)
      q <= 1'b0;
    else if (~reset_L & ~preset_L)
      q <= 1'bX;
    else
      q <= d;

endmodule : DFlipFlop


module Synchronizer
  (input  logic async, clk,
   output logic sync);

  logic metastable;

  DFlipFlop one(.d(async),
                .q(metastable),
                .clk,
                .preset_L(1'b1),
                .reset_L(1'b1)
               );

  DFlipFlop two(.d(metastable),
                .q(sync),
                .clk,
                .preset_L(1'b1),
                .reset_L(1'b1)
               );

endmodule : Synchronizer

module Counter (
    input  logic       clk,    // Clock
    input  logic       rst_n,    // Active-high reset
    input  logic       en,     // Enable
    output logic [7:0] count   // 4-bit output
);

    // Always block triggered on positive edge of clock or reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 8'b00000000; // Reset counter
        end else if (en) begin
            count <= count + 1'b1; // Increment counter
        end
    end

endmodule: Counter