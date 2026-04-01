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
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    output logic [7:0] count
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 8'b00000000;
        end else if (en) begin
            count <= count + 1'b1;
        end
    end

endmodule: Counter