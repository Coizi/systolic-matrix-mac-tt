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
    logic [15:0] shift_reg;

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