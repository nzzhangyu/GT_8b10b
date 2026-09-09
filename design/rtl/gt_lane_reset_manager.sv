`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/07 10:51:33
// Design Name: 
// Module Name: gt_lane_reset_manager
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


module gt_lane_reset_manager(
    input  logic i_freerun_clk,
    input  logic i_sys_rst,
 
    input  logic i_soft_reset_all,

    input  logic [1:0] i_tx_usrclk,
    input  logic [1:0] i_rx_usrclk,

    input  logic [1:0] i_gtwiz_reset_tx_done,
    input  logic [1:0] i_gtwiz_reset_rx_done,

    input  logic [1:0] i_sfp_los,

    input  logic [1:0] i_rxbyterealign,

    output logic [1:0] o_gtwiz_reset_tx_datapath,
    output logic [1:0] o_gtwiz_reset_rx_datapath,

    output logic [1:0] o_tx_user_reset,
    output logic [1:0] o_rx_user_reset,

    output logic [1:0] o_tx_channel_up,
    output logic [1:0] o_rx_channel_up
    );

    // freerun reset synchronizer
    (* ASYNC_REG = "TRUE" *) logic [2:0] freerun_rst_pipe = 3'b111;
    wire freerun_rst = freerun_rst_pipe[2];

    always_ff @(posedge i_freerun_clk or posedge i_sys_rst) 
    begin
        if (i_sys_rst)
            freerun_rst_pipe <= 3'b111;
        else
            freerun_rst_pipe <= {freerun_rst_pipe[1:0], 1'b0};
    end

    // async input synchronizer
    (* ASYNC_REG = "TRUE" *) logic [1:0] soft_reset_all_pipe = 2'b00;
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_tx_done_d1;
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_tx_done_d2;
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_rx_done_d1;
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_rx_done_d2;
    (* ASYNC_REG = "TRUE" *) logic [1:0] sfp_los_d1;
    (* ASYNC_REG = "TRUE" *) logic [1:0] sfp_los_d2;
    wire soft_reset_all_sync = soft_reset_all_pipe[1];

    always_ff @(posedge i_freerun_clk)
    begin
        if (freerun_rst)
            soft_reset_all_pipe <= 2'b00;
        else 
            soft_reset_all_pipe <= {soft_reset_all_pipe[0], i_soft_reset_all};
    end

    always_ff @(posedge i_freerun_clk)
    begin
        if (freerun_rst)
        begin

            reset_tx_done_d1 <= 2'b00;
            reset_tx_done_d2 <= 2'b00;

            reset_rx_done_d1 <= 2'b00;
            reset_rx_done_d2 <= 2'b00;

            sfp_los_d1 <= 2'b11;
            sfp_los_d2 <= 2'b11;
        end  
        else begin

            reset_tx_done_d1 <= i_gtwiz_reset_tx_done;
            reset_tx_done_d2 <= reset_tx_done_d1;

            reset_rx_done_d1 <= i_gtwiz_reset_rx_done;
            reset_rx_done_d2 <= reset_rx_done_d1;

            sfp_los_d1 <= i_sfp_los;
            sfp_los_d2 <= sfp_los_d1;
        end
    end

    // Tx reset logic
    generate 
        for (genvar i = 0; i < 2; i = i + 1) begin : tx_lane_reset
            gt_tx_reset # (
                .RESET_HOLD_CYCLES(16)
            ) gt_tx_reset_inst (
                .i_freerun_clk              (i_freerun_clk                  ),
                .i_freerun_rst              (freerun_rst                    ),
                .i_soft_reset_all           (soft_reset_all_sync            ),
                .i_tx_usrclk                (i_tx_usrclk[i]                 ),
                .i_gtwiz_reset_tx_done      (reset_tx_done_d2[i]            ),
                .o_gtwiz_reset_tx_datapath  (o_gtwiz_reset_tx_datapath[i]   ),
                .o_tx_user_reset            (o_tx_user_reset[i]             ),
                .o_tx_channel_up            (o_tx_channel_up[i]             )
            );
        end  
    endgenerate

    // Rx reset logic
    generate
        for (genvar i = 0; i < 2; i = i + 1) begin : rx_lane_reset
            gt_rx_reset # (
                .RESET_HOLD_CYCLES(16)
            )
            u_gt_rx_reset (
                .i_freerun_clk              (i_freerun_clk                 ),
                .i_freerun_rst              (freerun_rst                   ),
                .i_soft_reset_all           (soft_reset_all_sync           ),
                .i_rx_usrclk                (i_rx_usrclk[i]                ),
                .i_gtwiz_reset_rx_done      (reset_rx_done_d2[i]           ),
                .i_sfp_los                  (sfp_los_d2[i]                 ),
                .i_rxbyterealign            (i_rxbyterealign[i]            ),
                .o_gtwiz_reset_rx_datapath  (o_gtwiz_reset_rx_datapath[i]  ),
                .o_rx_user_reset            (o_rx_user_reset[i]            ),
                .o_rx_channel_up            (o_rx_channel_up[i]            )
            );

        end
    endgenerate

    
    
endmodule
