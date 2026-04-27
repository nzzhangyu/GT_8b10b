`timescale 1ns / 1ps

module tb_gt_8b10b_top #(
    parameter int LANE_NUM = 2
)(
    input  logic sys_clk,
    input  logic sys_reset,

    // AXI-Stream Input (To TX module AXI2GI)
    input  logic [LANE_NUM*32-1:0] s_axi_tdata,
    input  logic [LANE_NUM*4-1:0]  s_axi_tkeep,
    input  logic                   s_axi_tvalid,
    output logic                   s_axi_tready,
    input  logic                   s_axi_tlast,

    // AXI-Stream Output (From RX module GI2AXI)
    output logic [LANE_NUM*32-1:0] m_axi_tdata,
    output logic [LANE_NUM*4-1:0]  m_axi_tkeep,
    output logic                   m_axi_tvalid,
    input  logic                   m_axi_tready,
    output logic                   m_axi_tlast,

    // Fault Injection Interfaces (Controlled by Python)
    input  logic [LANE_NUM*6-1:0] inj_skew_lane,  // Dynamic per-lane delay cycles 
    input  logic [LANE_NUM-1:0]   inj_bit_flip,   // Pulse: per-lane payload bit flip
    input  logic                  inj_link_drop,  // Level: Simulate fiber cut: output garbage or all 0s
    
    // Status Outputs
    output logic                  lane_aligned,
    output logic                  rx_crc_error
);

    // ==========================================
    // Internal Signals
    // ==========================================
    logic gt_ready;
    assign gt_ready = ~sys_reset; 

    // Interconnect: TX -> Channel
    logic [LANE_NUM*32-1:0] tx_data;
    logic [LANE_NUM*4-1:0]  tx_ctrl;

    // Interconnect: Channel -> RX
    logic [LANE_NUM*32-1:0] rx_data;
    logic [LANE_NUM*4-1:0]  rx_ctrl;

    // ==========================================
    // 1. Instantiate TX (AXI2GI)
    // ==========================================
    AXI2GI #(
        .WORDS_IN_BRAM(512),
        .LANE_NUM     (LANE_NUM)
    ) tx_inst (
        .i_gt_txresetdone  ({LANE_NUM{gt_ready}}),
        
        .i_s_axi_rx_tdata  (s_axi_tdata         ),
        .i_s_axi_rx_tkeep  (s_axi_tkeep         ),
        .i_s_axi_rx_tvalid (s_axi_tvalid        ),
        .o_s_axi_rx_tready (s_axi_tready        ),
        .i_s_axi_rx_tlast  (s_axi_tlast         ),

        .o_tx_data_out     (tx_data             ),
        .o_txctrl_out      (tx_ctrl             ),

        .i_user_clk        (sys_clk             ),
        .i_system_reset    (sys_reset           )
    );

    // ==========================================
    // 2. Instantiate Dummy GT Channel
    // ==========================================
    dummy_gt_channel #(
        .MAX_SKEW(63),
        .LANE_NUM(LANE_NUM)
    ) channel_inst (
        .clk              (sys_clk          ),
        .rst              (sys_reset        ),
        
        .i_tx_data        (tx_data          ),
        .i_tx_ctrl        (tx_ctrl          ),

        .o_rx_data        (rx_data          ),
        .o_rx_ctrl        (rx_ctrl          ),
        
        .cfg_lane_delay   (inj_skew_lane    ),
        .inj_err_lane     (inj_bit_flip     ),
        .inj_link_drop    (inj_link_drop    )
    );

    // ==========================================
    // 3. Instantiate RX (GI2AXI)
    // ==========================================
    GI2AXI #(
        .WORDS_IN_BRAM(512),
        .LANE_NUM     (LANE_NUM)
    ) rx_inst (
        .i_gt_rxresetdone  ({LANE_NUM{gt_ready}}),

        .i_rx_data_in      (rx_data             ),
        .i_rxctrl_in       (rx_ctrl             ),
        .i_rx_clk          ({LANE_NUM{sys_clk}} ),
        
        .o_m_axi_tx_tdata  (m_axi_tdata         ),
        .o_m_axi_tx_tkeep  (m_axi_tkeep         ),
        .o_m_axi_tx_tvalid (m_axi_tvalid        ),
        .i_m_axi_tx_tready (m_axi_tready        ),
        .o_m_axi_tx_tlast  (m_axi_tlast         ),
            
        .i_user_clk        (sys_clk             ),
        .i_system_reset    (sys_reset           ),
                
        .o_lane_aligned    (lane_aligned        ),
        .o_rx_crc_error    (rx_crc_error        )
    );  

    initial begin
        $dumpfile("dump.fst"); 
        $dumpvars(0, tb_gt_8b10b_top);
    end

endmodule
