

class PETransaction;
    rand logic [7:0] a_in;
    rand logic [7:0] b_in;

    constraint overflow_protection {
        a_in inside {[0:15]};
        b_in inside {[0:15]};
    }

endclass

module pe_tb;
    logic clk, rst_n, clear, start;
    logic [7:0] a_in, b_in;
    logic [7:0] a_out, b_out;
    logic [19:0] acc;
    logic [19:0] expected;
    int pass_count;

    pe DUT(.*);

    initial begin
        $monitor($time,,
        "Ain: %d, Bin: %d, Aout: %d, Bout: %d, Acc: %d",
        a_in, b_in, a_out, b_out, acc);
        clk = 0;
        clear = 0;
        start = 0;
        rst_n = 0;
        rst_n <= 1; 
        forever #10 clk = ~clk;
    end

    initial begin
        automatic PETransaction txn = new();
        a_in = 0; b_in = 0;
        @(posedge clk); @(posedge clk);
        pass_count = 0;
        repeat(1000) begin
            assert(txn.randomize()) else $fatal(1, "randomize failed");
            $display("a=%0d b=%0d", txn.a_in, txn.b_in);
            drive_and_check(txn.a_in, txn.b_in);
        end
        $display("1000 tests done");
        $display("%0d/1000 tests passed", pass_count);
        $finish;

    end

    task automatic drive_and_check(input logic [7:0] a, b);
        a_in = a;
        b_in = b;
        start = 1'b1;
        @(posedge clk);
        a_in = 0;
        b_in = 0;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        @(posedge clk);
        expected = 20'(a) * 20'(b);
        if (acc !== expected)
            $display("FAIL a=%0d b=%0d expected=%0d got=%0d", a, b, expected, acc);
        else
            pass_count++;
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        endtask

endmodule: pe_tb
