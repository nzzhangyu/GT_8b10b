`timescale 1ns / 1ps

module tb_gt_8b10b_top (
    input  logic        sys_clk,
    input  logic        sys_reset,

    // AXI-Stream input to AXI2GI.
    input  logic [63:0] s_axi_tdata,
    input  logic [7:0]  s_axi_tkeep,
    input  logic        s_axi_tvalid,
    output logic        s_axi_tready,
    input  logic        s_axi_tlast,

    // AXI-Stream output from GI2AXI.
    output logic [63:0] m_axi_tdata,
    output logic [7:0]  m_axi_tkeep,
    output logic        m_axi_tvalid,
    input  logic        m_axi_tready,
    output logic        m_axi_tlast,

    // Fault injection controls.
    input  logic [11:0] inj_skew_lane,
    input  logic [1:0]  inj_bit_flip,
    input  logic        inj_link_drop,

    // Link status.
    output logic        lane_aligned,
    output logic        rx_crc_error
);

    logic       gt_ready;
    logic [1:0] lane_clks;
    logic [1:0] lane_resets;

    // AXI2GI and GI2AXI use unpacked lane arrays. The dummy channel uses
    // packed vectors, so keep both representations and convert explicitly.
    logic [31:0] tx_data_lane [1:0];
    logic [3:0]  tx_ctrl_lane [1:0];
    logic [63:0] tx_data_packed;
    logic [7:0]  tx_ctrl_packed;

    logic [63:0] rx_data_packed;
    logic [7:0]  rx_ctrl_packed;
    logic [31:0] rx_data_lane [1:0];
    logic [3:0]  rx_ctrl_lane [1:0];

    logic m_axi_aresetn;

    assign gt_ready    = ~sys_reset;
    assign lane_clks   = {2{sys_clk}};
    assign lane_resets = {2{sys_reset}};

    assign tx_data_packed[31:0]  = tx_data_lane[0];
    assign tx_data_packed[63:32] = tx_data_lane[1];
    assign tx_ctrl_packed[3:0]   = tx_ctrl_lane[0];
    assign tx_ctrl_packed[7:4]   = tx_ctrl_lane[1];

    assign rx_data_lane[0] = rx_data_packed[31:0];
    assign rx_data_lane[1] = rx_data_packed[63:32];
    assign rx_ctrl_lane[0]  = rx_ctrl_packed[3:0];
    assign rx_ctrl_lane[1]  = rx_ctrl_packed[7:4];

    AXI2GI #(
        .WORDS_IN_BRAM(512)
    ) tx_inst (
        .i_gt_reset_tx_done ({2{gt_ready}} ),
        .s_axi_rx_tdata     (s_axi_tdata   ),
        .s_axi_rx_tkeep     (s_axi_tkeep   ),
        .s_axi_rx_tvalid    (s_axi_tvalid  ),
        .s_axi_rx_tready    (s_axi_tready  ),
        .s_axi_rx_tlast     (s_axi_tlast   ),
        .o_tx_data_out      (tx_data_lane  ),
        .o_txctrl_out       (tx_ctrl_lane  ),
        .i_tx_usrclk        (lane_clks     ),
        .i_tx_user_reset    (lane_resets   )
    );

    dummy_gt_channel #(
        .MAX_SKEW(63),
        .LANE_NUM(2)
    ) channel_inst (
        .clk            (sys_clk        ),
        .rst            (sys_reset      ),
        .i_tx_data      (tx_data_packed ),
        .i_tx_ctrl      (tx_ctrl_packed ),
        .o_rx_data      (rx_data_packed ),
        .o_rx_ctrl      (rx_ctrl_packed ),
        .cfg_lane_delay (inj_skew_lane  ),
        .inj_err_lane   (inj_bit_flip   ),
        .inj_link_drop  (inj_link_drop  )
    );

    GI2AXI #(
        .WORDS_IN_BRAM(512)
    ) rx_inst (
        .i_gt_reset_rx_done ({2{gt_ready}} ),
        .i_rx_data_in       (rx_data_lane  ),
        .i_rxctrl_in        (rx_ctrl_lane  ),
        .i_rx_usrclk        (lane_clks     ),
        .i_rx_user_reset    (lane_resets   ),
        .m_axi_tx_tdata     (m_axi_tdata   ),
        .m_axi_tx_tkeep     (m_axi_tkeep   ),
        .m_axi_tx_tvalid    (m_axi_tvalid  ),
        .m_axi_tx_tready    (m_axi_tready  ),
        .m_axi_tx_tlast     (m_axi_tlast   ),
        .m_axi_tx_aresetn   (m_axi_aresetn ),
        .i_user_axi_clk     (sys_clk       ),
        .o_lane_aligned     (lane_aligned  ),
        .o_rx_crc_error     (rx_crc_error  )
    );

endmodule

