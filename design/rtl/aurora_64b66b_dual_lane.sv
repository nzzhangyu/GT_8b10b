`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/11 10:01:52
// Design Name: 
// Module Name: aurora_64b66b_dual_lane
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


module aurora_64b66b_dual_lane (
    input  wire         i_init_clk,
    input  wire         i_init_clk_rst,

    // Single-ended GT reference clock from the upstream IBUFDS_GTE4 O output.
    input  wire         i_mgtrefclk,

    input  wire [1:0]   i_rxp,
    input  wire [1:0]   i_rxn,

    output wire [0:63]  m_axi_rx_tdata [1:0],
    output wire [0:7]   m_axi_rx_tkeep [1:0],
    output wire [1:0]   m_axi_rx_tlast,
    output wire [1:0]   m_axi_rx_tvalid,
    output wire [1:0]   m_axi_rx_aclk,
    output wire [1:0]   m_axi_rx_aresetn,

    output wire [1:0]   o_rx_hard_err,
    output wire [1:0]   o_rx_soft_err,
    output wire [1:0]   o_rx_lane_up,
    output wire [1:0]   o_rx_channel_up,
    output wire [1:0]   o_rx_crc_pass_fail_n,
    output wire [1:0]   o_rx_crc_valid
);

    // Both channels use QPLL1 in Quad_X0Y1 (X0Y5 and X0Y7).
    wire       qpll1_clk;
    wire       qpll1_refclk;
    wire       qpll1_lock;
    wire       qpll1_refclklost;
    wire [1:0] qpll1_reset_req;
    wire       qpll1_reset;

    // A reset request from either channel resets the shared PLL.
    assign qpll1_reset = |qpll1_reset_req;

    // Power-on reset counter.
    reg  [9:0] poweron_cnt = 10'h000;
    wire       reset;
    wire       pma_init;

    // Reset generation.
    assign reset    = ~poweron_cnt[9];
    assign pma_init = ~(&poweron_cnt);

    always @(posedge i_init_clk) begin
        if (i_init_clk_rst) begin
            poweron_cnt <= 10'h000;
        end
        else if (!(&poweron_cnt)) begin
            poweron_cnt <= poweron_cnt + 1'b1;
        end
    end

    aurora_64b66b_0_gt_common_wrapper u_gt_common (
        .qpll1_refclk       (i_mgtrefclk        ),
        .qpll1_reset        (qpll1_reset        ),
        .qpll1_lock_detclk  (i_init_clk         ),
        .qpll1_lock         (qpll1_lock         ),
        .qpll1_outclk       (qpll1_clk          ),
        .qpll1_outrefclk    (qpll1_refclk       ),
        .qpll1_refclklost   (qpll1_refclklost   )
    );

    aurora_64b66b_0_exdes u_rx_lane0 (
        .RX_HARD_ERR       (o_rx_hard_err[0]        ),
        .RX_SOFT_ERR       (o_rx_soft_err[0]        ),
        .RX_LANE_UP        (o_rx_lane_up[0]         ),
        .RX_CHANNEL_UP     (o_rx_channel_up[0]      ),
        .INIT_CLK          (i_init_clk              ),
        .PMA_INIT          (pma_init                ),
        .GT_REFCLK         (i_mgtrefclk             ),
        .QPLL_CLK          (qpll1_clk               ),
        .QPLL_REFCLK       (qpll1_refclk            ),
        .QPLL_LOCK         (qpll1_lock              ),
        .QPLL_REFCLKLOST   (qpll1_refclklost        ),
        .QPLL_RESET        (qpll1_reset_req[0]      ),
        .M_AXI_RX_TDATA    (m_axi_rx_tdata[0]       ),
        .M_AXI_RX_TKEEP    (m_axi_rx_tkeep[0]       ),
        .M_AXI_RX_TLAST    (m_axi_rx_tlast[0]       ),
        .M_AXI_RX_TVALID   (m_axi_rx_tvalid[0]      ),
        .M_AXI_RX_ACLK     (m_axi_rx_aclk[0]        ),
        .M_AXI_RX_ARESETN  (m_axi_rx_aresetn[0]     ),
        .RXP               (i_rxp[0]                ),
        .RXN               (i_rxn[0]                ),
        .CRC_PASS_FAIL_N   (o_rx_crc_pass_fail_n[0] ),
        .CRC_VALID         (o_rx_crc_valid[0]       ),
        .RESET             (reset                   )
    );

    aurora_64b66b_1_exdes u_rx_lane1 (
        .RX_HARD_ERR       (o_rx_hard_err[1]        ),
        .RX_SOFT_ERR       (o_rx_soft_err[1]        ),
        .RX_LANE_UP        (o_rx_lane_up[1]         ),
        .RX_CHANNEL_UP     (o_rx_channel_up[1]      ),
        .INIT_CLK          (i_init_clk              ),
        .PMA_INIT          (pma_init                ),
        .GT_REFCLK         (i_mgtrefclk             ),
        .QPLL_CLK          (qpll1_clk               ),
        .QPLL_REFCLK       (qpll1_refclk            ),
        .QPLL_LOCK         (qpll1_lock              ),
        .QPLL_REFCLKLOST   (qpll1_refclklost        ),
        .QPLL_RESET        (qpll1_reset_req[1]      ),
        .M_AXI_RX_TDATA    (m_axi_rx_tdata[1]       ),
        .M_AXI_RX_TKEEP    (m_axi_rx_tkeep[1]       ),
        .M_AXI_RX_TLAST    (m_axi_rx_tlast[1]       ),
        .M_AXI_RX_TVALID   (m_axi_rx_tvalid[1]      ),
        .M_AXI_RX_ACLK     (m_axi_rx_aclk[1]        ),
        .M_AXI_RX_ARESETN  (m_axi_rx_aresetn[1]     ),
        .RXP               (i_rxp[1]                ),
        .RXN               (i_rxn[1]                ),
        .CRC_PASS_FAIL_N   (o_rx_crc_pass_fail_n[1] ),
        .CRC_VALID         (o_rx_crc_valid[1]       ),
        .RESET             (reset                   )
    );

endmodule
