`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/08 17:48:03
// Design Name: 
// Module Name: gt_tx_reset
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


module gt_tx_reset #(
    parameter int RESET_HOLD_CYCLES = 16
)(
    input  logic i_freerun_clk,
    input  logic i_freerun_rst,

    input  logic i_soft_reset_all,
    input  logic i_tx_usrclk,
    input  logic i_gtwiz_reset_tx_done,

    output logic o_gtwiz_reset_tx_datapath,
    output logic o_tx_user_reset,
    output logic o_tx_channel_up
    );

    typedef enum logic [1:0] {
        ST_RESET,
        ST_WAIT_DONE,
        ST_RUN
    } tx_reset_state_t;

    tx_reset_state_t tx_reset_state;
    tx_reset_state_t tx_reset_next_state;

    logic [7:0] hold_cnt;

    always_ff @(posedge i_freerun_clk) begin
        if (i_freerun_rst)
            tx_reset_state <= ST_RESET;
        else
            tx_reset_state <= tx_reset_next_state;
    end

    always_ff @(posedge i_freerun_clk) begin
        if (i_freerun_rst)
            hold_cnt <= 8'd0;
        else if (i_soft_reset_all)
            hold_cnt <= 8'd0;
        else if (tx_reset_state != ST_RESET)
            hold_cnt <= 8'd0;
        else if (hold_cnt != RESET_HOLD_CYCLES-1)
            hold_cnt <= hold_cnt + 1'b1;
    end

    always_comb begin
        case (tx_reset_state)

            ST_RESET: begin
                if (i_soft_reset_all)
                    tx_reset_next_state = ST_RESET;
                else if ((hold_cnt == RESET_HOLD_CYCLES-1) & !i_gtwiz_reset_tx_done)
                    tx_reset_next_state = ST_WAIT_DONE;
                else
                    tx_reset_next_state = ST_RESET;
            end

            ST_WAIT_DONE: begin
                if (i_soft_reset_all)
                    tx_reset_next_state = ST_RESET;
                else if (i_gtwiz_reset_tx_done)
                    tx_reset_next_state = ST_RUN;
                else
                    tx_reset_next_state = ST_WAIT_DONE;
            end

            ST_RUN: begin
                if (i_soft_reset_all | !i_gtwiz_reset_tx_done)
                    tx_reset_next_state = ST_RESET;
                else
                    tx_reset_next_state = ST_RUN;
            end

            default: begin
                tx_reset_next_state = ST_RESET;
            end

        endcase
    end

    always_ff @(posedge i_freerun_clk) begin
        if (i_freerun_rst)
            o_gtwiz_reset_tx_datapath <= 1'b1;
        else
            o_gtwiz_reset_tx_datapath <= (tx_reset_next_state == ST_RESET);
    end

    wire tx_user_reset_assert = i_freerun_rst | o_gtwiz_reset_tx_datapath | !i_gtwiz_reset_tx_done;

    (* ASYNC_REG = "TRUE" *)
    logic [2:0] tx_user_rst_pipe = 3'b111;

    always_ff @(posedge i_tx_usrclk or posedge tx_user_reset_assert) begin
        if (tx_user_reset_assert)
            tx_user_rst_pipe <= 3'b111;
        else
            tx_user_rst_pipe <= {tx_user_rst_pipe[1:0], 1'b0};
    end

    assign o_tx_user_reset = tx_user_rst_pipe[2];
    assign o_tx_channel_up = !o_tx_user_reset;
endmodule
