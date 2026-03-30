
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
    output logic done);
    
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
