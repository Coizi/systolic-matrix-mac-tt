module pe 
    (input logic clk, 
    input logic rst_n, clear, start,
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
            a_reg <= 8'b0;
            b_reg <= 8'b0;
        end else if (start) begin
            a_reg <= a_in;
            b_reg <= b_in;
            acc <= acc + (a_reg * b_reg);
        end
    end

    assign a_out = a_reg;
    assign b_out = b_reg;

endmodule: pe