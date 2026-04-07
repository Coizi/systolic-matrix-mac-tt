module tt_um_systolic_top (
    input  logic [7:0] ui_in,    // dedicated inputs
    output logic [7:0] uo_out,   // dedicated outputs
    input  logic [7:0] uio_in,   // bidirectional inputs
    output logic [7:0] uio_out,  // bidirectional outputs
    output logic [7:0] uio_oe,   // bidirectional output enable (1=output)
    input  logic       ena,      // design enable
    input  logic       clk,      // clock
    input  logic       rst_n     // active-low reset
);

    // Pin mapping
    // ui_in[0] = SCK
    // ui_in[1] = MOSI
    // ui_in[2] = CS
    // uo_out[0] = MISO
    // uo_out[1] = comp_done
    // uo_out[2] = load_done
    // uo_out[3] = spi_done
    // uo_out[7:4] = unused (tied 0)
    // uio = unused (all inputs)

    logic sck, mosi, cs;
    assign sck  = ui_in[0];
    assign mosi = ui_in[1];
    assign cs   = ui_in[2];

    // bidirectional pins all unused
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

  
    
    logic [7:0] a_in [4][4];
    logic [7:0] b_in [4][4];
    logic [19:0] acc [4][4];

    logic load_done, comp_done, spi_done;
    logic clear, start, spi_tx_en;
    logic miso;
    

    //module instantiations
    spi_slave u_spi_slave (
        .clk      (clk),
        .rst_n    (rst_n),
        .sck      (sck),
        .mosi     (mosi),
        .cs       (cs),
        .a_out    (a_in),
        .b_out    (b_in),
        .load_done(load_done)
    );

    control_fsm u_control_fsm (
        .clk      (clk),
        .rst_n    (rst_n),
        .load_done(load_done),
        .comp_done(comp_done),
        .out_done (spi_done),
        .clear    (clear),
        .start    (start),
        .spi_tx_en(spi_tx_en)
    );

    systolic_array_4x4 u_systolic (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear),
        .start    (start),
        .a_in     (a_in),
        .b_in     (b_in),
        .acc      (acc),
        .comp_done(comp_done)
    );

    spi_tx u_spi_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .sck      (sck),
        .cs       (cs),
        .spi_tx_en(spi_tx_en),
        .acc      (acc),
        .miso     (miso),
        .spi_done (spi_done)
    );

    //output assignments
    assign uo_out = ena ? {4'b0, spi_done, load_done, comp_done, miso} : 8'b0;
endmodule: tt_um_systolic_top