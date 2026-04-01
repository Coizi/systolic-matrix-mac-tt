module spi_slave 
    (input logic clk, rst_n,
     input logic sck, mosi, cs,
     output logic [7:0] a_out [4][4],
     output logic [7:0] b_out [4][4],
     output logic load_done
    );

    logic sck_sync, mosi_sync, cs_sync;
    logic sck_prev, sck_curr;
    logic rising_edge;
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic [5:0] byte_cnt;
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
        end else begin
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