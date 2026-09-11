//------------------------------------------------------------------------------
//  (c) Copyright 2013-2018 Xilinx, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of Xilinx, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  Xilinx, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) Xilinx shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or Xilinx had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  Xilinx products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of Xilinx products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//------------------------------------------------------------------------------


`timescale 1ps/1ps

// =====================================================================================================================
// This example design wrapper module instantiates the core and any helper blocks which the user chose to exclude from
// the core, connects them as appropriate, and maps enabled ports
// =====================================================================================================================

module gtwizard_ultrascale_1_example_wrapper (
  input  wire [0:0] gtyrxn_in
 ,input  wire [0:0] gtyrxp_in
 ,output wire [0:0] gtytxn_out
 ,output wire [0:0] gtytxp_out
 ,input  wire [0:0] gtwiz_userclk_tx_reset_in
 ,output wire [0:0] gtwiz_userclk_tx_srcclk_out
 ,output wire [0:0] gtwiz_userclk_tx_usrclk_out
 ,output wire [0:0] gtwiz_userclk_tx_usrclk2_out
 ,output wire [0:0] gtwiz_userclk_tx_active_out
 ,input  wire [0:0] gtwiz_userclk_rx_reset_in
 ,output wire [0:0] gtwiz_userclk_rx_srcclk_out
 ,output wire [0:0] gtwiz_userclk_rx_usrclk_out
 ,output wire [0:0] gtwiz_userclk_rx_usrclk2_out
 ,output wire [0:0] gtwiz_userclk_rx_active_out

 ,input  wire [0:0] gtwiz_reset_clk_freerun_in
 ,input  wire [0:0] gtwiz_reset_all_in
 ,input  wire [0:0] gtwiz_reset_tx_pll_and_datapath_in
 ,input  wire [0:0] gtwiz_reset_tx_datapath_in
 ,input  wire [0:0] gtwiz_reset_rx_pll_and_datapath_in
 ,input  wire [0:0] gtwiz_reset_rx_datapath_in
 ,output wire [0:0] gtwiz_reset_rx_cdr_stable_out
 ,output wire [0:0] gtwiz_reset_tx_done_out
 ,output wire [0:0] gtwiz_reset_rx_done_out
 ,input  wire [31:0] gtwiz_userdata_tx_in
 ,output wire [31:0] gtwiz_userdata_rx_out

//  ,input  wire [0:0] gtrefclk01_in
 ,input  wire [0:0] qpll1lock_in
 ,input  wire [0:0] qpll1outclk_in
 ,input  wire [0:0] qpll1outrefclk_in
 ,output wire [0:0] qpll1_rst_out
//  ,output wire [0:0] qpll0outclk_out
//  ,output wire [0:0] qpll0outrefclk_out
//  ,output wire [0:0] qpll1outclk_out
//  ,output wire [0:0] qpll1outrefclk_out
 ,input  wire [0:0] rx8b10ben_in
 ,input  wire [0:0] rxcommadeten_in
 ,input  wire [0:0] rxmcommaalignen_in
 ,input  wire [0:0] rxpcommaalignen_in
 ,input  wire [0:0] tx8b10ben_in
 ,input  wire [15:0] txctrl0_in
 ,input  wire [15:0] txctrl1_in
 ,input  wire [7:0] txctrl2_in
 ,output wire [0:0] gtpowergood_out
 ,output wire [0:0] rxbyteisaligned_out
 ,output wire [0:0] rxbyterealign_out
 ,output wire [0:0] rxcommadet_out
 ,output wire [15:0] rxctrl0_out
 ,output wire [15:0] rxctrl1_out
 ,output wire [7:0] rxctrl2_out
 ,output wire [7:0] rxctrl3_out
 ,output wire [0:0] rxpmaresetdone_out
 ,output wire [0:0] txpmaresetdone_out
 ,output wire [0:0] txprgdivresetdone_out
);


  // ===================================================================================================================
  // PARAMETERS AND FUNCTIONS
  // ===================================================================================================================

  // Declare and initialize local parameters and functions used for HDL generation
  localparam [191:0] P_CHANNEL_ENABLE = 192'b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001;
  `include "gtwizard_ultrascale_1_example_wrapper_functions.v"
  localparam integer P_TX_MASTER_CH_PACKED_IDX = f_calc_pk_mc_idx(0);
  localparam integer P_RX_MASTER_CH_PACKED_IDX = f_calc_pk_mc_idx(0);


  // ===================================================================================================================
  // HELPER BLOCKS
  // ===================================================================================================================

  // Any helper blocks which the user chose to exclude from the core will appear below. In addition, some signal
  // assignments related to optionally-enabled ports may appear below.

  // -------------------------------------------------------------------------------------------------------------------
  // Transmitter user clocking network helper block
  // -------------------------------------------------------------------------------------------------------------------

  wire [0:0] txusrclk_int;
  wire [0:0] txusrclk2_int;
  wire [0:0] txoutclk_int;

  // Generate a single module instance which is driven by a clock source associated with the master transmitter channel,
  // and which drives TXUSRCLK and TXUSRCLK2 for all channels

  // The source clock is TXOUTCLK from the master transmitter channel
  assign gtwiz_userclk_tx_srcclk_out = txoutclk_int[P_TX_MASTER_CH_PACKED_IDX];

  // Instantiate a single instance of the transmitter user clocking network helper block
  gtwizard_ultrascale_1_example_gtwiz_userclk_tx gtwiz_userclk_tx_inst (
    .gtwiz_userclk_tx_srcclk_in   (gtwiz_userclk_tx_srcclk_out),
    .gtwiz_userclk_tx_reset_in    (gtwiz_userclk_tx_reset_in),
    .gtwiz_userclk_tx_usrclk_out  (gtwiz_userclk_tx_usrclk_out),
    .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2_out),
    .gtwiz_userclk_tx_active_out  (gtwiz_userclk_tx_active_out)
  );

  // Drive TXUSRCLK and TXUSRCLK2 for all channels with the respective helper block outputs
  assign txusrclk_int  = {1{gtwiz_userclk_tx_usrclk_out}};
  assign txusrclk2_int = {1{gtwiz_userclk_tx_usrclk2_out}};

  // -------------------------------------------------------------------------------------------------------------------
  // Receiver user clocking network helper block
  // -------------------------------------------------------------------------------------------------------------------

  wire [0:0] rxusrclk_int;
  wire [0:0] rxusrclk2_int;
  wire [0:0] rxoutclk_int;

  // Generate a single module instance which is driven by a clock source associated with the master receiver channel,
  // and which drives RXUSRCLK and RXUSRCLK2 for all channels

  // The source clock is RXOUTCLK from the master receiver channel
  assign gtwiz_userclk_rx_srcclk_out = rxoutclk_int[P_RX_MASTER_CH_PACKED_IDX];

  // Instantiate a single instance of the receiver user clocking network helper block
  gtwizard_ultrascale_1_example_gtwiz_userclk_rx gtwiz_userclk_rx_inst (
    .gtwiz_userclk_rx_srcclk_in   (gtwiz_userclk_rx_srcclk_out),
    .gtwiz_userclk_rx_reset_in    (gtwiz_userclk_rx_reset_in),
    .gtwiz_userclk_rx_usrclk_out  (gtwiz_userclk_rx_usrclk_out),
    .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2_out),
    .gtwiz_userclk_rx_active_out  (gtwiz_userclk_rx_active_out)
  );

  // Drive RXUSRCLK and RXUSRCLK2 for all channels with the respective helper block outputs
  assign rxusrclk_int  = {1{gtwiz_userclk_rx_usrclk_out}};
  assign rxusrclk2_int = {1{gtwiz_userclk_rx_usrclk2_out}};

  // Required declarations to connect COMMON reset and lock signals to reset controller helper block within the core
  wire [0:0] gtwiz_reset_qpll1lock_int;
  wire [0:0] gtwiz_reset_qpll1reset_int;
  wire [0:0] gtpowergood_int;

  // Required assignment to expose the GTPOWERGOOD port per user request
  assign gtpowergood_out = gtpowergood_int;

  // ----------------------------------------------------------------------------------------------------------------
  // Assignments to expose data ports, or data control ports, per configuration requirement or user request
  // ----------------------------------------------------------------------------------------------------------------

  wire [15:0] txctrl0_int;

  // Required assignment to expose the TXCTRL0 port per configuration requirement or user request
  assign txctrl0_int = txctrl0_in;
  wire [15:0] txctrl1_int;

  // Required assignment to expose the TXCTRL1 port per configuration requirement or user request
  assign txctrl1_int = txctrl1_in;
  wire [15:0] rxctrl0_int;

  // Required assignment to expose the RXCTRL0 port per configuration requirement or user request
  assign rxctrl0_out = rxctrl0_int;
  wire [15:0] rxctrl1_int;

  // Required assignment to expose the RXCTRL1 port per configuration requirement or user request
  assign rxctrl1_out = rxctrl1_int;

  // ===================================================================================================================
  // TRANSCEIVER COMMON BLOCK
  // ===================================================================================================================

  wire [0:0] gtrefclk00_int;
  wire [0:0] qpll0clk_int;
  wire [0:0] qpll0refclk_int;
  wire [0:0] qpll0reset_int;
  wire [0:0] qpll0lock_int;

  // When QPLL0 is not used, the following assignments tie off QPLL0-related inputs as appropriate
  assign gtrefclk00_int  = {1{1'b0}};
  assign qpll0clk_int    = {1{1'b0}};
  assign qpll0refclk_int = {1{1'b0}};
  assign qpll0reset_int  = {1{1'b1}};

  wire [0:0] gtrefclk01_int;
  wire [0:0] qpll1clk_int;
  wire [0:0] qpll1refclk_int;

  // When QPLL1 is used, the following assignments support the use of the transceiver COMMON block in the example design
//   assign gtrefclk01_int = gtrefclk01_in;
  genvar gi_ch_to_cm1;
  generate for (gi_ch_to_cm1 = 0; gi_ch_to_cm1 < 1; gi_ch_to_cm1 = gi_ch_to_cm1 + 1) begin : gen_ch_to_cm1
    // assign qpll1clk_int    [gi_ch_to_cm1] = qpll1outclk_out    [f_idx_cm(gi_ch_to_cm1)];
    // assign qpll1refclk_int [gi_ch_to_cm1] = qpll1outrefclk_out [f_idx_cm(gi_ch_to_cm1)];
    assign qpll1clk_int    [gi_ch_to_cm1] = qpll1outclk_in     [f_idx_cm(gi_ch_to_cm1)];
    assign qpll1refclk_int [gi_ch_to_cm1] = qpll1outrefclk_in  [f_idx_cm(gi_ch_to_cm1)];
  end
  endgenerate

//   wire [0:0] qpll1reset_int;
//   wire [0:0] qpll1lock_int;
//   assign qpll1reset_int            = gtwiz_reset_qpll1reset_int;
//   assign gtwiz_reset_qpll1lock_int = qpll1lock_int;
  assign qpll1_rst_out             = gtwiz_reset_qpll1reset_int;
  assign gtwiz_reset_qpll1lock_int = qpll1lock_in;

  localparam [47:0] P_COMMON_ENABLE = f_pop_cm_en(0);

//   // The following HDL generate loop iterates across each possible transceiver quad, instantiating only the enabled
//   // transceiver COMMON blocks, each within a configuration-specific parameterization wrapper
//   genvar cm;
//   generate for (cm = 0; cm < 48; cm = cm + 1) begin : gen_common_container
//     if (P_COMMON_ENABLE[cm] == 1'b1) begin : gen_enabled_common

//       gtwizard_ultrascale_1_gtye4_common_wrapper gtye4_common_wrapper_inst (
//         .GTYE4_COMMON_BGBYPASSB         (1'b1),
//         .GTYE4_COMMON_BGMONITORENB      (1'b1),
//         .GTYE4_COMMON_BGPDB             (1'b1),
//         .GTYE4_COMMON_BGRCALOVRD        (5'b10000),
//         .GTYE4_COMMON_BGRCALOVRDENB     (1'b1),
//         .GTYE4_COMMON_DRPADDR           (16'b0000000000000000),
//         .GTYE4_COMMON_DRPCLK            (1'b0),
//         .GTYE4_COMMON_DRPDI             (16'b0000000000000000),
//         .GTYE4_COMMON_DRPEN             (1'b0),
//         .GTYE4_COMMON_DRPWE             (1'b0),
//         .GTYE4_COMMON_GTGREFCLK0        (1'b0),
//         .GTYE4_COMMON_GTGREFCLK1        (1'b0),
//         .GTYE4_COMMON_GTNORTHREFCLK00   (1'b0),
//         .GTYE4_COMMON_GTNORTHREFCLK01   (1'b0),
//         .GTYE4_COMMON_GTNORTHREFCLK10   (1'b0),
//         .GTYE4_COMMON_GTNORTHREFCLK11   (1'b0),
//         .GTYE4_COMMON_GTREFCLK00        (gtrefclk00_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_GTREFCLK01        (gtrefclk01_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_GTREFCLK10        (1'b0),
//         .GTYE4_COMMON_GTREFCLK11        (1'b0),
//         .GTYE4_COMMON_GTSOUTHREFCLK00   (1'b0),
//         .GTYE4_COMMON_GTSOUTHREFCLK01   (1'b0),
//         .GTYE4_COMMON_GTSOUTHREFCLK10   (1'b0),
//         .GTYE4_COMMON_GTSOUTHREFCLK11   (1'b0),
//         .GTYE4_COMMON_PCIERATEQPLL0     (3'b000),
//         .GTYE4_COMMON_PCIERATEQPLL1     (3'b000),
//         .GTYE4_COMMON_PMARSVD0          (8'b00000000),
//         .GTYE4_COMMON_PMARSVD1          (8'b00000000),
//         .GTYE4_COMMON_QPLL0CLKRSVD0     (1'b0),
//         .GTYE4_COMMON_QPLL0CLKRSVD1     (1'b0),
//         .GTYE4_COMMON_QPLL0FBDIV        (8'b00000000),
//         .GTYE4_COMMON_QPLL0LOCKDETCLK   (1'b0),
//         .GTYE4_COMMON_QPLL0LOCKEN       (1'b0),
//         .GTYE4_COMMON_QPLL0PD           (1'b1),
//         .GTYE4_COMMON_QPLL0REFCLKSEL    (3'b001),
//         .GTYE4_COMMON_QPLL0RESET        (qpll0reset_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL1CLKRSVD0     (1'b0),
//         .GTYE4_COMMON_QPLL1CLKRSVD1     (1'b0),
//         .GTYE4_COMMON_QPLL1FBDIV        (8'b00000000),
//         .GTYE4_COMMON_QPLL1LOCKDETCLK   (1'b0),
//         .GTYE4_COMMON_QPLL1LOCKEN       (1'b1),
//         .GTYE4_COMMON_QPLL1PD           (1'b0),
//         .GTYE4_COMMON_QPLL1REFCLKSEL    (3'b001),
//         .GTYE4_COMMON_QPLL1RESET        (qpll1reset_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLLRSVD1         (8'b00000000),
//         .GTYE4_COMMON_QPLLRSVD2         (5'b00000),
//         .GTYE4_COMMON_QPLLRSVD3         (5'b00000),
//         .GTYE4_COMMON_QPLLRSVD4         (8'b00000000),
//         .GTYE4_COMMON_RCALENB           (1'b1),
//         .GTYE4_COMMON_SDM0DATA          (25'b0000000000000000000000000),
//         .GTYE4_COMMON_SDM0RESET         (1'b0),
//         .GTYE4_COMMON_SDM0TOGGLE        (1'b0),
//         .GTYE4_COMMON_SDM0WIDTH         (2'b00),
//         .GTYE4_COMMON_SDM1DATA          (25'b0000000000000000000000000),
//         .GTYE4_COMMON_SDM1RESET         (1'b0),
//         .GTYE4_COMMON_SDM1TOGGLE        (1'b0),
//         .GTYE4_COMMON_SDM1WIDTH         (2'b00),
//         .GTYE4_COMMON_UBCFGSTREAMEN     (1'b0),
//         .GTYE4_COMMON_UBDO              (16'b0000000000000000),
//         .GTYE4_COMMON_UBDRDY            (1'b0),
//         .GTYE4_COMMON_UBENABLE          (1'b0),
//         .GTYE4_COMMON_UBGPI             (2'b00),
//         .GTYE4_COMMON_UBINTR            (2'b00),
//         .GTYE4_COMMON_UBIOLMBRST        (1'b0),
//         .GTYE4_COMMON_UBMBRST           (1'b0),
//         .GTYE4_COMMON_UBMDMCAPTURE      (1'b0),
//         .GTYE4_COMMON_UBMDMDBGRST       (1'b0),
//         .GTYE4_COMMON_UBMDMDBGUPDATE    (1'b0),
//         .GTYE4_COMMON_UBMDMREGEN        (4'b0000),
//         .GTYE4_COMMON_UBMDMSHIFT        (1'b0),
//         .GTYE4_COMMON_UBMDMSYSRST       (1'b0),
//         .GTYE4_COMMON_UBMDMTCK          (1'b0),
//         .GTYE4_COMMON_UBMDMTDI          (1'b0),
//         .GTYE4_COMMON_DRPDO             (),
//         .GTYE4_COMMON_DRPRDY            (),
//         .GTYE4_COMMON_PMARSVDOUT0       (),
//         .GTYE4_COMMON_PMARSVDOUT1       (),
//         .GTYE4_COMMON_QPLL0FBCLKLOST    (),
//         .GTYE4_COMMON_QPLL0LOCK         (qpll0lock_int      [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL0OUTCLK       (qpll0outclk_out    [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL0OUTREFCLK    (qpll0outrefclk_out [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL0REFCLKLOST   (),
//         .GTYE4_COMMON_QPLL1FBCLKLOST    (),
//         .GTYE4_COMMON_QPLL1LOCK         (qpll1lock_int      [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL1OUTCLK       (qpll1outclk_out    [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL1OUTREFCLK    (qpll1outrefclk_out [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
//         .GTYE4_COMMON_QPLL1REFCLKLOST   (),
//         .GTYE4_COMMON_QPLLDMONITOR0     (),
//         .GTYE4_COMMON_QPLLDMONITOR1     (),
//         .GTYE4_COMMON_REFCLKOUTMONITOR0 (),
//         .GTYE4_COMMON_REFCLKOUTMONITOR1 (),
//         .GTYE4_COMMON_RXRECCLK0SEL      (),
//         .GTYE4_COMMON_RXRECCLK1SEL      (),
//         .GTYE4_COMMON_SDM0FINALOUT      (),
//         .GTYE4_COMMON_SDM0TESTDATA      (),
//         .GTYE4_COMMON_SDM1FINALOUT      (),
//         .GTYE4_COMMON_SDM1TESTDATA      (),
//         .GTYE4_COMMON_UBDADDR           (),
//         .GTYE4_COMMON_UBDEN             (),
//         .GTYE4_COMMON_UBDI              (),
//         .GTYE4_COMMON_UBDWE             (),
//         .GTYE4_COMMON_UBMDMTDO          (),
//         .GTYE4_COMMON_UBRSVDOUT         (),
//         .GTYE4_COMMON_UBTXUART          ()
//       );

//     end
//   end
//   endgenerate


  // ===================================================================================================================
  // CORE INSTANCE
  // ===================================================================================================================

  // Instantiate the core, mapping its enabled ports to example design ports and helper blocks as appropriate
  gtwizard_ultrascale_1 gtwizard_ultrascale_1_inst (
    .gtyrxn_in                               (gtyrxn_in)
   ,.gtyrxp_in                               (gtyrxp_in)
   ,.gtytxn_out                              (gtytxn_out)
   ,.gtytxp_out                              (gtytxp_out)
   ,.gtwiz_userclk_tx_active_in              (gtwiz_userclk_tx_active_out)
   ,.gtwiz_userclk_rx_active_in              (gtwiz_userclk_rx_active_out)
   ,.gtwiz_reset_clk_freerun_in              (gtwiz_reset_clk_freerun_in)
   ,.gtwiz_reset_all_in                      (gtwiz_reset_all_in)
   ,.gtwiz_reset_tx_pll_and_datapath_in      (gtwiz_reset_tx_pll_and_datapath_in)
   ,.gtwiz_reset_tx_datapath_in              (gtwiz_reset_tx_datapath_in)
   ,.gtwiz_reset_rx_pll_and_datapath_in      (gtwiz_reset_rx_pll_and_datapath_in)
   ,.gtwiz_reset_rx_datapath_in              (gtwiz_reset_rx_datapath_in)
   ,.gtwiz_reset_qpll1lock_in                (gtwiz_reset_qpll1lock_int)
   ,.gtwiz_reset_rx_cdr_stable_out           (gtwiz_reset_rx_cdr_stable_out)
   ,.gtwiz_reset_tx_done_out                 (gtwiz_reset_tx_done_out)
   ,.gtwiz_reset_rx_done_out                 (gtwiz_reset_rx_done_out)
   ,.gtwiz_reset_qpll1reset_out              (gtwiz_reset_qpll1reset_int)
   ,.gtwiz_userdata_tx_in                    (gtwiz_userdata_tx_in)
   ,.gtwiz_userdata_rx_out                   (gtwiz_userdata_rx_out)
   ,.qpll0clk_in                             (qpll0clk_int)
   ,.qpll0refclk_in                          (qpll0refclk_int)
   ,.qpll1clk_in                             (qpll1clk_int)
   ,.qpll1refclk_in                          (qpll1refclk_int)
   ,.rx8b10ben_in                            (rx8b10ben_in)
   ,.rxcommadeten_in                         (rxcommadeten_in)
   ,.rxmcommaalignen_in                      (rxmcommaalignen_in)
   ,.rxpcommaalignen_in                      (rxpcommaalignen_in)
   ,.rxusrclk_in                             (rxusrclk_int)
   ,.rxusrclk2_in                            (rxusrclk2_int)
   ,.tx8b10ben_in                            (tx8b10ben_in)
   ,.txctrl0_in                              (txctrl0_int)
   ,.txctrl1_in                              (txctrl1_int)
   ,.txctrl2_in                              (txctrl2_in)
   ,.txusrclk_in                             (txusrclk_int)
   ,.txusrclk2_in                            (txusrclk2_int)
   ,.gtpowergood_out                         (gtpowergood_int)
   ,.rxbyteisaligned_out                     (rxbyteisaligned_out)
   ,.rxbyterealign_out                       (rxbyterealign_out)
   ,.rxcommadet_out                          (rxcommadet_out)
   ,.rxctrl0_out                             (rxctrl0_int)
   ,.rxctrl1_out                             (rxctrl1_int)
   ,.rxctrl2_out                             (rxctrl2_out)
   ,.rxctrl3_out                             (rxctrl3_out)
   ,.rxoutclk_out                            (rxoutclk_int)
   ,.rxpmaresetdone_out                      (rxpmaresetdone_out)
   ,.txoutclk_out                            (txoutclk_int)
   ,.txpmaresetdone_out                      (txpmaresetdone_out)
   ,.txprgdivresetdone_out                   (txprgdivresetdone_out)
);

endmodule
