`timescale 1ns / 1ps
`default_nettype none

module GTY_top (
    input  wire         i_init_clk,
    input  wire         i_init_clk_rst,
    input  wire         i_sys_clk,

    input  wire         i_mgtrefclk,

    input  wire [1:0]   i_8b10b_rxp,
    input  wire [1:0]   i_8b10b_rxn,
    output wire [1:0]   o_8b10b_txp,
    output wire [1:0]   o_8b10b_txn,

    input  wire [1:0]   i_64b66b_rxp,
    input  wire [1:0]   i_64b66b_rxn,

    input  wire [1:0]   i_sfp_los,
    input  wire         i_8b10b_soft_rst,

    input  wire [63:0]  s_axi_8b10b_tx_tdata,
    input  wire [7:0]   s_axi_8b10b_tx_tkeep,
    input  wire         s_axi_8b10b_tx_tvalid,
    output wire         s_axi_8b10b_tx_tready,
    input  wire         s_axi_8b10b_tx_tlast,
    output wire         s_axi_8b10b_tx_aclk,
    output wire         s_axi_8b10b_tx_aresetn,

    output wire [63:0]  m_axi_8b10b_rx_tdata,
    output wire [7:0]   m_axi_8b10b_rx_tkeep,
    output wire         m_axi_8b10b_rx_tvalid,
    input  wire         m_axi_8b10b_rx_tready,
    output wire         m_axi_8b10b_rx_tlast,
    output wire         m_axi_8b10b_rx_aclk,
    output wire         m_axi_8b10b_rx_aresetn,

    output wire [0:63]  m_axi_64b66b_rx_tdata [1:0],
    output wire [0:7]   m_axi_64b66b_rx_tkeep [1:0],
    output wire [1:0]   m_axi_64b66b_rx_tlast,
    output wire [1:0]   m_axi_64b66b_rx_tvalid,
    output wire [1:0]   m_axi_64b66b_rx_aclk,
    output wire [1:0]   m_axi_64b66b_rx_aresetn,

    output wire [0:0]   o_8b10b_tx_channel_up,
    output wire         o_8b10b_gt_tx_lock,
    output wire         o_8b10b_rx_lane_aligned,
    output wire         o_8b10b_rx_lane_crc_err,
    output wire [1:0]   o_64b66b_rx_hard_err,
    output wire [1:0]   o_64b66b_rx_soft_err,
    output wire [1:0]   o_64b66b_rx_lane_up,
    output wire [1:0]   o_64b66b_rx_channel_up,
    output wire [1:0]   o_64b66b_rx_crc_pass_fail_n,
    output wire [1:0]   o_64b66b_rx_crc_valid
);

    gt_8b10b_dual_lane u_8b10b_dual_lane (
        .i_mgtrefclk        (i_mgtrefclk           ),
        .i_soft_rst         (i_8b10b_soft_rst      ),
        .i_rxp              (i_8b10b_rxp           ),
        .i_rxn              (i_8b10b_rxn           ),
        .o_txp              (o_8b10b_txp           ),
        .o_txn              (o_8b10b_txn           ),
        .i_init_clk         (i_init_clk             ),
        .o_gt_tx_channel_up (o_8b10b_tx_channel_up ),
        .o_gt_tx_lock       (o_8b10b_gt_tx_lock    ),
        .s_axi_tx_tdata     (s_axi_8b10b_tx_tdata  ),
        .s_axi_tx_tkeep     (s_axi_8b10b_tx_tkeep  ),
        .s_axi_tx_tvalid    (s_axi_8b10b_tx_tvalid ),
        .s_axi_tx_tready    (s_axi_8b10b_tx_tready ),
        .s_axi_tx_tlast     (s_axi_8b10b_tx_tlast  ),
        .s_axi_tx_aclk      (s_axi_8b10b_tx_aclk   ),
        .s_axi_tx_aresetn   (s_axi_8b10b_tx_aresetn),
        .m_axi_rx_tdata     (m_axi_8b10b_rx_tdata  ),
        .m_axi_rx_tkeep     (m_axi_8b10b_rx_tkeep  ),
        .m_axi_rx_tvalid    (m_axi_8b10b_rx_tvalid ),
        .m_axi_rx_tready    (m_axi_8b10b_rx_tready ),
        .m_axi_rx_tlast     (m_axi_8b10b_rx_tlast  ),
        .m_axi_rx_aclk      (m_axi_8b10b_rx_aclk   ),
        .m_axi_rx_aresetn   (m_axi_8b10b_rx_aresetn),
        .o_rx_lane_aligned  (o_8b10b_rx_lane_aligned),
        .o_rx_lane_crc_err  (o_8b10b_rx_lane_crc_err),
        .i_sfp_los          (i_sfp_los             ),
        .i_sys_clk          (i_sys_clk             )
    );

    aurora_64b66b_dual_lane u_64b66b_dual_lane (
        .i_init_clk             (i_init_clk                    ),
        .i_init_clk_rst         (i_init_clk_rst                ),
        .i_mgtrefclk            (i_mgtrefclk                    ),
        .i_rxp                  (i_64b66b_rxp                  ),
        .i_rxn                  (i_64b66b_rxn                  ),
        .m_axi_rx_tdata         (m_axi_64b66b_rx_tdata         ),
        .m_axi_rx_tkeep         (m_axi_64b66b_rx_tkeep         ),
        .m_axi_rx_tlast         (m_axi_64b66b_rx_tlast         ),
        .m_axi_rx_tvalid        (m_axi_64b66b_rx_tvalid        ),
        .m_axi_rx_aclk          (m_axi_64b66b_rx_aclk          ),
        .m_axi_rx_aresetn       (m_axi_64b66b_rx_aresetn       ),
        .o_rx_hard_err          (o_64b66b_rx_hard_err          ),
        .o_rx_soft_err          (o_64b66b_rx_soft_err          ),
        .o_rx_lane_up           (o_64b66b_rx_lane_up           ),
        .o_rx_channel_up        (o_64b66b_rx_channel_up        ),
        .o_rx_crc_pass_fail_n   (o_64b66b_rx_crc_pass_fail_n   ),
        .o_rx_crc_valid         (o_64b66b_rx_crc_valid         )
    );

endmodule

`default_nettype wire
