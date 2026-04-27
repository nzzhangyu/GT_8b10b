`timescale 1ns / 1ps

module dummy_gt_channel #(
    parameter int MAX_SKEW = 63,
    parameter int LANE_NUM = 2
)(  
    input  logic clk,
    input  logic rst,

    // TX Interface (from AXI2GI)
    input  logic [LANE_NUM*32-1:0] i_tx_data,
    input  logic [LANE_NUM*4-1:0]  i_tx_ctrl,

    // RX Interface (to AXI2GI)
    output logic [LANE_NUM*32-1:0] o_rx_data,
    output logic [LANE_NUM*4-1:0]  o_rx_ctrl,

    // Fault Injection and Control Interface
    input logic [LANE_NUM*6-1:0] cfg_lane_delay,    // Dynamic configuration: per-lane delay cycles
    input logic [LANE_NUM-1:0]   inj_err_lane,      // Pulse: Trigger per-lane payload bit flip

    input logic       inj_link_drop       // Level: Simulate fiber cut: output garbage or all 0s
);

    // Shift Register Pipeline
    logic [35:0] pipe_lane[LANE_NUM-1:0][0:MAX_SKEW];

    // Simulate physical transmission and error injection
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int lane = 0; lane < LANE_NUM; lane++) begin
                for (int i = 0; i <= MAX_SKEW; i++) begin
                    pipe_lane[lane][i] <= 36'h0_0000_0000;
                end
            end
        end
        else begin
            for (int lane = 0; lane < LANE_NUM; lane++) begin
                pipe_lane[lane][0] <= {
                    i_tx_ctrl[lane*4 +: 4],
                    i_tx_data[lane*32 +: 32] ^ {32{inj_err_lane[lane]}}
                };
                for (int i = 0; i < MAX_SKEW; i++) begin
                    pipe_lane[lane][i+1] <= pipe_lane[lane][i];
                end
            end
        end
    end

    logic [35:0] raw_rx_lane [LANE_NUM-1:0];
    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_lane_select
        assign raw_rx_lane[lane] = pipe_lane[lane][cfg_lane_delay[lane*6 +: 6]];
    end

    always_comb begin
        if (inj_link_drop) begin
            // Fiber disconnect: transceiver outputs all zeros or loses word boundary
            o_rx_data = '0;
            o_rx_ctrl = '0;
        end 
        else begin
            // Normal link: outputs real data with latency and potential bit errors
            for (int lane = 0; lane < LANE_NUM; lane++) begin
                o_rx_data[lane*32 +: 32] = raw_rx_lane[lane][31:0];
                o_rx_ctrl[lane*4 +: 4] = raw_rx_lane[lane][35:32];
            end
        end
    end

endmodule
