 ///////////////////////////////////////////////////////////////////////////////
 //
 // Project:  Aurora 64B/66B
 // Company:  Xilinx
 //
 //
 //
 // (c) Copyright 2008 - 2009 Xilinx, Inc. All rights reserved.
 //
 // This file contains confidential and proprietary information
 // of Xilinx, Inc. and is protected under U.S. and
 // international copyright and other intellectual property
 // laws.
 //
 // DISCLAIMER
 // This disclaimer is not a license and does not grant any
 // rights to the materials distributed herewith. Except as
 // otherwise provided in a valid license issued to you by
 // Xilinx, and to the maximum extent permitted by applicable
 // law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
 // WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
 // AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
 // BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
 // INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
 // (2) Xilinx shall not be liable (whether in contract or tort,
 // including negligence, or under any other theory of
 // liability) for any loss or damage of any kind or nature
 // related to, arising under or in connection with these
 // materials, including for any direct, or any indirect,
 // special, incidental, or consequential loss or damage
 // (including loss of data, profits, goodwill, or any type of
 // loss or damage suffered as a result of any action brought
 // by a third party) even if such damage or loss was
 // reasonably foreseeable or Xilinx had been advised of the
 // possibility of the same.
 //
 // CRITICAL APPLICATIONS
 // Xilinx products are not designed or intended to be fail-
 // safe, or for use in any application requiring fail-safe
 // performance, such as life-support or safety devices or
 // systems, Class III medical devices, nuclear facilities,
 // applications related to the deployment of airbags, or any
 // other applications that could lead to death, personal
 // injury, or severe property or environmental damage
 // (individually and collectively, "Critical
 // Applications"). Customer assumes the sole risk and
 // liability of any use of Xilinx products in Critical
 // Applications, subject only to applicable laws and
 // regulations governing limitations on product liability.
 //
 // THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
 // PART OF THIS FILE AT ALL TIMES.

 //
 ///////////////////////////////////////////////////////////////////////////////
 //
 //  EXAMPLE_DESIGN
 //
 //
 //
 //
 //  Description:  This module instantiates 1 lane Aurora Module.
 //                Used to exhibit functionality in hardware using the example design
 //                The User Interface is connected to Data Generator or Checker.
 //
 ///////////////////////////////////////////////////////////////////////////////
// This is sample simplex exdes file.
`timescale 1ns / 1ps
`default_nettype none

(* core_generation_info = "aurora_64b66b_1,aurora_64b66b_v12_0_10,{c_aurora_lanes=1,c_column_used=left,c_gt_clock_1=GTYQ0,c_gt_clock_2=None,c_gt_loc_1=1,c_gt_loc_10=X,c_gt_loc_11=X,c_gt_loc_12=X,c_gt_loc_13=X,c_gt_loc_14=X,c_gt_loc_15=X,c_gt_loc_16=X,c_gt_loc_17=X,c_gt_loc_18=X,c_gt_loc_19=X,c_gt_loc_2=X,c_gt_loc_20=X,c_gt_loc_21=X,c_gt_loc_22=X,c_gt_loc_23=X,c_gt_loc_24=X,c_gt_loc_25=X,c_gt_loc_26=X,c_gt_loc_27=X,c_gt_loc_28=X,c_gt_loc_29=X,c_gt_loc_3=X,c_gt_loc_30=X,c_gt_loc_31=X,c_gt_loc_32=X,c_gt_loc_33=X,c_gt_loc_34=X,c_gt_loc_35=X,c_gt_loc_36=X,c_gt_loc_37=X,c_gt_loc_38=X,c_gt_loc_39=X,c_gt_loc_4=X,c_gt_loc_40=X,c_gt_loc_41=X,c_gt_loc_42=X,c_gt_loc_43=X,c_gt_loc_44=X,c_gt_loc_45=X,c_gt_loc_46=X,c_gt_loc_47=X,c_gt_loc_48=X,c_gt_loc_5=X,c_gt_loc_6=X,c_gt_loc_7=X,c_gt_loc_8=X,c_gt_loc_9=X,c_lane_width=4,c_line_rate=10.3125,c_gt_type=GTYE4,c_qpll=true,c_nfc=false,c_nfc_mode=IMM,c_refclk_frequency=156.25,c_simplex=true,c_simplex_mode=RX,c_stream=false,c_ufc=false,c_user_k=false,flow_mode=None,interface_mode=Framing,dataflow_config=RX-only_Simplex}" *)
(* DowngradeIPIdentifiedWarnings = "yes" *)
module aurora_64b66b_1_exdes #(
    parameter EXAMPLE_SIMULATION = 0
        // pragma translate_off
        | 1
        // pragma translate_on
)(
    // System interface
    input  wire        RESET,
    input  wire        PMA_INIT,
    input  wire        INIT_CLK,

    // GT reference clock and serial input
    input  wire        GT_REFCLK,
    input  wire        QPLL_CLK,
    input  wire        QPLL_REFCLK,
    input  wire        QPLL_LOCK,
    input  wire        QPLL_REFCLKLOST,
    output wire        QPLL_RESET,
    input  wire        RXP,
    input  wire        RXN,

    // RX AXI4-Stream interface
    output wire [0:63] M_AXI_RX_TDATA,
    output wire [0:7]  M_AXI_RX_TKEEP,
    output wire        M_AXI_RX_TLAST,
    output wire        M_AXI_RX_TVALID,
    output wire        M_AXI_RX_ACLK,
    output wire        M_AXI_RX_ARESETN,

    // Aurora status and diagnostics
    output reg         RX_HARD_ERR,
    output reg         RX_SOFT_ERR,
    output reg         RX_LANE_UP,
    output reg         RX_CHANNEL_UP,
    output wire        CRC_PASS_FAIL_N,
    output wire        CRC_VALID
);

