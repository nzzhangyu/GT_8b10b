`timescale 1ns / 1ps

module GI2AXI #(
    parameter int WORDS_IN_BRAM = 512,
    parameter int LANE_NUM      = 2
)(
    // GT RX Interface Status
    input  logic [LANE_NUM-1:0]     i_gt_rxresetdone,
    input  logic [LANE_NUM*32-1:0]  i_rx_data_in,
    input  logic [LANE_NUM*4-1:0]   i_rxctrl_in,
    input  logic [LANE_NUM-1:0]     i_rx_clk,

    // User AXI-Stream Interface (To DDR)
    output logic [LANE_NUM*32-1:0]  o_m_axi_tx_tdata,
    output logic [LANE_NUM*4-1:0]   o_m_axi_tx_tkeep,
    output logic                    o_m_axi_tx_tvalid,
    input  logic                    i_m_axi_tx_tready,
    output logic                    o_m_axi_tx_tlast,

    // System Interface
    input  logic                    i_user_clk,        // System AXI clock
    input  logic                    i_system_reset,

    // Status Signals           
    output logic                    o_lane_aligned,    // Indicates both lanes are deskewed
    output logic                    o_rx_crc_error     // Pulses high if CRC mismatch
    );

    // ====================================================================
    // Internal Signals & Types Declarations
    // ====================================================================

    // Reset & System Ready
    logic                   sys_ready;
    logic                   async_fifo_rst;
    logic [LANE_NUM-1:0]    rd_rst_busy;

    // Deskew FIFO Signals
    logic [35:0]            fifo_dout [LANE_NUM-1:0];
    logic [LANE_NUM-1:0]    fifo_empty;
    logic [LANE_NUM-1:0]    fifo_rd_en;
    logic [LANE_NUM-1:0]    lane_is_align;
    logic                   aligned_rd_en;

    logic [LANE_NUM*32-1:0] aligned_data;
    logic [LANE_NUM*4-1:0]  aligned_ctrl;

    // Deskew FSM
    typedef enum logic [1:0] {
        ST_DSK_INIT,
        ST_DSK_WAIT_ALIGN,
        ST_DSK_ALIGNED
    } deskew_state_t;
    deskew_state_t dsk_state = ST_DSK_INIT;

    logic [3:0] err_align_cnt;

    // Descrambler Signals
    logic [LANE_NUM*32-1:0] desc_data;
    logic [LANE_NUM*4-1:0]  desc_ctrl;
    logic                   clear_scrambler;

    // Framer & Delay Line Signals
    logic is_sof_raw;
    logic is_eof_raw;
    logic in_frame = 1'b0;

    logic [LANE_NUM*32-1:0] rx_data_d0;
    logic [LANE_NUM*32-1:0] rx_data_d1;
    logic [LANE_NUM*32-1:0] rx_data_d2;

    logic [LANE_NUM*4-1:0]  rx_ctrl_d0;
    logic [LANE_NUM*4-1:0]  rx_ctrl_d1;
    logic [LANE_NUM*4-1:0]  rx_ctrl_d2;

    logic valid_d0;
    logic valid_d1;
    logic valid_d2;

    logic is_sof_d0;
    logic is_eof_d0;
    logic is_eof_d1;

    logic in_frame_d0;
    logic in_frame_d1;
    logic in_frame_d2;

    // RX Elastic FIFO Signals
    logic                   write_to_axi;
    logic                   axi_tlast_d2;
    logic                   rx_fifo_empty;
    logic [LANE_NUM*32:0]   rx_fifo_dout;
    logic                   rx_fifo_prog_full;
    logic                   rx_overflow_drop;    // drop current frame  

    // CRC 
    logic                   crc_en;
    logic                   crc_clear;
    logic [LANE_NUM*32-1:0] crc_result;
    logic [15:0]            crc_in_bus [LANE_NUM*2-1:0];
    logic [15:0]            crc_out_bus[LANE_NUM*2-1:0];

    // ====================================================================
    // Core Logic Implementation
    // ====================================================================
    
    // --------------------------------------------------------------------
    // System Reset Generation
    // --------------------------------------------------------------------
    assign sys_ready      = &i_gt_rxresetdone;
    assign async_fifo_rst = i_system_reset | ~sys_ready;

    // --------------------------------------------------------------------
    // Lane Deskew Buffers (Async FIFOs for Clock Bridging & Deskew)
    // --------------------------------------------------------------------
    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_deskew_fifo
        xpm_fifo_async #(
            .FIFO_MEMORY_TYPE("distributed"),
            .FIFO_WRITE_DEPTH(64),
            .READ_MODE("fwft"),
            .WRITE_DATA_WIDTH(36),
            .READ_DATA_WIDTH(36),
            .USE_ADV_FEATURES("0000")
        ) deskew_fifo_lane (
            .rst         (async_fifo_rst                                            ),
            .wr_clk      (i_rx_clk[lane]                                            ),
            .wr_en       (1'b1                                                      ),
            .din         ({i_rxctrl_in[lane*4 +: 4], i_rx_data_in[lane*32 +: 32]}   ),
            .full        (                                                          ),
            .prog_full   (                                                          ),
            .wr_rst_busy (                                                          ),
            .rd_clk      (i_user_clk                                                ),
            .rd_en       (fifo_rd_en[lane]                                          ),
            .dout        (fifo_dout[lane]                                           ),
            .empty       (fifo_empty[lane]                                          ),
            .prog_empty  (                                                          ),
            .rd_rst_busy (rd_rst_busy[lane]                                         )
        );
    end

    // --------------------------------------------------------------------
    // Deskew Alignment FSM
    // --------------------------------------------------------------------
    // Look-ahead for K28.5 Alignment Characters (BCBCBCBC with Ctrl=F)
    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_align_detect
        assign lane_is_align[lane] = (fifo_dout[lane][31:0] == 32'hBCBCBCBC) && (fifo_dout[lane][35:32] == 4'hF);
    end

    always_ff @(posedge i_user_clk) begin 
        if (async_fifo_rst || |rd_rst_busy) begin
            dsk_state      <= ST_DSK_INIT;
            o_lane_aligned <= 1'b0;
            err_align_cnt  <= 4'd0;
        end
        else begin
            case (dsk_state)
                ST_DSK_INIT: begin
                    err_align_cnt <= 4'd0;
                    if (!(|fifo_empty))
                        dsk_state <= ST_DSK_WAIT_ALIGN;
                end

                ST_DSK_WAIT_ALIGN: begin
                    // Once BOTH lanes hit the alignment character, lock alignment
                    if (&lane_is_align) begin
                        dsk_state      <= ST_DSK_ALIGNED;
                        o_lane_aligned <= 1'b1;
                    end
                end

                ST_DSK_ALIGNED: begin
                    logic align_mismatch;
                    align_mismatch = 1'b0;

                    if (!(&lane_is_align)) begin
                        align_mismatch = 1'b1;
                    end
                    else begin
                        for (int lane = 1; lane < LANE_NUM; lane++) begin
                            if (fifo_dout[lane] != fifo_dout[0]) begin
                                align_mismatch = 1'b1;
                            end
                        end
                    end

                    if (align_mismatch) begin
                        if (err_align_cnt == 4'd15) begin
                            dsk_state      <= ST_DSK_INIT;
                            o_lane_aligned <= 1'b0;
                            err_align_cnt  <= 4'd0;
                        end
                        else begin
                            err_align_cnt <= err_align_cnt + 1'b1;
                        end
                    end
                    else begin
                        err_align_cnt <= 4'd0;
                    end
                end

                default: begin
                    dsk_state      <= ST_DSK_INIT;
                    o_lane_aligned <= 1'b0;
                    err_align_cnt  <= 4'd0;
                end
            endcase
        end
    end

    // Deskew Read Logic
    // Advance independent pointers during WAIT until they both point to ALIGN.
    // Once ALIGNED, lock them together and only read when BOTH have data.
    assign aligned_rd_en = (dsk_state == ST_DSK_ALIGNED) && !(|fifo_empty);
    
    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_deskew_read
        assign fifo_rd_en[lane]            = (dsk_state == ST_DSK_WAIT_ALIGN && !fifo_empty[lane] && !lane_is_align[lane]) || aligned_rd_en;
        assign aligned_data[lane*32 +: 32] = fifo_dout[lane][31:0];
        assign aligned_ctrl[lane*4  +: 4 ] = fifo_dout[lane][35:32];
    end

    // --------------------------------------------------------------------
    //[4] Descrambler
    // --------------------------------------------------------------------
    // Descrambler is cleared when SOF is detected in the aligned data
    assign clear_scrambler = (aligned_data == {LANE_NUM{32'h1C1C1C1C}}) && (aligned_ctrl == {LANE_NUM{4'hF}});

    for (genvar lane = 0; lane < LANE_NUM; lane++) begin : gen_descrambler
        aurora_8b10b_SCRAMBLER_TOP descrambler_lane (
            .DATA          (aligned_data[lane*32 +: 32] ),
            .CHAR_IS_K     (aligned_ctrl[lane*4  +: 4 ] ),
            .CLEAR         (clear_scrambler             ),
            .RESET         (async_fifo_rst              ),
            .USER_CLK      (i_user_clk                  ),
            .DATA_OUT      (desc_data[lane*32 +: 32]    ),
            .CHAR_IS_K_OUT (desc_ctrl[lane*4  +: 4 ]    )
        );
    end

    // --------------------------------------------------------------------
    // Framer & Delay Line (Look-ahead architecture)
    // --------------------------------------------------------------------
    assign is_sof_raw = (desc_data == {LANE_NUM{32'h1C1C1C1C}}) && (desc_ctrl == {LANE_NUM{4'hF}});
    assign is_eof_raw = (desc_data == {LANE_NUM{32'hFDFDFDFD}}) && (desc_ctrl == {LANE_NUM{4'hF}});

    always_ff @(posedge i_user_clk) begin
        if (async_fifo_rst) begin
            valid_d0 <= 1'b0;
            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;
        end
        else begin
            valid_d0 <= aligned_rd_en;
            valid_d1 <= valid_d0;
            valid_d2 <= valid_d1;
        end
    end

    always_ff @(posedge i_user_clk) begin
        if (async_fifo_rst) 
            in_frame <= 1'b0;
        else if (aligned_rd_en) begin
            if (is_sof_raw)
                in_frame <= 1'b1;
            else if (is_eof_raw)
                in_frame <= 1'b0;
        end
    end

    always_ff @(posedge i_user_clk) begin
        if (aligned_rd_en) begin
            rx_data_d0  <= desc_data;
            rx_ctrl_d0  <= desc_ctrl;
            is_sof_d0   <= is_sof_raw;
            is_eof_d0   <= is_eof_raw;
            in_frame_d0 <= in_frame;
        end

        if (valid_d0) begin
            rx_data_d1  <= rx_data_d0;
            rx_ctrl_d1  <= rx_ctrl_d0;
            is_eof_d1   <= is_eof_d0;
            in_frame_d1 <= in_frame_d0;
        end

        if (valid_d1) begin
            rx_data_d2  <= rx_data_d1;
            rx_ctrl_d2  <= rx_ctrl_d1;
            in_frame_d2 <= in_frame_d1;
        end
    end

    // --------------------------------------------------------------------
    // RX Payload Extraction & CRC Checking
    // --------------------------------------------------------------------
    // TLAST Logic: If d0 is EOF, then d2 is currently the last payload byte.
    assign axi_tlast_d2 = is_eof_d0;

    always_ff @(posedge i_user_clk) begin
        if (async_fifo_rst) begin
            rx_overflow_drop <= 1'b0;
        end
        else begin
            if (rx_fifo_prog_full) 
                rx_overflow_drop <= 1'b1; 
            else if (valid_d0 && is_sof_raw) 
                rx_overflow_drop <= 1'b0; 
        end
    end

    // A byte is valid Payload if it's inside a frame, has no K-chars, 
    // and is NOT the CRC. If d1 is EOF, it guarantees d2 is the CRC.
    assign write_to_axi = valid_d2 && in_frame_d2 && (rx_ctrl_d2 == '0) && !is_eof_d1 && !rx_overflow_drop;

    // CRC Error Detection
    always_ff @(posedge i_user_clk) begin
        if (async_fifo_rst) 
            o_rx_crc_error <= 1'b0;
        else if (valid_d0 && is_sof_raw) begin
            o_rx_crc_error <= 1'b0; // Clear error on new frame
        end
        else if (valid_d2 && is_eof_d1) begin
            // When d1 is EOF, d2 contains the CRC received from TX.
            // crc_result contains the CRC just computed up to d3 payload.
            if (crc_result != rx_data_d2) 
                o_rx_crc_error <= 1'b1;
        end
    end

    // CRC Computation Engine
    assign crc_en    = write_to_axi;
    assign crc_clear = valid_d0 && is_sof_raw;

    for (genvar i = 0; i < LANE_NUM*2; i++) begin : gen_crc_data
        assign crc_in_bus[i]          = rx_data_d2[i*16 +: 16];
        assign crc_result[i*16 +: 16] = crc_out_bus[i];
    end

    for (genvar i = 0; i < LANE_NUM*2; i++) begin : gen_rx_crc
        CRC_16 rx_crc_inst (
            .i_clk       (i_user_clk      ), 
            .i_rst       (async_fifo_rst  ), 
            .i_crc_clear (crc_clear       ),
            .i_crc_en    (crc_en          ), 
            .i_data      (crc_in_bus[i]   ), 
            .o_crc       (crc_out_bus[i]  )
        );
    end

    // --------------------------------------------------------------------
    // RX Elastic AXI FIFO (Isolates link clock stops from AXI domain)
    // --------------------------------------------------------------------
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"), 
        .FIFO_WRITE_DEPTH(4096),     
        .READ_MODE("fwft"),         
        .FIFO_READ_LATENCY(0),
        .WRITE_DATA_WIDTH(LANE_NUM*32+1),
        .READ_DATA_WIDTH(LANE_NUM*32+1),
        .USE_ADV_FEATURES("0707")   
    ) rx_elastic_fifo (
        .wr_clk      (i_user_clk                            ),
        .rst         (async_fifo_rst                        ),
        .wr_en       (write_to_axi                          ),
        .din         ({axi_tlast_d2, rx_data_d2}            ),
        .full        (                                      ), 
        .prog_full   (rx_fifo_prog_full                     ),           
            
        .rd_en       (o_m_axi_tx_tvalid && i_m_axi_tx_tready),
        .dout        (rx_fifo_dout                          ),
        .empty       (rx_fifo_empty                         ),
        .prog_empty  (                                      )
    );

    // Final AXI-Stream Mapping
    assign o_m_axi_tx_tvalid = ~rx_fifo_empty;
    assign o_m_axi_tx_tdata  = rx_fifo_dout[63:0];
    assign o_m_axi_tx_tlast  = rx_fifo_dout[64];
    assign o_m_axi_tx_tkeep  = {LANE_NUM*4{1'b1}};
    


endmodule
