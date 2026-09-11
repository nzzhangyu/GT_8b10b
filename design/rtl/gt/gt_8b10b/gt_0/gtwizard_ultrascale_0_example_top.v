`timescale 1ps/1ps

// ============================================================================
// GTY 8B/10B product integration top (single channel)
//
// Derived from the Xilinx GT Wizard example_top structure, with the following
// demonstration-only resources removed:
//   * PRBS stimulus/checker
//   * PRBS-based link state machine
//   * example_init retry controller
//   * VIO and VIO-only synchronizers
//
// IMPORTANT:
//   1. This file does not replace or modify the generated example_top.
//   2. Sections marked "USER TODO" must be connected to project-specific RTL.
//   3. The TXCTRL/RXCTRL bit meanings must be checked against the exact GT
//      Wizard configuration and the generated product guide/example design.
// ============================================================================

module gtwizard_ultrascale_0_example_top (
    // GT reference clock input
    // input  wire mgtrefclk0,
    input  wire qpll0lock_in,
    input  wire qpll0clk_in,
    input  wire qpll0outrefclk_in,
    output wire qpll0_rst_out,

    // GT serial interface, channel 0
    input  wire ch0_gtyrxn_in,
    input  wire ch0_gtyrxp_in,
    output wire ch0_gtytxn_out,
    output wire ch0_gtytxp_out,

    // GT Wizard reset
    input  wire gtwiz_reset_clk_freerun_in,
    input  wire gtwiz_reset_all_in,
    input  wire gtwiz_reset_tx_datapath_in,
    input  wire gtwiz_reset_rx_datapath_in,

    // TX/RX data
    input  wire [31:0] txdata_in,
    input  wire [15:0] txctrl0_in,
    input  wire [15:0] txctrl1_in,
    input  wire [7:0]  txctrl2_in,

    output wire [31:0] rxdata_out,
    output wire [15:0] rxctrl0_out,
    output wire [15:0] rxctrl1_out,
    output wire [7:0]  rxctrl2_out,
    output wire [7:0]  rxctrl3_out,

    // User clocks exported for project TX/RX logic
    // output wire        tx_usrclk_out,
    output wire        tx_usrclk2_out,
    // output wire        rx_usrclk_out,
    output wire        rx_usrclk2_out,
    // output wire        tx_userclk_active_out,
    // output wire        rx_userclk_active_out,

    // Initialization and alignment status
    output wire        tx_reset_done_out,
    output wire        rx_reset_done_out,
    // output wire        rx_cdr_stable_out,
    // output wire        gtpowergood_out,
    // output wire        rxbyteisaligned_out,
    output wire        rxbyterealign_out
    // output wire        rxcommadet_out
);

    // ========================================================================== 
    // GT WIZARD VECTOR INTERFACE
    // ========================================================================== 

    wire [0:0]  gtyrxn_int;
    wire [0:0]  gtyrxp_int;
    wire [0:0]  gtytxn_int;
    wire [0:0]  gtytxp_int;

    assign gtyrxn_int[0] = ch0_gtyrxn_in;
    assign gtyrxp_int[0] = ch0_gtyrxp_in;
    assign ch0_gtytxn_out = gtytxn_int[0];
    assign ch0_gtytxp_out = gtytxp_int[0];

    wire [0:0]  gtwiz_userclk_tx_reset_int;
    wire [0:0]  gtwiz_userclk_tx_srcclk_int;
    wire [0:0]  gtwiz_userclk_tx_usrclk_int;
    wire [0:0]  gtwiz_userclk_tx_usrclk2_int;
    wire [0:0]  gtwiz_userclk_tx_active_int;

    // assign tx_usrclk_out         = gtwiz_userclk_tx_usrclk_int[0];
    assign tx_usrclk2_out        = gtwiz_userclk_tx_usrclk2_int[0];

    wire [0:0]  gtwiz_userclk_rx_reset_int;
    wire [0:0]  gtwiz_userclk_rx_srcclk_int;
    wire [0:0]  gtwiz_userclk_rx_usrclk_int;
    wire [0:0]  gtwiz_userclk_rx_usrclk2_int;
    wire [0:0]  gtwiz_userclk_rx_active_int;

    // assign rx_usrclk_out         = gtwiz_userclk_rx_usrclk_int[0];
    assign rx_usrclk2_out        = gtwiz_userclk_rx_usrclk2_int[0];

    wire [0:0]  gtwiz_reset_tx_done_int;
    wire [0:0]  gtwiz_reset_rx_done_int;
    wire [0:0]  gtwiz_reset_rx_cdr_stable_int;

    assign tx_reset_done_out     = gtwiz_reset_tx_done_int[0];
    assign rx_reset_done_out     = gtwiz_reset_rx_done_int[0];

    wire [31:0] gtwiz_userdata_tx_int;
    wire [31:0] gtwiz_userdata_rx_int;

    assign gtwiz_userdata_tx_int = txdata_in;
    assign rxdata_out            = gtwiz_userdata_rx_int;

    // wire [0:0]  gtrefclk00_int;
    // wire [0:0]  qpll0outclk_int;
    // wire [0:0]  qpll0outrefclk_int;
    // wire [0:0]  qpll1outclk_int;
    // wire [0:0]  qpll1outrefclk_int;

    // 8B/10B and comma alignment are enabled as in the supplied example.
    // USER TODO: confirm that the product protocol uses automatic comma
    // alignment. If alignment is handled in user RTL, revise these controls.
    wire [0:0]  rx8b10ben_int;
    wire [0:0]  rxcommadeten_int;
    wire [0:0]  rxmcommaalignen_int;
    wire [0:0]  rxpcommaalignen_int;
    wire [0:0]  tx8b10ben_int;

    assign rx8b10ben_int[0]         = 1'b1;
    assign rxcommadeten_int[0]      = 1'b1;
    assign rxmcommaalignen_int[0]   = 1'b1;
    assign rxpcommaalignen_int[0]   = 1'b1;
    assign tx8b10ben_int[0]         = 1'b1;

    wire [15:0] txctrl0_int;
    wire [15:0] txctrl1_int;
    wire [7:0]  txctrl2_int;

    assign txctrl0_int = txctrl0_in;
    assign txctrl1_int = txctrl1_in;
    assign txctrl2_int = txctrl2_in;

    wire [15:0] rxctrl0_int;
    wire [15:0] rxctrl1_int;
    wire [7:0]  rxctrl2_int;
    wire [7:0]  rxctrl3_int;

    assign rxctrl0_out = rxctrl0_int;
    assign rxctrl1_out = rxctrl1_int;
    assign rxctrl2_out = rxctrl2_int;
    assign rxctrl3_out = rxctrl3_int;

    wire [0:0]  gtpowergood_int;
    wire [0:0]  rxbyteisaligned_int;
    wire [0:0]  rxbyterealign_int;
    wire [0:0]  rxcommadet_int;
    wire [0:0]  rxpmaresetdone_int;
    wire [0:0]  txpmaresetdone_int;
    wire [0:0]  txprgdivresetdone_int;

    assign rxbyterealign_out     = rxbyterealign_int[0];

    // The selected TXOUTCLK source is TXPROGDIVCLK. Hold the TX user-clock
    // helper in reset until both the TX PMA and programmable divider are ready.
    assign gtwiz_userclk_tx_reset_int[0] =
        ~(txprgdivresetdone_int[0] && txpmaresetdone_int[0]);

    // The selected RXOUTCLK source is RXOUTCLKPMA. Hold the RX user-clock
    // helper in reset until the RX PMA clock source is ready.
    assign gtwiz_userclk_rx_reset_int[0] = ~rxpmaresetdone_int[0];

    // ========================================================================== 
    // GT WIZARD EXAMPLE WRAPPER
    // ========================================================================== 

    gtwizard_ultrascale_0_example_wrapper example_wrapper_inst (
        .gtyrxn_in                          (gtyrxn_int),
        .gtyrxp_in                          (gtyrxp_int),
        .gtytxn_out                         (gtytxn_int),
        .gtytxp_out                         (gtytxp_int),

        .gtwiz_userclk_tx_reset_in          (gtwiz_userclk_tx_reset_int),
        .gtwiz_userclk_tx_srcclk_out        (gtwiz_userclk_tx_srcclk_int),
        .gtwiz_userclk_tx_usrclk_out        (gtwiz_userclk_tx_usrclk_int),
        .gtwiz_userclk_tx_usrclk2_out       (gtwiz_userclk_tx_usrclk2_int),
        .gtwiz_userclk_tx_active_out        (gtwiz_userclk_tx_active_int),

        .gtwiz_userclk_rx_reset_in          (gtwiz_userclk_rx_reset_int),
        .gtwiz_userclk_rx_srcclk_out        (gtwiz_userclk_rx_srcclk_int),
        .gtwiz_userclk_rx_usrclk_out        (gtwiz_userclk_rx_usrclk_int),
        .gtwiz_userclk_rx_usrclk2_out       (gtwiz_userclk_rx_usrclk2_int),
        .gtwiz_userclk_rx_active_out        (gtwiz_userclk_rx_active_int),

        .gtwiz_reset_clk_freerun_in         ({1{gtwiz_reset_clk_freerun_in}}),
        .gtwiz_reset_all_in                 ({1{gtwiz_reset_all_in}}),

        .gtwiz_reset_tx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_tx_datapath_in         ({1{gtwiz_reset_tx_datapath_in}}),
        .gtwiz_reset_rx_pll_and_datapath_in (1'b0),
        .gtwiz_reset_rx_datapath_in         ({1{gtwiz_reset_rx_datapath_in}}),
        .gtwiz_reset_rx_cdr_stable_out      (gtwiz_reset_rx_cdr_stable_int),
        .gtwiz_reset_tx_done_out            (gtwiz_reset_tx_done_int),
        .gtwiz_reset_rx_done_out            (gtwiz_reset_rx_done_int),
        .gtwiz_userdata_tx_in               (gtwiz_userdata_tx_int),
        .gtwiz_userdata_rx_out              (gtwiz_userdata_rx_int),

        // .gtrefclk00_in                      (gtrefclk00_int),
        .qpll0lock_in                       (qpll0lock_in),
        .qpll0outclk_in                     (qpll0clk_in),
        .qpll0outrefclk_in                  (qpll0outrefclk_in),
        .qpll0_rst_out                      (qpll0_rst_out),
        // .qpll0outclk_out                    (qpll0outclk_int),
        // .qpll0outrefclk_out                 (qpll0outrefclk_int),
        // .qpll1outclk_out                    (qpll1outclk_int),
        // .qpll1outrefclk_out                 (qpll1outrefclk_int),
        
        .rx8b10ben_in                       (rx8b10ben_int),
        .rxcommadeten_in                    (rxcommadeten_int),
        .rxmcommaalignen_in                 (rxmcommaalignen_int),
        .rxpcommaalignen_in                 (rxpcommaalignen_int),

        .tx8b10ben_in                       (tx8b10ben_int),
        .txctrl0_in                         (txctrl0_int),
        .txctrl1_in                         (txctrl1_int),
        .txctrl2_in                         (txctrl2_int),
        .gtpowergood_out                    (gtpowergood_int),
        .rxbyteisaligned_out                (rxbyteisaligned_int),
        .rxbyterealign_out                  (rxbyterealign_int),
        .rxcommadet_out                     (rxcommadet_int),
        .rxctrl0_out                        (rxctrl0_int),
        .rxctrl1_out                        (rxctrl1_int),
        .rxctrl2_out                        (rxctrl2_int),
        .rxctrl3_out                        (rxctrl3_int),
        .rxpmaresetdone_out                 (rxpmaresetdone_int),
        .txpmaresetdone_out                 (txpmaresetdone_int),
        .txprgdivresetdone_out              (txprgdivresetdone_int)
    );

endmodule