`define DLY #1
    // Internal signals
    // RX AXI4-Stream interface
    wire [0:63] rx_tdata_i;
    wire [0:7]  rx_tkeep_i;
    wire        rx_tlast_i;
    wire        rx_tvalid_i;

    // Clock interface
    wire INIT_CLK_i /* synthesis syn_keep = 1 */;
    wire user_clk_i;
    wire tx_out_clk_i;
    wire gt_pll_lock_i;
    wire pll_not_locked_i;
    wire bufg_gt_clr_out;

    // Error and status interface
    wire rx_soft_err_i;
    wire rx_hard_err_i;
    wire rx_channel_up_i;
    wire rx_lane_up_i;

    // System and reset interface
    wire system_reset_i;
    wire power_down_i;
    wire link_reset_i;
    wire reset_i;
    wire gt_reset_i;
    wire gt_reset_i_tmp;
    wire gt_reset_i_tmp2;
    wire gt_reset_i_eff;
    wire gt_reset_i_delayed;
    wire gt_rxcdrovrden_i;

    reg reset_r3;

    // DRP AXI4-Lite interface
    wire [31:0] s_axi_awaddr_i;
    wire [31:0] s_axi_araddr_i;
    wire [31:0] s_axi_wdata_i;
    wire [31:0] s_axi_rdata_i;
    wire [3:0]  s_axi_wstrb_i;
    wire [1:0]  s_axi_rresp_i;
    wire [1:0]  s_axi_bresp_i;
    wire        s_axi_awvalid_i;
    wire        s_axi_arvalid_i;
    wire        s_axi_wvalid_i;
    wire        s_axi_rvalid_i;
    wire        s_axi_bvalid_i;
    wire        s_axi_bready_i;
    wire        s_axi_awready_i;
    wire        s_axi_arready_i;
    wire        s_axi_wready_i;
    wire        s_axi_rready_i;

    // Main body
    assign INIT_CLK_i = INIT_CLK;

    assign M_AXI_RX_TDATA   = rx_tdata_i;
    assign M_AXI_RX_TKEEP   = rx_tkeep_i;
    assign M_AXI_RX_TLAST   = rx_tlast_i;
    assign M_AXI_RX_TVALID  = rx_tvalid_i;
    assign M_AXI_RX_ACLK    = user_clk_i;
    assign M_AXI_RX_ARESETN = ~(system_reset_i | !rx_channel_up_i);

    always @(posedge user_clk_i) begin
        reset_r3 <= `DLY reset_i;

        RX_HARD_ERR   <= `DLY rx_hard_err_i;
        RX_SOFT_ERR   <= `DLY rx_soft_err_i;
        RX_LANE_UP    <= `DLY rx_lane_up_i;
        RX_CHANNEL_UP <= `DLY rx_channel_up_i;
    end

    assign power_down_i      = 1'b0;
    assign gt_rxcdrovrden_i  = 1'b0;

    // DRP AXI4-Lite is retained and disabled by default.
    assign s_axi_awaddr_i  = 32'd0;
    assign s_axi_wdata_i   = 32'd0;
    assign s_axi_wstrb_i   = 4'd0;
    assign s_axi_araddr_i  = 32'd0;
    assign s_axi_awvalid_i = 1'b0;
    assign s_axi_wvalid_i  = 1'b0;
    assign s_axi_arvalid_i = 1'b0;
    assign s_axi_rready_i  = 1'b0;
    assign s_axi_bready_i  = 1'b0;

    // Use the dual-lane top-level PMA_INIT sequence directly.
    assign gt_reset_i_delayed = gt_reset_i_tmp;
    assign gt_reset_i_eff     = gt_reset_i_delayed;

    assign gt_reset_i_tmp = PMA_INIT;
    assign reset_i        = RESET | gt_reset_i_tmp2;
    assign gt_reset_i     = gt_reset_i_eff;

    aurora_64b66b_1_rst_sync_exdes u_rst_sync_gtrsttmpi (
        .prmry_in    (gt_reset_i_tmp),
        .scndry_aclk (user_clk_i),
        .scndry_out  (gt_reset_i_tmp2)
    );

    aurora_64b66b_1_support

    aurora_64b66b_1_block_i
    (
    // RX AXI4-S Interface
    .m_axi_rx_tdata(rx_tdata_i),
    .m_axi_rx_tlast(rx_tlast_i),
    .m_axi_rx_tkeep(rx_tkeep_i),
    .m_axi_rx_tvalid(rx_tvalid_i),

    // GTX Serial I/O
    .rxp(RXP),
    .rxn(RXN),

    .crc_pass_fail_n(CRC_PASS_FAIL_N),
    .crc_valid(CRC_VALID),
    .refclk1_in                 (GT_REFCLK),
    .gt_qpllclk_quad1_i         (QPLL_CLK),
    .gt_qpllrefclk_quad1_i      (QPLL_REFCLK),
    .gt_qplllock_quad1_i        (QPLL_LOCK),
    .gt_qpllrefclklost_quad1_i  (QPLL_REFCLKLOST),
    .gt_to_common_qpllreset_i   (QPLL_RESET),

    // Error Detection Interface
    .rx_hard_err(rx_hard_err_i),
    .rx_soft_err(rx_soft_err_i),

    // Status
    .rx_channel_up(rx_channel_up_i),
    .rx_lane_up(rx_lane_up_i),

    // System Interface
    .user_clk_out    (user_clk_i),

    .reset2fc(),

    .reset_pb(reset_r3),
    .gt_rxcdrovrden_in(gt_rxcdrovrden_i),
    .power_down(power_down_i),
    .pma_init(gt_reset_i),
    .gt_pll_lock(gt_pll_lock_i),
    // ---------- AXI4-Lite input signals ---------------
    .s_axi_awaddr(s_axi_awaddr_i),
    .s_axi_awvalid(s_axi_awvalid_i),
    .s_axi_awready(s_axi_awready_i),
    .s_axi_wdata(s_axi_wdata_i),
    .s_axi_wstrb(s_axi_wstrb_i),
    .s_axi_wvalid(s_axi_wvalid_i),
    .s_axi_wready(s_axi_wready_i),
    .s_axi_bvalid(s_axi_bvalid_i),
    .s_axi_bresp(s_axi_bresp_i),
    .s_axi_bready(s_axi_bready_i),
    .s_axi_araddr(s_axi_araddr_i),
    .s_axi_arvalid(s_axi_arvalid_i),
    .s_axi_arready(s_axi_arready_i),
    .s_axi_rdata(s_axi_rdata_i),
    .s_axi_rvalid(s_axi_rvalid_i),
    .s_axi_rresp(s_axi_rresp_i),
    .s_axi_rready(s_axi_rready_i),
    .init_clk            (INIT_CLK_i),
    .link_reset_out        (link_reset_i),
    .mmcm_not_locked_out        (pll_not_locked_i),

    .bufg_gt_clr_out                 (bufg_gt_clr_out),

    .sys_reset_out(system_reset_i),
    .tx_out_clk(tx_out_clk_i)
    );

    endmodule
    //------------------------------------------------------------------------------

`default_nettype wire
