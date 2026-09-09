`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/07 16:53:56
// Design Name: 
// Module Name: gt_rx_reset
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


module gt_rx_reset #(
    parameter int RESET_HOLD_CYCLES = 16,
    parameter int REALIGN_WINDOW_CYCLES = 128000
)(
    input  logic i_freerun_clk,
    input  logic i_freerun_rst,

    input  logic i_soft_reset_all,
    input  logic i_rx_usrclk,
    input  logic i_gtwiz_reset_rx_done,
    input  logic i_sfp_los,
    input  logic i_rxbyterealign,

    output logic o_gtwiz_reset_rx_datapath,
    output logic o_rx_user_reset,
    output logic o_rx_channel_up
    );

    // =====================================================================
    // RX User Reset: Async assertion, sync release
    // =====================================================================
    logic rx_user_reset_assert;
    assign rx_user_reset_assert = i_freerun_rst | o_gtwiz_reset_rx_datapath | !i_gtwiz_reset_rx_done;

    (* ASYNC_REG = "TRUE" *) logic [2:0] rx_user_rst_pipe = 3'b111;
    always_ff @(posedge i_rx_usrclk or posedge rx_user_reset_assert) 
    begin
        if (rx_user_reset_assert)
            rx_user_rst_pipe <= 3'b111;
        else
            rx_user_rst_pipe <= {rx_user_rst_pipe[1:0], 1'b0};
    end

    assign o_rx_user_reset = rx_user_rst_pipe[2];

    // =====================================================================
    // Byte Realignment Monitor
    // =====================================================================
    logic        rxbyterealign_d1;
    logic        realign_pulse;  
    assign realign_pulse = i_rxbyterealign & ~rxbyterealign_d1;  

    always_ff @(posedge i_rx_usrclk) begin
        rxbyterealign_d1 <= i_rxbyterealign;
    end

    logic [19:0] realign_window_cnt;
    logic [1:0]  realign_cnt;
    logic [1:0]  realign_cnt_now;

    // Include the current event; saturate at 2 to count the window's last cycle.
    always_comb 
    begin
        if (realign_pulse && (realign_cnt < 2'd2))
            realign_cnt_now <= realign_cnt + 1'b1;
        else
            realign_cnt_now <= realign_cnt;
    end

    always_ff @(posedge i_rx_usrclk)
    begin
        if (o_rx_user_reset)
        begin
            realign_window_cnt <= 20'd0;
            realign_cnt        <= 2'd0;
        end
        else begin
            if (realign_window_cnt == REALIGN_WINDOW_CYCLES - 1)
            begin
                realign_window_cnt <= 20'd0;
                realign_cnt        <= 2'd0;
            end
            else begin
                realign_window_cnt <= realign_window_cnt + 1'b1;
                realign_cnt        <= realign_cnt_now;
            end
        end
    end

    logic realign_reset_req_rx;

    always_ff @(posedge i_rx_usrclk or posedge o_rx_user_reset)
    begin
        if (o_rx_user_reset)
            realign_reset_req_rx <= 1'b0;
        else if ((realign_window_cnt == REALIGN_WINDOW_CYCLES - 1) && (realign_cnt_now >= 2))
            realign_reset_req_rx <= 1'b1;
    end
    
    logic rx_channel_up_reg;

    always_ff @(posedge i_rx_usrclk or posedge o_rx_user_reset)
    begin
        if (o_rx_user_reset)
            rx_channel_up_reg <= 1'b0; 
        else if (realign_pulse | realign_reset_req_rx)
            rx_channel_up_reg <= 1'b0;
        else if ((realign_window_cnt == REALIGN_WINDOW_CYCLES - 1) && (realign_cnt_now == 2'd0))
            rx_channel_up_reg <= 1'b1;
    end

    assign o_rx_channel_up = rx_channel_up_reg &! o_rx_user_reset;

    // =====================================================================
    // Reset Requset CDC
    // =====================================================================
    (* ASYNC_REG = "TRUE" *) logic [1:0] realign_req_pipe;
    logic realign_reset_req_sync;

    always_ff @(posedge i_freerun_clk)
    begin
        if (i_freerun_rst)
            realign_req_pipe <= 2'b00;
        else 
            realign_req_pipe <= {realign_req_pipe[0], realign_reset_req_rx};
    end

    assign realign_reset_req_sync = realign_req_pipe[1];

    // =====================================================================
    // RX Reset State Machine
    // =====================================================================
    logic rx_reset_request;
    assign rx_reset_request = i_soft_reset_all | i_sfp_los;

    typedef enum logic [1:0] {
        ST_RESET,
        ST_WAIT_DONE,
        ST_RUN
    } rx_reset_state_t;

    rx_reset_state_t rx_reset_state;
    rx_reset_state_t rx_reset_next_state;
    
    always_ff @(posedge i_freerun_clk)
    begin
        if (i_freerun_rst)
            rx_reset_state <= ST_RESET;
        else
            rx_reset_state <= rx_reset_next_state;
    end

    logic [7:0]  hold_cnt;

    always_ff @(posedge i_freerun_clk)
    begin
        if (i_freerun_rst)
            hold_cnt <= 8'd0;
        else if (rx_reset_request)
            hold_cnt <= 8'd0;
        else if (rx_reset_state != ST_RESET)
            hold_cnt <= 8'd0;
        else if (hold_cnt != RESET_HOLD_CYCLES - 1)
            hold_cnt <= hold_cnt + 1'b1;
    end

    always_comb 
    begin
        case (rx_reset_state)
            ST_RESET: begin
                if (rx_reset_request)
                    rx_reset_next_state = ST_RESET;
                else if ((hold_cnt == RESET_HOLD_CYCLES - 1) & !i_gtwiz_reset_rx_done)
                    rx_reset_next_state = ST_WAIT_DONE;
                else
                    rx_reset_next_state = ST_RESET;
            end

            ST_WAIT_DONE: begin
                if (rx_reset_request)
                    rx_reset_next_state = ST_RESET;
                else if (i_gtwiz_reset_rx_done & !realign_reset_req_sync)
                    rx_reset_next_state = ST_RUN;
                else 
                    rx_reset_next_state = ST_WAIT_DONE;
            end

            ST_RUN: begin
                if (rx_reset_request | !i_gtwiz_reset_rx_done | realign_reset_req_sync)
                    rx_reset_next_state = ST_RESET;
                else
                    rx_reset_next_state = ST_RUN;
            end

            default: begin
                rx_reset_next_state = ST_RESET;
            end
        endcase
    end

    always_ff @(posedge i_freerun_clk)
    begin
        if (i_freerun_rst)
            o_gtwiz_reset_rx_datapath <= 1'b1;
        else 
            o_gtwiz_reset_rx_datapath <= (rx_reset_state == ST_RESET);
    end

endmodule

