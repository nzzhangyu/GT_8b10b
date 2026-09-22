`timescale 1ns / 1ps

module dummy_gt_channel #(
    parameter int MAX_SKEW        = 63,
    parameter int LANE_NUM        = 2,
    parameter int MAX_QUEUE_DEPTH = 4096
)(
    input  logic [LANE_NUM-1:0]    i_tx_clk,
    input  logic [LANE_NUM-1:0]    i_rx_clk,
    input  logic                   rst,
    input  logic [LANE_NUM*32-1:0] i_tx_data,
    input  logic [LANE_NUM*4-1:0]  i_tx_ctrl,
    output logic [LANE_NUM*32-1:0] o_rx_data,
    output logic [LANE_NUM*4-1:0]  o_rx_ctrl,
    input  logic [LANE_NUM*6-1:0]  cfg_lane_delay,
    input  logic [LANE_NUM-1:0]    inj_err_lane,
    input  logic                   inj_link_drop
);

    // Simulation-only per-lane elastic transport queues. TX and RX may have
    // different phases and average frequencies.
    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_lane_transport
        logic [35:0] word_queue[$];
        logic        steady_state;
        logic [35:0] rx_word;
        int unsigned lane_delay;

        always_comb lane_delay = cfg_lane_delay[lane*6 +: 6];

        always @(posedge i_tx_clk[lane]) begin
            logic [35:0] tx_word;

            if (rst || inj_link_drop) begin
                // Discard every word that was in flight before link loss.
                word_queue.delete();
            end
            else begin
                tx_word = {
                    i_tx_ctrl[lane*4 +: 4],
                    i_tx_data[lane*32 +: 32] ^ {32{inj_err_lane[lane]}}
                };
                word_queue.push_back(tx_word);

                if (word_queue.size() > MAX_QUEUE_DEPTH)
                    $fatal(1,
                           "dummy_gt_channel lane %0d queue overflow: depth=%0d",
                           lane, word_queue.size());
            end
        end

        always @(posedge i_rx_clk[lane]) begin
            // Resolve coincident TX/RX edges deterministically: allow the TX
            // process to enqueue the word before inspecting queue depth.
            #1fs;
            if (rst || inj_link_drop) begin
                o_rx_data[lane*32 +: 32] <= 32'd0;
                o_rx_ctrl[lane*4 +: 4]   <= 4'd0;
                steady_state             <= 1'b0;
                rx_word                  <= 36'd0;
            end
            else if (!steady_state) begin
                // cfg_lane_delay is an initial elastic-buffer fill level, not
                // a threshold that must be maintained forever.  Holding this
                // threshold after startup would insert a zero word each time
                // a faster RX clock consumed one word of PPM margin.
                if (word_queue.size() > lane_delay) begin
                    rx_word = word_queue.pop_front();
                    steady_state <= 1'b1;
                    o_rx_data[lane*32 +: 32] <= rx_word[31:0];
                    o_rx_ctrl[lane*4 +: 4]   <= rx_word[35:32];
                end
                else begin
                    o_rx_data[lane*32 +: 32] <= 32'd0;
                    o_rx_ctrl[lane*4 +: 4]   <= 4'd0;
                end
            end
            else if (word_queue.size() > 0) begin
                rx_word = word_queue.pop_front();
                o_rx_data[lane*32 +: 32] <= rx_word[31:0];
                o_rx_ctrl[lane*4 +: 4]   <= rx_word[35:32];
            end
            else begin
                o_rx_data[lane*32 +: 32] <= 32'd0;
                o_rx_ctrl[lane*4 +: 4]   <= 4'd0;
                $error("dummy_gt_channel lane %0d unexpected underflow: depth=%0d delay=%0d",
                       lane, word_queue.size(), lane_delay);
            end
        end
    end

endmodule

