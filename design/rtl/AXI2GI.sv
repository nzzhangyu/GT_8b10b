`timescale 1ns / 1ps

module AXI2GI #(
    parameter int WORDS_IN_BRAM = 512
)(
    // GT Interface Status Signals
    input  logic [1:0]   i_gt_reset_tx_done,
    
    // User AXI-Stream Interface (From DDR/DMA)
    input  logic [63:0]  s_axi_rx_tdata, 
    input  logic [7:0]   s_axi_rx_tkeep, 
    input  logic         s_axi_rx_tvalid,
    output logic         s_axi_rx_tready,
    input  logic         s_axi_rx_tlast, 
    
    // GT Transceiver Interface Outputs
    output logic [63:0]  o_tx_data_out,   
    output logic [7:0]   o_txctrl_out,    

    // System Interface
    input  logic [1:0]   i_tx_usrclk,          
    input  logic         i_tx_user_reset    
    );

    // ====================================================================
    // Internal Signals & Types Declarations
    // ====================================================================

    // Elastic FIFO & Flow Control Signals
    logic          fifo_wr_en;
    logic          fifo_rd_en;
    logic [64:0]   fifo_din;          // {tlast, tdata}
    logic [64:0]   fifo_dout;
    logic          fifo_empty;
    logic          fifo_prog_full;
    logic          fifo_prog_empty;
    logic [15:0]   pkt_in_fifo;       // Tracks the number of complete packets in the FIFO

    logic          pkt_wr_done;
    logic          pkt_rd_done;
    logic [1:0]    pkt_stat;

    // Link Scheduler FSM & Timers
    typedef enum logic [2:0] {
        ST_IDLE,    // Send Physical Layer Keep-Alive (F7F7)
        ST_ALIGN,   // Send 64-cycle Alignment Sequence (BCBC)
        ST_SOF,     // Insert Start of Frame (1C1C1C1C)
        ST_DATA,    // Send Payload (Read from FIFO)
        ST_CRC,     // Insert CRC Checksum
        ST_EOF      // Insert End of Frame (FDFDFDFD)
    } link_state_t;
    
    link_state_t link_state = ST_IDLE;

    logic [11:0] timer_1us_cnt  = 12'd0;
    logic [5:0]  timer_32us_cnt = 6'd0;
    logic        need_align     = 1'b0;
    logic [5:0]  align_cnt      = 6'd0;

    // Datapath & Formatting Signals
    logic [63:0] tx_data_final;
    logic [7:0]  tx_ctrl_final;
    logic        clear_scrambler;

    logic [31:0] gt_idle_data;
    logic [3:0]  gt_idle_ctrl;
    logic [63:0] gt_align_data;
    logic [7:0]  gt_align_ctrl;
    // logic        align_en;

    logic [63:0] crc_result;
    logic        crc_clear;
    logic        crc_en;
    logic [15:0] crc_in_bus  [1:0];
    logic [15:0] crc_out_bus [1:0];

    // 4. FIFO CDC Outputs & Reset Sync Signals
    logic [35:0] lane_fifo_in [1:0];

    logic [35:0] lane_fifo_out [1:0];

    logic [31:0] tx_data_pre [1:0];

    logic [3:0]  tx_ctrl_pre [1:0];

    logic [31:0] tx_data_slice [1:0];
    logic [3:0]  tx_ctrl_slice [1:0];
    
    logic [1:0] rst_fifo;
    logic [1:0] gt_r0;
    logic [1:0] gt_r1;
    logic [1:0] gt_r2;
    logic [1:0] gt_r3;
    logic [1:0] gt_sync;

    // Lane FIFO health monitoring 
    logic [1:0] lane_fifo_full;
    logic [1:0] lane_fifo_empty;
    logic [1:0] lane_fifo_err_sticky;  // set if lane FIFO ever under/overflows

    // ====================================================================
    //  Core Logic Implementation
    // ====================================================================

    // --------------------------------------------------------------------
    // AXI-Stream Flow Control & Bubble Packing
    // --------------------------------------------------------------------
    assign s_axi_rx_tready = ~fifo_prog_full;
    
    assign fifo_wr_en = s_axi_rx_tvalid && s_axi_rx_tready;
    assign fifo_din   = {s_axi_rx_tlast, s_axi_rx_tdata};

    assign pkt_wr_done = fifo_wr_en & s_axi_rx_tlast;
    assign pkt_rd_done = fifo_rd_en & fifo_dout[64];
    assign pkt_stat    = {pkt_wr_done, pkt_rd_done};

    // Tracks complete frame count in FIFO to prevent underflow
    always_ff @(posedge i_tx_usrclk[0]) begin
        if (i_tx_user_reset) begin
            pkt_in_fifo <= 16'd0;
        end
        else begin
            case (pkt_stat)
                2'b10: 
                    pkt_in_fifo <= pkt_in_fifo + 1'b1; // Finished writing one packet
                2'b01: 
                    pkt_in_fifo <= pkt_in_fifo - 1'b1; // Finished reading one packet
                default: pkt_in_fifo <= pkt_in_fifo;      // No change
            endcase
        end
    end

    // XPM FIFO Instance
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE   ("block"), 
        .FIFO_WRITE_DEPTH   (4096),          
        .READ_MODE          ("fwft"),         
        .FIFO_READ_LATENCY  (0),
        .WRITE_DATA_WIDTH   (65),
        .READ_DATA_WIDTH    (65),
        .PROG_FULL_THRESH   (3072),    
        .PROG_EMPTY_THRESH  (WORDS_IN_BRAM),    
        .USE_ADV_FEATURES   ("0A02")   
    ) tx_elastic_fifo (
        .wr_clk      (i_tx_usrclk[0]    ),
        .rst         (i_tx_user_reset   ),
        .wr_en       (fifo_wr_en        ),
        .din         (fifo_din          ),
        .full        (                  ),            
        .prog_full   (fifo_prog_full    ),
            
        .rd_en       (fifo_rd_en        ),
        .dout        (fifo_dout         ),
        .empty       (fifo_empty        ),
        .prog_empty  (fifo_prog_empty   )
    );

    // --------------------------------------------------------------------
    // 32us Alignment Timer
    // --------------------------------------------------------------------
    always_ff @(posedge i_tx_usrclk[0]) begin
        if (i_tx_user_reset) begin
            timer_1us_cnt  <= 12'd0;
            timer_32us_cnt <= 6'd0;
            need_align     <= 1'b0;
        end 
        else begin
            if (timer_1us_cnt == 12'd67) begin
                timer_1us_cnt <= 12'd0;
                
                if (timer_32us_cnt == 6'd31) begin
                    timer_32us_cnt <= 6'd0;
                    need_align     <= 1'b1; 
                end 
                else begin
                    timer_32us_cnt <= timer_32us_cnt + 1'b1;
                end
            end 
            else begin
                timer_1us_cnt <= timer_1us_cnt + 1'b1;
            end

            if (link_state == ST_ALIGN && align_cnt == 6'd63) begin
                need_align <= 1'b0; 
            end
        end
    end

    // --------------------------------------------------------------------
    // Main Transmission FSM (GT Link Scheduler)
    // --------------------------------------------------------------------
    always_ff @(posedge i_tx_usrclk[0]) begin
        if (i_tx_user_reset) begin
            link_state <= ST_IDLE;
            align_cnt  <= 6'd0;
        end 
        else begin
            case (link_state)
                ST_IDLE: begin
                    if (need_align) begin
                        link_state <= ST_ALIGN;
                        align_cnt  <= 6'd0;
                    end 
                    else if ((pkt_in_fifo > 0 || !fifo_prog_empty) && !fifo_empty) begin
                        link_state <= ST_SOF;
                    end
                end

                ST_ALIGN: begin
                    if (align_cnt == 6'd63)
                        link_state <= ST_IDLE;
                    else
                        align_cnt <= align_cnt + 1'b1;
                end

                ST_SOF: begin
                    link_state <= ST_DATA;
                end

                ST_DATA: begin
                    if (fifo_rd_en && fifo_dout[64]) begin
                        link_state <= ST_CRC;
                    end
                end

                ST_CRC: begin
                    link_state <= ST_EOF; 
                end

                ST_EOF: begin
                    link_state <= ST_IDLE; 
                end

                default: link_state <= ST_IDLE;
            endcase
        end
    end

    // FSM auxiliary control signals
    assign fifo_rd_en = (link_state == ST_DATA) && !fifo_empty;
    assign crc_clear  = (link_state == ST_SOF);
    assign crc_en     = (link_state == ST_DATA) && !fifo_empty;
    // assign align_en   = (link_state == ST_ALIGN);

    // --------------------------------------------------------------------
    // [4] Data Formatting & Datapath Muxing
    // --------------------------------------------------------------------
    always_ff @(posedge i_tx_usrclk[0]) begin
        if (i_tx_user_reset) begin
            tx_data_final <= {2{32'hF7F7F7F7}};
            tx_ctrl_final <= {2{4'hF}};
        end 
        else begin
            case (link_state)
                ST_IDLE: begin
                    tx_data_final <= {2{gt_idle_data}}; 
                    tx_ctrl_final <= {2{gt_idle_ctrl}};
                end

                ST_ALIGN: begin
                    tx_data_final <= gt_align_data; 
                    tx_ctrl_final <= gt_align_ctrl;
                end

                ST_SOF: begin
                    tx_data_final <= {2{32'h1C1C1C1C}}; 
                    tx_ctrl_final <= {2{4'hF}};
                end

                ST_DATA: begin
                    if (!fifo_empty) begin
                        tx_data_final <= fifo_dout[63:0];   
                        tx_ctrl_final <= '0;
                    end 
                    else begin
                        tx_data_final <= {2{32'hFEFEFEFE}}; 
                        tx_ctrl_final <= {2{4'hF}};
                    end
                end
                
                ST_CRC: begin
                    tx_data_final <= crc_result;            
                    tx_ctrl_final <= '0;
                end
                
                ST_EOF: begin
                    tx_data_final <= {2{32'hFDFDFDFD}}; 
                    tx_ctrl_final <= {2{4'hF}};
                end

                default: begin
                    tx_data_final <= {2{32'hF7F7F7F7}}; 
                    tx_ctrl_final <= {2{4'hF}};
                end
            endcase
        end
    end

    // --------------------------------------------------------------------
    // K-Code Generators & CRC Engines
    // --------------------------------------------------------------------
    
    // Idle / Keep-Alive Generator
    gt_idle_Kcode_gen gt_idle_Kcode_gen ( 
        .TX_DATA_OUT(gt_idle_data   ), 
        .TXCTRL_OUT (gt_idle_ctrl   ),    
        .USER_CLK   (i_tx_usrclk[0]  ), 
        .ENABLE     (1'b1           ) 
    );

    // Lane Alignment Sequence Generator 
    for (genvar lane = 0; lane < 2; lane++) begin : gen_align
        gtwizard_2_GT_INITSEQ_GEN align_gen (
            .TX_DATA_OUT(gt_align_data[lane*32 +: 32]  ), 
            .TXCTRL_OUT (gt_align_ctrl[lane*4  +: 4 ]  ),
            .USER_CLK   (i_tx_usrclk[0]                 ), 
            .ENABLE     (need_align                    )
        );
    end

    // 4-way Parallel CRC16 Calculation
    for (genvar i = 0; i < 4; i++) begin : gen_crc_data
        assign crc_in_bus[i]          = fifo_dout[i*16 +: 16];
        assign crc_result[i*16 +: 16] = crc_out_bus[i];
    end

    for (genvar i = 0; i < 4; i++) begin : gen_crc
        CRC_16 tx_crc_inst (
            .i_clk       (i_tx_usrclk[0]  ), 
            .i_rst       (i_tx_user_reset ), 
            .i_crc_clear (crc_clear       ),
            .i_crc_en    (crc_en          ), 
            .i_data      (crc_in_bus[i]   ), 
            .o_crc       (crc_out_bus[i]  )
        );
    end

    // --------------------------------------------------------------------
    // Scrambler & Final CDC FIFOs (Lane processing)
    // --------------------------------------------------------------------
    assign clear_scrambler = (tx_data_final == {2{32'h1C1C1C1C}}) && (tx_ctrl_final == {2{4'hF}});
    
    for (genvar lane = 0; lane < 2; lane++) begin : gen_lane_path
        assign tx_data_slice[lane] = tx_data_final[lane*32 +: 32];
        assign tx_ctrl_slice[lane] = tx_ctrl_final[lane*4  +: 4 ];

        aurora_8b10b_SCRAMBLER_TOP scrambler_lane (
            .DATA_OUT      (tx_data_pre[lane]   ), 
            .CHAR_IS_K_OUT (tx_ctrl_pre[lane]   ),
            .DATA          (tx_data_slice[lane] ), 
            .CHAR_IS_K     (tx_ctrl_slice[lane] ),
            .CLEAR         (clear_scrambler     ), 
            .RESET         (i_tx_user_reset     ), 
            .USER_CLK      (i_tx_usrclk[0]      )
        );

        assign lane_fifo_in[lane] = {tx_data_pre[lane], tx_ctrl_pre[lane]};

        fifo_rx_gtdata fifo_lane (
            .rst    (~rst_fifo[lane]       ), 
            .wr_clk (i_tx_usrclk[0]        ), 
            .rd_clk (i_tx_usrclk[1]        ),
            .din    (lane_fifo_in[lane]    ), 
            .wr_en  (1'b1                  ), 
            .rd_en  (1'b1                  ),
            .dout   (lane_fifo_out[lane]   ), 
            .full   (lane_fifo_full[lane]  ), 
            .empty  (lane_fifo_empty[lane] )
        );

        assign o_tx_data_out[lane*32 +: 32] = lane_fifo_out[lane][35:4];
        assign o_txctrl_out[lane*4  +: 4 ]  = lane_fifo_out[lane][3:0];

        always_ff @(posedge i_tx_usrclk) begin
            {gt_sync[lane], gt_r3[lane], gt_r2[lane], gt_r1[lane], gt_r0[lane]} <=
                {gt_r3[lane], gt_r2[lane], gt_r1[lane], gt_r0[lane], i_gt_reset_tx_done[lane]};
            rst_fifo[lane] <= gt_sync[lane];
        end

        // FIFO health monitor
        always_ff @(posedge i_tx_usrclk[0]) begin
            if (i_tx_user_reset) 
                lane_fifo_err_sticky[lane] <= 1'b0;
            else
                lane_fifo_err_sticky[lane] <= lane_fifo_full[lane] | lane_fifo_empty[lane];
        end
    end

endmodule   
