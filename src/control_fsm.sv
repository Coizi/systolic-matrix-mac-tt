module control_fsm 
    (input logic clk, rst_n,
    input logic load_done, out_done, comp_done,
    output logic clear, start,
    output logic spi_tx_en
    );

typedef enum logic [2:0] {IDLE, CLEAR, LOAD, COMPUTE, DRAIN} state_t;
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
        CLEAR: begin
            clear = 1'b1;
            nextState = LOAD;
        end
        LOAD: begin
            start = 1'b1;
            nextState = COMPUTE;
        end
        COMPUTE : begin
            start = 1'b1;
            if (comp_done) nextState = DRAIN;
        end
        DRAIN : begin
            spi_tx_en = 1'b1;
            if (out_done) nextState = IDLE;
        end
    endcase
end

endmodule: control_fsm