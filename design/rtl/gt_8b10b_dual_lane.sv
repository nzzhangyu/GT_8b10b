`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/03 11:38:53
// Design Name: 
// Module Name: gt_8b10b_dual_lane
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module gt_8b10b_dual_lane(
    input  wire i_mgtrefclk,
    input  wire i_soft_rst,

    input  wire [1:0]  i_rxp,
    input  wire [1:0]  i_rxn,
    output wire [1:0]  o_txp,
    output wire [1:0]  o_txn,

    input  wire [0:0]  i_init_clk,

    output wire [0:0]  o_gt_tx_channel_up,
    output wire        o_gt_tx_lock,

    input  wire [63:0] s_axi_tx_tdata,
    input  wire [7:0]  s_axi_tx_tkeep,
    input  wire        s_axi_tx_tvalid,
    output wire        s_axi_tx_tready,
    input  wire        s_axi_tx_tlast,
    output wire        s_axi_tx_aclk,
    output wire        s_axi_tx_aresetn,


    output wire [63:0] m_axi_rx_tdata,
    output wire [7:0]  m_axi_rx_tkeep,
    output wire        m_axi_rx_tvalid,
    input  wire        m_axi_rx_tready,
    output wire        m_axi_rx_tlast,
    output wire        m_axi_rx_aclk,
    output wire        m_axi_rx_aresetn,

    output wire        o_rx_lane_aligned,
    output wire        o_rx_lane_crc_err,
    
    input  wire [1:0]  i_sfp_los,

    input  wire i_sys_clk
    );

    localparam int WORDS_IN_BRAM = 512;

    // GTY Quad PLL signals
    logic qpll0lock_int;
    logic qpll0outclk_int;
    logic qpll0outrefclk_int;
    logic qpll0reset_int;

    logic qpll1lock_int;
    logic qpll1outclk_int;
    logic qpll1outrefclk_int;
    logic qpll1reset_int;

    assign o_gt_tx_lock = qpll0lock_int & qpll1lock_int;

    logic gtwiz_reset_clk_freerun_int;
    assign gtwiz_reset_clk_freerun_int = i_init_clk;

    // System Reset Logic
    logic gtwiz_reset_all_int;

    logic soft_rst_d1, soft_rst_d2, soft_rst_d3;

    always_ff @(posedge gtwiz_reset_clk_freerun_int) 
    begin
        soft_rst_d1 <= i_soft_rst;
        soft_rst_d2 <= soft_rst_d1;
        soft_rst_d3 <= soft_rst_d2;
    end

    assign gtwiz_reset_all_int = soft_rst_d3;

    logic [1:0]  gt_reset_tx_datapath;
    logic [1:0]  gt_reset_rx_datapath;

    logic [31:0] gt_txdata[1:0];
    logic [3:0]  gt_txctrl[1:0];
    logic [31:0] gt_rxdata[1:0];
    logic [7:0]  gt_rxctrl[1:0];
    logic [3:0]  gt_rxctrl_low[1:0];

    assign gt_rxctrl_low[0] = gt_rxctrl[0][3:0];
    assign gt_rxctrl_low[1] = gt_rxctrl[1][3:0];
    
    logic [1:0] gt_tx_usrclk;
    logic [1:0] gt_rx_usrclk;

    logic [1:0] gt_reset_tx_done;
    logic [1:0] gt_reset_rx_done;

    logic [1:0] gt_rxbyterealign;

    logic [1:0] tx_user_reset;
    logic [1:0] rx_user_reset;
    logic [2:0] tx_axi_reset_pipe = 3'b111;
    logic       tx_axi_reset;

    always_ff @(posedge gt_tx_usrclk[0] or posedge tx_user_reset[0] or posedge tx_user_reset[1]) begin
        if (tx_user_reset[0] || tx_user_reset[1])
            tx_axi_reset_pipe <= 3'b111;
        else
            tx_axi_reset_pipe <= {tx_axi_reset_pipe[1:0], 1'b0};
    end

    assign tx_axi_reset      = tx_axi_reset_pipe[2];
    assign s_axi_tx_aclk     = gt_tx_usrclk[0];
    assign s_axi_tx_aresetn  = ~tx_axi_reset;
    assign m_axi_rx_aclk     = i_sys_clk;

    logic [1:0] tx_channel_up;
    logic [1:0] rx_channel_up;
    logic       tx_all_channels_up;
    logic       rx_lane_aligned;
    logic       rx_lane_crc_err;

    assign tx_all_channels_up = tx_channel_up[0] & tx_channel_up[1];
    assign o_gt_tx_channel_up = tx_all_channels_up;

    assign o_rx_lane_aligned = rx_lane_aligned;
    assign o_rx_lane_crc_err = rx_lane_crc_err;

    gtwizard_ultrascale_0_gtye4_common_wrapper gtye4_common_wrapper_inst (
        .GTYE4_COMMON_BGBYPASSB         (1'b1                   ),
        .GTYE4_COMMON_BGMONITORENB      (1'b1                   ),
        .GTYE4_COMMON_BGPDB             (1'b1                   ),
        .GTYE4_COMMON_BGRCALOVRD        (5'b10000               ),
        .GTYE4_COMMON_BGRCALOVRDENB     (1'b1                   ),

        .GTYE4_COMMON_DRPADDR           (16'b0000000000000000   ),
        .GTYE4_COMMON_DRPCLK            (1'b0                   ),
        .GTYE4_COMMON_DRPDI             (16'b0000000000000000   ),
        .GTYE4_COMMON_DRPEN             (1'b0                   ),
        .GTYE4_COMMON_DRPWE             (1'b0                   ),

        .GTYE4_COMMON_GTGREFCLK0        (1'b0                   ),
        .GTYE4_COMMON_GTGREFCLK1        (1'b0                   ),
        .GTYE4_COMMON_GTNORTHREFCLK00   (1'b0                   ),
        .GTYE4_COMMON_GTNORTHREFCLK01   (1'b0                   ),
        .GTYE4_COMMON_GTNORTHREFCLK10   (1'b0                   ),
        .GTYE4_COMMON_GTNORTHREFCLK11   (1'b0                   ),
        .GTYE4_COMMON_GTREFCLK00        (i_mgtrefclk            ),
        .GTYE4_COMMON_GTREFCLK01        (i_mgtrefclk            ),
        .GTYE4_COMMON_GTREFCLK10        (1'b0                   ),
        .GTYE4_COMMON_GTREFCLK11        (1'b0                   ),
        .GTYE4_COMMON_GTSOUTHREFCLK00   (1'b0                   ),
        .GTYE4_COMMON_GTSOUTHREFCLK01   (1'b0                   ),
        .GTYE4_COMMON_GTSOUTHREFCLK10   (1'b0                   ),
        .GTYE4_COMMON_GTSOUTHREFCLK11   (1'b0                   ),
        .GTYE4_COMMON_PCIERATEQPLL0     (3'b000                 ),
        .GTYE4_COMMON_PCIERATEQPLL1     (3'b000                 ),
        .GTYE4_COMMON_PMARSVD0          (8'b00000000            ),
        .GTYE4_COMMON_PMARSVD1          (8'b00000000            ),

        .GTYE4_COMMON_QPLL0CLKRSVD0     (1'b0                   ),
        .GTYE4_COMMON_QPLL0CLKRSVD1     (1'b0                   ),
        .GTYE4_COMMON_QPLL0FBDIV        (8'b00000000            ),
        .GTYE4_COMMON_QPLL0LOCKDETCLK   (1'b0                   ),
        .GTYE4_COMMON_QPLL0LOCKEN       (1'b1                   ),
        .GTYE4_COMMON_QPLL0PD           (1'b0                   ),
        .GTYE4_COMMON_QPLL0REFCLKSEL    (3'b001                 ),
        .GTYE4_COMMON_QPLL0RESET        (qpll0reset_int         ),

        .GTYE4_COMMON_QPLL1CLKRSVD0     (1'b0                   ),
        .GTYE4_COMMON_QPLL1CLKRSVD1     (1'b0                   ),
        .GTYE4_COMMON_QPLL1FBDIV        (8'b00000000            ),
        .GTYE4_COMMON_QPLL1LOCKDETCLK   (1'b0                   ),
        .GTYE4_COMMON_QPLL1LOCKEN       (1'b1                   ),
        .GTYE4_COMMON_QPLL1PD           (1'b0                   ),
        .GTYE4_COMMON_QPLL1REFCLKSEL    (3'b001                 ),
        .GTYE4_COMMON_QPLL1RESET        (qpll1reset_int         ),

        .GTYE4_COMMON_QPLLRSVD1         (8'b00000000            ),
        .GTYE4_COMMON_QPLLRSVD2         (5'b00000               ),
        .GTYE4_COMMON_QPLLRSVD3         (5'b00000               ),
        .GTYE4_COMMON_QPLLRSVD4         (8'b00000000            ),
        .GTYE4_COMMON_RCALENB           (1'b1                   ),
        .GTYE4_COMMON_SDM0DATA          (25'b0000000000000000000000000  ),
        .GTYE4_COMMON_SDM0RESET         (1'b0                           ),
        .GTYE4_COMMON_SDM0TOGGLE        (1'b0                           ),
        .GTYE4_COMMON_SDM0WIDTH         (2'b00                          ),
        .GTYE4_COMMON_SDM1DATA          (25'b0000000000000000000000000  ),
        .GTYE4_COMMON_SDM1RESET         (1'b0                           ),
        .GTYE4_COMMON_SDM1TOGGLE        (1'b0                           ),
        .GTYE4_COMMON_SDM1WIDTH         (2'b00                          ),
        .GTYE4_COMMON_UBCFGSTREAMEN     (1'b0                           ),
        .GTYE4_COMMON_UBDO              (16'b0000000000000000           ),
        .GTYE4_COMMON_UBDRDY            (1'b0                           ),
        .GTYE4_COMMON_UBENABLE          (1'b0                           ),
        .GTYE4_COMMON_UBGPI             (2'b00                          ),
        .GTYE4_COMMON_UBINTR            (2'b00                          ),
        .GTYE4_COMMON_UBIOLMBRST        (1'b0                           ),
        .GTYE4_COMMON_UBMBRST           (1'b0                           ),
        .GTYE4_COMMON_UBMDMCAPTURE      (1'b0                           ),
        .GTYE4_COMMON_UBMDMDBGRST       (1'b0                           ),
        .GTYE4_COMMON_UBMDMDBGUPDATE    (1'b0                           ),
        .GTYE4_COMMON_UBMDMREGEN        (4'b0000                        ),
        .GTYE4_COMMON_UBMDMSHIFT        (1'b0                           ),
        .GTYE4_COMMON_UBMDMSYSRST       (1'b0                           ),
        .GTYE4_COMMON_UBMDMTCK          (1'b0                           ),
        .GTYE4_COMMON_UBMDMTDI          (1'b0                           ),
        .GTYE4_COMMON_DRPDO             (                               ),
        .GTYE4_COMMON_DRPRDY            (                               ),
        .GTYE4_COMMON_PMARSVDOUT0       (                               ),
        .GTYE4_COMMON_PMARSVDOUT1       (                               ),
        .GTYE4_COMMON_QPLL0FBCLKLOST    (                               ), 
        // Lane 0 QPLL Signals
        .GTYE4_COMMON_QPLL0LOCK         (qpll0lock_int                  ),
        .GTYE4_COMMON_QPLL0OUTCLK       (qpll0outclk_int                ),
        .GTYE4_COMMON_QPLL0OUTREFCLK    (qpll0outrefclk_int             ),
        .GTYE4_COMMON_QPLL0REFCLKLOST   (                               ),
        .GTYE4_COMMON_QPLL1FBCLKLOST    (                               ),
        // Lane 1 QPLL Signals
        .GTYE4_COMMON_QPLL1LOCK         (qpll1lock_int                  ),
        .GTYE4_COMMON_QPLL1OUTCLK       (qpll1outclk_int                ),
        .GTYE4_COMMON_QPLL1OUTREFCLK    (qpll1outrefclk_int             ),
        .GTYE4_COMMON_QPLL1REFCLKLOST   (                               ),
        .GTYE4_COMMON_QPLLDMONITOR0     (                               ),
        .GTYE4_COMMON_QPLLDMONITOR1     (                               ),
        .GTYE4_COMMON_REFCLKOUTMONITOR0 (                               ),
        .GTYE4_COMMON_REFCLKOUTMONITOR1 (                               ),
        .GTYE4_COMMON_RXRECCLK0SEL      (                               ),
        .GTYE4_COMMON_RXRECCLK1SEL      (                               ),
        .GTYE4_COMMON_SDM0FINALOUT      (                               ),
        .GTYE4_COMMON_SDM0TESTDATA      (                               ),
        .GTYE4_COMMON_SDM1FINALOUT      (                               ),
        .GTYE4_COMMON_SDM1TESTDATA      (                               ),
        .GTYE4_COMMON_UBDADDR           (                               ),
        .GTYE4_COMMON_UBDEN             (                               ),
        .GTYE4_COMMON_UBDI              (                               ),
        .GTYE4_COMMON_UBDWE             (                               ),
        .GTYE4_COMMON_UBMDMTDO          (                               ),
        .GTYE4_COMMON_UBRSVDOUT         (                               ),
        .GTYE4_COMMON_UBTXUART          (                               )
    );

    gtwizard_ultrascale_0_example_top  gtwizard_ultrascale_0_example_top_inst (
        .qpll0lock_in               (qpll0lock_int              ),
        .qpll0clk_in                (qpll0outclk_int            ),
        .qpll0outrefclk_in          (qpll0outrefclk_int         ),
        .qpll0_rst_out              (qpll0reset_int             ),
        .ch0_gtyrxn_in              (i_rxn[0]                   ),
        .ch0_gtyrxp_in              (i_rxp[0]                   ),
        .ch0_gtytxn_out             (o_txn[0]                   ),
        .ch0_gtytxp_out             (o_txp[0]                   ),
        .gtwiz_reset_clk_freerun_in (gtwiz_reset_clk_freerun_int),
        .gtwiz_reset_all_in         (gtwiz_reset_all_int        ),
        .gtwiz_reset_tx_datapath_in (gt_reset_tx_datapath[0]    ),
        .gtwiz_reset_rx_datapath_in (gt_reset_rx_datapath[0]    ),
        .txdata_in                  (gt_txdata[0]               ),
        .txctrl0_in                 (                           ),
        .txctrl1_in                 (                           ),
        .txctrl2_in                 ({4'b0000, gt_txctrl[0]}    ),
        .rxdata_out                 (gt_rxdata[0]               ),
        .rxctrl0_out                (                           ),
        .rxctrl1_out                (                           ),
        .rxctrl2_out                (gt_rxctrl[0]               ),
        .rxctrl3_out                (                           ),
        .tx_usrclk2_out             (gt_tx_usrclk[0]            ),
        .rx_usrclk2_out             (gt_rx_usrclk[0]            ),
        .tx_reset_done_out          (gt_reset_tx_done[0]        ),
        .rx_reset_done_out          (gt_reset_rx_done[0]        ),
        .rxbyterealign_out          (gt_rxbyterealign[0]        )
    );

    gtwizard_ultrascale_1_example_top  gtwizard_ultrascale_1_example_top_inst (
        .qpll1lock_in               (qpll1lock_int              ),
        .qpll1clk_in                (qpll1outclk_int            ),
        .qpll1outrefclk_in          (qpll1outrefclk_int         ),
        .qpll1_rst_out              (qpll1reset_int             ),
        .ch0_gtyrxn_in              (i_rxn[1]                   ),
        .ch0_gtyrxp_in              (i_rxp[1]                   ),
        .ch0_gtytxn_out             (o_txn[1]                   ),
        .ch0_gtytxp_out             (o_txp[1]                   ),
        .gtwiz_reset_clk_freerun_in (gtwiz_reset_clk_freerun_int),
        .gtwiz_reset_all_in         (gtwiz_reset_all_int        ),
        .gtwiz_reset_tx_datapath_in (gt_reset_tx_datapath[1]    ),
        .gtwiz_reset_rx_datapath_in (gt_reset_rx_datapath[1]    ),
        .txdata_in                  (gt_txdata[1]               ),
        .txctrl0_in                 (                           ),
        .txctrl1_in                 (                           ),
        .txctrl2_in                 ({4'b0000, gt_txctrl[1]}    ),
        .rxdata_out                 (gt_rxdata[1]               ),
        .rxctrl0_out                (                           ),
        .rxctrl1_out                (                           ),
        .rxctrl2_out                (gt_rxctrl[1]               ),
        .rxctrl3_out                (                           ),
        .tx_usrclk2_out             (gt_tx_usrclk[1]            ),
        .rx_usrclk2_out             (gt_rx_usrclk[1]            ),
        .tx_reset_done_out          (gt_reset_tx_done[1]        ),
        .rx_reset_done_out          (gt_reset_rx_done[1]        ),
        .rxbyterealign_out          (gt_rxbyterealign[1]        )
    );

    gt_lane_reset_manager  gt_lane_reset_manager_inst (
        .i_freerun_clk              (gtwiz_reset_clk_freerun_int),
        .i_soft_reset_all           (gtwiz_reset_all_int        ),
        .i_tx_usrclk                (gt_tx_usrclk               ),
        .i_rx_usrclk                (gt_rx_usrclk               ),
        .i_gtwiz_reset_tx_done      (gt_reset_tx_done           ),
        .i_gtwiz_reset_rx_done      (gt_reset_rx_done           ),
        .i_sfp_los                  (i_sfp_los                  ),
        .i_rxbyterealign            (gt_rxbyterealign           ),
        .o_gtwiz_reset_tx_datapath  (gt_reset_tx_datapath       ),
        .o_gtwiz_reset_rx_datapath  (gt_reset_rx_datapath       ),
        .o_tx_user_reset            (tx_user_reset              ),
        .o_rx_user_reset            (rx_user_reset              ),
        .o_tx_channel_up            (tx_channel_up              ),
        .o_rx_channel_up            (rx_channel_up              )
    );

    AXI2GI # (
        .WORDS_IN_BRAM(WORDS_IN_BRAM)
    ) TX_AXI2GI (
        .i_gt_reset_tx_done (gt_reset_tx_done  ),
        .s_axi_rx_tdata     (s_axi_tx_tdata    ),
        .s_axi_rx_tkeep     (s_axi_tx_tkeep    ),
        .s_axi_rx_tvalid    (s_axi_tx_tvalid   ),
        .s_axi_rx_tready    (s_axi_tx_tready   ),
        .s_axi_rx_tlast     (s_axi_tx_tlast    ),
        .o_tx_data_out      (gt_txdata         ),
        .o_txctrl_out       (gt_txctrl         ), 
        .i_tx_usrclk        (gt_tx_usrclk      ),
        .i_tx_user_reset    ({tx_user_reset[1], tx_axi_reset})
    );

    GI2AXI # (
        .WORDS_IN_BRAM(WORDS_IN_BRAM)
    ) RX_GI2AXI0 (
        .i_gt_reset_rx_done (gt_reset_rx_done   ),
        .i_rx_data_in       (gt_rxdata          ),
        .i_rxctrl_in        (gt_rxctrl_low      ),
        .i_rx_usrclk        (gt_rx_usrclk       ),
        .i_rx_user_reset    (rx_user_reset      ),
        .m_axi_tx_tdata     (m_axi_rx_tdata     ),
        .m_axi_tx_tkeep     (m_axi_rx_tkeep     ),
        .m_axi_tx_tvalid    (m_axi_rx_tvalid    ),
        .m_axi_tx_tready    (m_axi_rx_tready    ),
        .m_axi_tx_tlast     (m_axi_rx_tlast     ),
        .m_axi_tx_aresetn   (m_axi_rx_aresetn   ),
        .i_user_axi_clk     (i_sys_clk          ),
        .o_lane_aligned     (rx_lane_aligned    ),
        .o_rx_crc_error     (rx_lane_crc_err    )
    );


endmodule
