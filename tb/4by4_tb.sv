
class ArrayTransaction;

    rand logic [7:0] a_in [4][4];
    rand logic [7:0] b_in [4][4];

    constraint overflow_protection {
        foreach (a_in[i,j]) a_in[i][j] inside {[0:255]};
        foreach (b_in[i,j]) b_in[i][j] inside {[0:255]};
    }

endclass

module array_tb;
    logic clk, rst_n, clear, start;
    logic [7:0] a_in [4][4];
    logic [7:0] b_in [4][4];
    logic [19:0] acc [4][4];
    logic comp_done;
    //test vars
    logic [19:0] expected [4][4];
    int pass_count;

    systolic_array_4x4 DUT (.*);

        initial begin   
            clk = 0;
            clear = 0;
            start = 0;
            rst_n = 0;
            #10;
            rst_n <= 1; 
            forever #10 clk = ~clk;
        end

        initial begin
            automatic ArrayTransaction txn = new();
            foreach (a_in[i,j]) a_in[i][j] = 0;
            foreach (b_in[i,j]) b_in[i][j] = 0;
            @(posedge clk);
            @(posedge clk);
            pass_count = 0;
            repeat(1000) begin
                assert(txn.randomize()) else $fatal(1, "randomize failed");
                check_array(txn.a_in, txn.b_in);
            end
            $display("1000 tests done");
            $display("%0d/1000 tests passed", pass_count);

            //set edge cases
            //0s
            foreach (a_in[i,j]) a_in[i][j] = 8'd0;
            foreach (b_in[i,j]) b_in[i][j] = 8'd0;
            check_array(a_in, b_in);
            //maxed
            foreach (a_in[i,j]) a_in[i][j] = 8'd255;
            foreach (b_in[i,j]) b_in[i][j] = 8'd255;
            check_array(a_in, b_in);

            //identity
            foreach (b_in[i,j]) begin
                if (i == j) b_in[i][j] = 8'd1;
                else b_in[i][j] = 8'd0;
            end
            foreach (a_in[i,j]) begin
                if (i == j) a_in[i][j] = 8'd1;
                else a_in[i][j] = 8'd0;
            end
            check_array(a_in, b_in);
            $display("1003 tests done");
            $display("%0d/1003 tests passed", pass_count);
            $finish;
        end

        task automatic check_array(input logic [7:0] a [4][4],
            input logic [7:0] b [4][4]);
            
            a_in = a;
            b_in = b;
            clear = 1'b1;
            @(posedge clk);
            clear = 1'b0;
            @(posedge clk);
            start = 1'b1;
            while (!comp_done) @(posedge clk);
            @(posedge clk); @(posedge clk);
            start = 0;
            compute_expected(a, b);
            if (acc != expected) begin
                $display("FAIL");
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        if (acc[i][j] !== expected[i][j])
                            $display("  acc[%0d][%0d]: expected=%0d, got=%0d", i, j, expected[i][j], acc[i][j]);
            end
            else
                pass_count++;

        
        endtask

        function automatic void compute_expected(
            input logic [7:0] a [4][4],
            input logic [7:0] b [4][4]
        );

            foreach (expected[i, j]) expected[i][j] = 0;

            for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
            for (int k = 0; k < 4; k++) begin
                expected[i][j] = expected[i][j] + (a[i][k] * b[k][j]);
                    end
                end
            end

        endfunction

endmodule