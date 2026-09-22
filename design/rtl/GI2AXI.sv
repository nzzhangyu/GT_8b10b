`timescale 1ns / 1ps

module GI2AXI #(
    parameter int WORDS_IN_BRAM = 512
)(
    // GT RX Interface Status
    input  logic [1:0]   i_gt_reset_rx_done,
    input  logic [31:0]  i_rx_data_in[1:0],
    input  logic [3:0]   i_rxctrl_in[1:0],
    input  logic [1:0]   i_rx_usrclk,
    input  logic [1:0]   i_rx_user_reset,

    // User AXI-Stream Interface (To DDR)
    output logic [63:0]  m_axi_rx_tdata,
    output logic [7:0]   m_axi_rx_tkeep,
    output logic         m_axi_rx_tvalid,
    input  logic         m_axi_rx_tready,
    output logic         m_axi_rx_tlast,
    output logic         m_axi_rx_aresetn,

    // Status Signals           
    output logic         o_lane_aligned,    // Indicates both lanes are deskewed
    output logic         o_rx_crc_error,    // High after a CRC mismatch until next SOF
    output logic         o_rx_frame_drop    // Pulses when one complete frame is discarded
    );

    // Reset & System Ready
    (* ASYNC_REG = "TRUE" *) logic [1:0]    gt_reset_rx_done_d1;
    (* ASYNC_REG = "TRUE" *) logic [1:0]    gt_reset_rx_done_d2;
    logic          all_lanes_ready;
    logic          rx_core_reset;
    logic          rx_logic_reset;
    logic          rx_core_clk;

    assign rx_core_clk      = i_rx_usrclk[0];
    assign m_axi_rx_aresetn = ~rx_core_reset;

    // Deskew FIFO Signals
    logic [35:0]   fifo_dout [1:0];
    logic [1:0]    fifo_empty;
    logic [1:0]    fifo_full;
    logic [1:0]    fifo_rd_en;
    logic [1:0]    fifo_wr_en;
    logic [1:0]    fifo_wr_rst_busy;
    logic [1:0]    fifo_rd_rst_busy;
    logic [1:0]    lane_is_align;
    logic [1:0]    lane_seen_align;
    logic [1:0]    lane_at_boundary;
    logic          aligned_rd_en;

    logic [63:0]   aligned_data;
    logic [7:0]    aligned_ctrl;

    // Deskew FSM
    typedef enum logic [1:0] {
        ST_DSK_INIT,
        ST_DSK_WAIT_ALIGN,
        ST_DSK_ALIGNED
    } deskew_state_t;
    deskew_state_t dsk_state = ST_DSK_INIT;

    logic [3:0]  align_mismatch_cnt;

    // Descrambler Signals
    logic [63:0] desc_data;
    logic [7:0]  desc_ctrl;
    logic        clear_scrambler;
    logic        desc_valid;

    // Framer & Delay Line Signals
    logic is_sof_raw;
    logic is_eof_raw;
    logic in_frame = 1'b0;

    logic [63:0] rx_data_d0;
    logic [63:0] rx_data_d1;
    logic [63:0] rx_data_d2;
    logic [7:0]  rx_ctrl_d0;
    logic [7:0]  rx_ctrl_d1;
    logic [7:0]  rx_ctrl_d2;

    logic valid_d0;
    logic valid_d1;
    logic valid_d2;
    logic is_sof_d0;
    logic is_sof_d1;
    logic is_sof_d2;
    logic is_eof_d0;
    logic is_eof_d1;
    logic in_frame_d0;
    logic in_frame_d1;
    logic in_frame_d2;

    // RX Store-and-Forward FIFO Signals
    localparam int RX_FIFO_DEPTH          = 4096;
    localparam int RX_PROG_FULL_THRESH    = 3072;
    localparam int FRAME_BEAT_COUNT_WIDTH = $clog2(RX_FIFO_DEPTH + 1);
    localparam int FRAME_DESC_WIDTH       = FRAME_BEAT_COUNT_WIDTH + 1;

    logic          payload_valid_d2;
    logic          write_to_axi;
    logic          axi_tlast_d2;
    logic          rx_fifo_empty;
    logic          rx_fifo_full;
    logic [64:0]   rx_fifo_dout;
    logic          rx_fifo_prog_full;
    logic          rx_overflow_drop;    // drop current frame  
    logic          rx_fifo_rd_en;

    logic          rx_frame_active;
    logic          rx_frame_format_bad;
    logic [FRAME_BEAT_COUNT_WIDTH-1:0] frame_stored_beats;
    logic [FRAME_BEAT_COUNT_WIDTH-1:0] frame_count_after_write;
    logic          frame_sof_event;
    logic          frame_end_event;
    logic          frame_crc_bad;
    logic          illegal_control_event;

    logic [FRAME_DESC_WIDTH-1:0] frame_desc_din;
    logic [FRAME_DESC_WIDTH-1:0] frame_desc_dout;
    logic          frame_desc_wr_en;
    logic          frame_desc_rd_en;
    logic          frame_desc_empty;
    logic          frame_desc_full;
    logic          frame_drop_decision;

    typedef enum logic [1:0] {
        ST_OUT_IDLE,
        ST_OUT_COMMIT,
        ST_OUT_DROP
    } output_state_t;
    output_state_t output_state;
    logic [FRAME_BEAT_COUNT_WIDTH-1:0] output_beats_remaining;

    // CRC 
    logic        crc_en;
    logic        crc_clear;
    logic [63:0] crc_result;
    logic [15:0] crc_in_bus [3:0];
    logic [15:0] crc_out_bus[3:0];

    // --------------------------------------------------------------------
    // // RX lane ready signals synchronization and AXI-domain reset generation
    // --------------------------------------------------------------------
    for (genvar lane = 0; lane < 2; lane++) begin: gen_lane_ready_sync
        always_ff @(posedge rx_core_clk or posedge i_rx_user_reset[lane])
        begin
            if (i_rx_user_reset[lane]) begin
                gt_reset_rx_done_d1[lane] <= 1'b0;
                gt_reset_rx_done_d2[lane] <= 1'b0;
            end
            else begin
                gt_reset_rx_done_d1[lane] <= i_gt_reset_rx_done[lane];
                gt_reset_rx_done_d2[lane] <= gt_reset_rx_done_d1[lane];
            end
        end
    end

    assign all_lanes_ready  = &gt_reset_rx_done_d2;
    assign rx_core_reset  = ~all_lanes_ready;
    assign rx_logic_reset = rx_core_reset | (|fifo_rd_rst_busy);

    // --------------------------------------------------------------------
    // Lane Deskew Buffers (Async FIFOs for Clock Bridging & Deskew)
    // --------------------------------------------------------------------
    generate
        for (genvar lane = 0; lane < 2; lane++) begin : gen_deskew_fifo
            assign fifo_wr_en[lane] = 
                i_gt_reset_rx_done[lane] &
                !i_rx_user_reset[lane] &
                !fifo_wr_rst_busy[lane] &
                !fifo_full[lane];

            xpm_fifo_async #(
                .FIFO_MEMORY_TYPE   ("distributed"  ),
                .FIFO_WRITE_DEPTH   (64             ),
                .READ_MODE          ("fwft"         ),
                .WRITE_DATA_WIDTH   (36             ),
                .READ_DATA_WIDTH    (36             ),
                .USE_ADV_FEATURES   ("0000"         )
            ) deskew_fifo_lane (
                .rst         (i_rx_user_reset[lane]                   ),
                .wr_clk      (i_rx_usrclk[lane]                       ),
                .wr_en       (fifo_wr_en[lane]                        ),
                .din         ({i_rxctrl_in[lane], i_rx_data_in[lane]} ),
                .full        (fifo_full[lane]                         ),
                .prog_full   (                                        ),
                .wr_rst_busy (fifo_wr_rst_busy[lane]                  ),
                .rd_clk      (rx_core_clk                             ),
                .rd_en       (fifo_rd_en[lane]                        ),
                .dout        (fifo_dout[lane]                         ),
                .empty       (fifo_empty[lane]                        ),
                .prog_empty  (                                        ),
                .rd_rst_busy (fifo_rd_rst_busy[lane]                  )
            );
        end
    endgenerate 

    // ================================================================
    // Alignment character detection
    // ================================================================
    // K28.5 alignment word:
    //   data = BC BC BC BC
    //   ctrl = 1111

    generate
        for (genvar lane = 0; lane < 2; lane++) begin : gen_align_detect
            assign lane_is_align[lane] = 
                !fifo_empty[lane] &&
                fifo_dout[lane][31:0] == 32'hBCBCBCBC && 
                fifo_dout[lane][35:32] == 4'hF;
        end
    endgenerate

    // ================================================================
    // Deskew alignment state machine
    // ================================================================

    always_ff @(posedge rx_core_clk) begin 
        if (rx_logic_reset) begin
            dsk_state           <= ST_DSK_INIT;
            o_lane_aligned      <= 1'b0;
            align_mismatch_cnt  <= 4'd0;
            lane_seen_align     <= 2'b00;
            lane_at_boundary    <= 2'b00;
        end
        else begin
            case (dsk_state)
                ST_DSK_INIT: begin
                    o_lane_aligned     <= 1'b0;
                    align_mismatch_cnt <= 4'd0;
                    lane_seen_align    <= 2'b00;
                    lane_at_boundary   <= 2'b00;
                    if (!(|fifo_empty))
                        dsk_state <= ST_DSK_WAIT_ALIGN;
                end

                ST_DSK_WAIT_ALIGN: begin
                    o_lane_aligned     <= 1'b0;
                    align_mismatch_cnt <= 4'd0;

                    // A repeated BC word identifies the alignment interval, but
                    // not a unique word within that interval.  Consume each
                    // lane through the complete BC run, then hold its first
                    // post-alignment word until both lanes reach that boundary.
                    for (int lane = 0; lane < 2; lane++) begin
                        if (!fifo_empty[lane] && !lane_at_boundary[lane]) begin
                            if (!lane_seen_align[lane] && lane_is_align[lane])
                                lane_seen_align[lane] <= 1'b1;
                            else if (lane_seen_align[lane] && !lane_is_align[lane])
                                lane_at_boundary[lane] <= 1'b1;
                        end
                    end

                    if (&lane_at_boundary) begin
                        dsk_state      <= ST_DSK_ALIGNED;
                        o_lane_aligned <= 1'b1;
                    end
                end

                ST_DSK_ALIGNED: begin
                    o_lane_aligned <= 1'b1;

                    if (aligned_rd_en && (^lane_is_align)) begin
                        if (align_mismatch_cnt == 4'd15) begin
                            dsk_state          <= ST_DSK_INIT;
                            o_lane_aligned     <= 1'b0;
                            align_mismatch_cnt <= 4'd0;
                            lane_seen_align    <= 2'b00;
                            lane_at_boundary   <= 2'b00;
                        end
                        else begin
                            align_mismatch_cnt <= align_mismatch_cnt + 1'b1;
                        end
                    end
                    else if (aligned_rd_en && (&lane_is_align)) begin
                        align_mismatch_cnt <= 4'd0;
                    end
                end

                default: begin
                    dsk_state           <= ST_DSK_INIT;
                    o_lane_aligned      <= 1'b0;
                    align_mismatch_cnt  <= 4'd0;
                    lane_seen_align     <= 2'b00;
                    lane_at_boundary    <= 2'b00;
                end
            endcase
        end
    end

    // Deskew Read Logic
    // Advance each pointer through the complete ALIGN run, then hold the first
    // post-ALIGN word. Once both lanes reach that boundary, read in lockstep.
    assign aligned_rd_en = 
        (dsk_state == ST_DSK_ALIGNED) && 
        !(|fifo_empty) &&
        !rx_logic_reset;
    
    for (genvar lane = 0; lane < 2; lane++) begin : gen_deskew_read
        assign fifo_rd_en[lane]            = 
            ((dsk_state == ST_DSK_WAIT_ALIGN) &&
             !fifo_empty[lane] &&
             !lane_at_boundary[lane] &&
             ((!lane_seen_align[lane] && !lane_is_align[lane]) ||
              ( lane_seen_align[lane] &&  lane_is_align[lane]))) ||
            aligned_rd_en;
        assign aligned_data[lane*32 +: 32] = fifo_dout[lane][31:0];
        assign aligned_ctrl[lane*4  +: 4 ] = fifo_dout[lane][35:32];
    end

    // --------------------------------------------------------------------
    //[4] Descrambler
    // --------------------------------------------------------------------
    // Descrambler is cleared when SOF is detected in the aligned data
    assign clear_scrambler = (aligned_data == {2{32'h1C1C1C1C}}) && (aligned_ctrl == {2{4'hF}});

    for (genvar lane = 0; lane < 2; lane++) begin : gen_descrambler
        aurora_8b10b_SCRAMBLER_TOP descrambler_lane (
            .DATA          (aligned_data[lane*32 +: 32] ),
            .CHAR_IS_K     (aligned_ctrl[lane*4  +: 4 ] ),
            .CLEAR         (clear_scrambler             ),
            .RESET         (rx_logic_reset              ),
            .USER_CLK      (rx_core_clk                 ),
            .DATA_OUT      (desc_data[lane*32 +: 32]    ),
            .CHAR_IS_K_OUT (desc_ctrl[lane*4  +: 4 ]    )
        );
    end

    // --------------------------------------------------------------------
    // Framer & Delay Line (Look-ahead architecture)
    // --------------------------------------------------------------------
    assign is_sof_raw = (desc_data == {2{32'h1C1C1C1C}}) && (desc_ctrl == {2{4'hF}});
    assign is_eof_raw = (desc_data == {2{32'hFDFDFDFD}}) && (desc_ctrl == {2{4'hF}});

    always_ff @(posedge rx_core_clk) begin
        if (rx_logic_reset) begin
            desc_valid <= 1'b0;
            valid_d0 <= 1'b0;
            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;
        end
        else begin
            desc_valid <= aligned_rd_en;
            valid_d0 <= desc_valid;
            valid_d1 <= valid_d0;
            valid_d2 <= valid_d1;
        end
    end

    always_ff @(posedge rx_core_clk) begin
        if (rx_logic_reset) 
            in_frame <= 1'b0;
        else if (desc_valid) begin
            if (is_sof_raw)
                in_frame <= 1'b1;
            else if (is_eof_raw)
                in_frame <= 1'b0;
        end
    end

    always_ff @(posedge rx_core_clk) begin
        if (desc_valid) begin
            rx_data_d0  <= desc_data;
            rx_ctrl_d0  <= desc_ctrl;
            is_sof_d0   <= is_sof_raw;
            is_eof_d0   <= is_eof_raw;
            in_frame_d0 <= in_frame;
        end

        if (valid_d0) begin
            rx_data_d1  <= rx_data_d0;
            rx_ctrl_d1  <= rx_ctrl_d0;
            is_sof_d1   <= is_sof_d0;
            is_eof_d1   <= is_eof_d0;
            in_frame_d1 <= in_frame_d0;
        end

        if (valid_d1) begin
            rx_data_d2  <= rx_data_d1;
            rx_ctrl_d2  <= rx_ctrl_d1;
            is_sof_d2   <= is_sof_d1;
            in_frame_d2 <= in_frame_d1;
        end
    end

    // --------------------------------------------------------------------
    // RX frame validation and atomic commit
    // --------------------------------------------------------------------
    // If d0 contains EOF, d2 contains the last payload beat.  The following
    // cycle places the received CRC in d2 while EOF is in d1.
    assign axi_tlast_d2 = valid_d2 && is_eof_d0;
    assign frame_sof_event = valid_d2 && is_sof_d2;
    assign frame_end_event = valid_d2 && is_eof_d1;
    assign frame_crc_bad   = frame_end_event && (crc_result != rx_data_d2);

    // A payload beat is inside a frame, contains no K characters, and is not
    // the CRC word immediately preceding EOF.
    assign payload_valid_d2 =
        valid_d2 &&
        in_frame_d2 &&
        (rx_ctrl_d2 == 8'd0) &&
        !is_eof_d1;

    // Any K character inside a live frame other than the framing symbols is
    // a malformed-frame indication.  Idle K characters outside frames are
    // intentionally ignored.
    assign illegal_control_event =
        valid_d2 &&
        rx_frame_active &&
        (rx_ctrl_d2 != 8'd0) &&
        !is_sof_d2;

    // Stop the current frame before FIFO full.  RX_PROG_FULL_THRESH leaves
    // headroom for already-pipelined writes and descriptor processing.
    assign write_to_axi =
        payload_valid_d2 &&
        rx_frame_active &&
        !rx_overflow_drop &&
        !rx_frame_format_bad &&
        !rx_fifo_prog_full &&
        !rx_fifo_full;

    assign frame_count_after_write =
        frame_stored_beats + (write_to_axi ? 1'b1 : 1'b0);

    // A descriptor is emitted only when the outcome of the frame is known.
    // Data ahead of a descriptor is therefore never visible at the AXI port.
    always_comb begin
        frame_desc_wr_en      = 1'b0;
        frame_desc_din        = '0;
        frame_drop_decision   = 1'b0;

        if (frame_end_event) begin
            if (rx_frame_active) begin
                frame_drop_decision =
                    rx_overflow_drop ||
                    rx_frame_format_bad ||
                    illegal_control_event ||
                    frame_crc_bad ||
                    (frame_count_after_write == 0);

                if (frame_count_after_write != 0) begin
                    frame_desc_wr_en = 1'b1;
                    frame_desc_din = {
                        frame_drop_decision,
                        frame_count_after_write
                    };
                end
            end
            else begin
                // EOF outside a frame is a format error with no buffered data.
                frame_drop_decision = 1'b1;
            end
        end
        else if (frame_sof_event && rx_frame_active) begin
            // A new SOF aborts a frame that never reached EOF.
            frame_drop_decision = 1'b1;
            if (frame_count_after_write != 0) begin
                frame_desc_wr_en = 1'b1;
                frame_desc_din = {
                    1'b1,
                    frame_count_after_write
                };
            end
        end
    end

    always_ff @(posedge rx_core_clk) begin
        if (rx_logic_reset) begin
            rx_frame_active     <= 1'b0;
            rx_frame_format_bad <= 1'b0;
            rx_overflow_drop    <= 1'b0;
            frame_stored_beats  <= '0;
            o_rx_frame_drop     <= 1'b0;
        end
        else begin
            o_rx_frame_drop <= frame_drop_decision;

            // EOF finalizes the old frame; a simultaneous SOF starts the next
            // frame without an idle cycle.
            if (frame_end_event) begin
                rx_frame_active     <= frame_sof_event;
                rx_frame_format_bad <= 1'b0;
                rx_overflow_drop    <= frame_sof_event && rx_fifo_prog_full;
                frame_stored_beats  <= '0;
            end
            else if (frame_sof_event) begin
                rx_frame_active     <= 1'b1;
                rx_frame_format_bad <= 1'b0;
                rx_overflow_drop    <= rx_fifo_prog_full;
                frame_stored_beats  <= '0;
            end
            else begin
                if (write_to_axi)
                    frame_stored_beats <= frame_stored_beats + 1'b1;
                if (rx_frame_active && illegal_control_event)
                    rx_frame_format_bad <= 1'b1;
                if (rx_frame_active && (rx_fifo_prog_full || rx_fifo_full))
                    rx_overflow_drop <= 1'b1;
            end

            if (frame_desc_wr_en && frame_desc_full)
                $fatal(1, "GI2AXI frame descriptor FIFO overflow");
        end
    end

    // CRC status remains asserted until the next SOF.  Bad CRC frames are
    // represented by DROP descriptors and never become visible on AXI.
    always_ff @(posedge rx_core_clk) begin
        if (rx_logic_reset)
            o_rx_crc_error <= 1'b0;
        else if (frame_sof_event)
            o_rx_crc_error <= 1'b0;
        else if (frame_end_event && rx_frame_active)
            o_rx_crc_error <= frame_crc_bad;
    end

    // CRC Computation Engine
    assign crc_en    = payload_valid_d2;
    assign crc_clear = valid_d0 && is_sof_d0;

    for (genvar i = 0; i < 4; i++) begin : gen_crc_data
        assign crc_in_bus[i]          = rx_data_d2[i*16 +: 16];
        assign crc_result[i*16 +: 16] = crc_out_bus[i];
    end

    for (genvar i = 0; i < 4; i++) begin : gen_rx_crc
        CRC_16 rx_crc_inst (
            .i_clk       (rx_core_clk     ),
            .i_rst       (rx_logic_reset  ),
            .i_crc_clear (crc_clear       ),
            .i_crc_en    (crc_en          ),
            .i_data      (crc_in_bus[i]   ),
            .o_crc       (crc_out_bus[i]  )
        );
    end

    // --------------------------------------------------------------------
    // Payload FIFO and frame descriptor FIFO
    // --------------------------------------------------------------------
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE   ("block"             ),
        .FIFO_WRITE_DEPTH   (RX_FIFO_DEPTH        ),
        .READ_MODE          ("fwft"               ),
        .FIFO_READ_LATENCY  (0                    ),
        .WRITE_DATA_WIDTH   (65                   ),
        .READ_DATA_WIDTH    (65                   ),
        .PROG_FULL_THRESH   (RX_PROG_FULL_THRESH  ),
        .USE_ADV_FEATURES   ("0707"               )
    ) rx_elastic_fifo (
        .wr_clk      (rx_core_clk                 ),
        .rst         (rx_core_reset               ),
        .wr_en       (write_to_axi                ),
        .din         ({axi_tlast_d2, rx_data_d2}  ),
        .full        (rx_fifo_full                ),
        .prog_full   (rx_fifo_prog_full           ),
        .rd_en       (rx_fifo_rd_en               ),
        .dout        (rx_fifo_dout                ),
        .empty       (rx_fifo_empty               ),
        .prog_empty  (                            )
    );

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE   ("distributed"       ),
        .FIFO_WRITE_DEPTH   (RX_FIFO_DEPTH        ),
        .READ_MODE          ("fwft"               ),
        .FIFO_READ_LATENCY  (0                    ),
        .WRITE_DATA_WIDTH   (FRAME_DESC_WIDTH     ),
        .READ_DATA_WIDTH    (FRAME_DESC_WIDTH     ),
        .USE_ADV_FEATURES   ("0000"               )
    ) rx_frame_desc_fifo (
        .wr_clk      (rx_core_clk                 ),
        .rst         (rx_core_reset               ),
        .wr_en       (frame_desc_wr_en && !frame_desc_full),
        .din         (frame_desc_din              ),
        .full        (frame_desc_full             ),
        .prog_full   (                            ),
        .rd_en       (frame_desc_rd_en            ),
        .dout        (frame_desc_dout             ),
        .empty       (frame_desc_empty            ),
        .prog_empty  (                            )
    );

    // --------------------------------------------------------------------
    // Descriptor-driven AXI output / internal frame discard
    // --------------------------------------------------------------------
    assign frame_desc_rd_en =
        (output_state == ST_OUT_IDLE) &&
        !frame_desc_empty &&
        !rx_core_reset;

    assign m_axi_rx_tvalid =
        (output_state == ST_OUT_COMMIT) &&
        !rx_fifo_empty &&
        !rx_core_reset;
    assign m_axi_rx_tdata  = rx_fifo_dout[63:0];
    assign m_axi_rx_tlast  = rx_fifo_dout[64];
    assign m_axi_rx_tkeep  = 8'hFF;

    assign rx_fifo_rd_en =
        ((output_state == ST_OUT_COMMIT) && m_axi_rx_tvalid && m_axi_rx_tready) ||
        ((output_state == ST_OUT_DROP) && !rx_fifo_empty && !rx_core_reset);

    always_ff @(posedge rx_core_clk) begin
        if (rx_core_reset) begin
            output_state           <= ST_OUT_IDLE;
            output_beats_remaining <= '0;
        end
        else begin
            case (output_state)
                ST_OUT_IDLE: begin
                    if (!frame_desc_empty) begin
                        if (frame_desc_dout[FRAME_BEAT_COUNT_WIDTH-1:0] == 0)
                            $fatal(1, "GI2AXI encountered a zero-length frame descriptor");
                        output_beats_remaining <=
                            frame_desc_dout[FRAME_BEAT_COUNT_WIDTH-1:0];
                        if (frame_desc_dout[FRAME_DESC_WIDTH-1])
                            output_state <= ST_OUT_DROP;
                        else
                            output_state <= ST_OUT_COMMIT;
                    end
                end

                ST_OUT_COMMIT: begin
                    if (rx_fifo_empty && (output_beats_remaining != 0))
                        $fatal(1, "GI2AXI payload FIFO underflow while committing a frame");
                    if (m_axi_rx_tvalid && m_axi_rx_tready) begin
                        if (output_beats_remaining == 1) begin
                            if (rx_fifo_dout[64] !== 1'b1)
                                $fatal(1, "GI2AXI committed frame ended without TLAST");
                            output_beats_remaining <= '0;
                            output_state <= ST_OUT_IDLE;
                        end
                        else begin
                            if (rx_fifo_dout[64] === 1'b1)
                                $fatal(1, "GI2AXI committed frame asserted TLAST early");
                            output_beats_remaining <= output_beats_remaining - 1'b1;
                        end
                    end
                end

                ST_OUT_DROP: begin
                    if (m_axi_rx_tvalid !== 1'b0)
                        $fatal(1, "GI2AXI asserted AXI TVALID while discarding a frame");
                    if (rx_fifo_empty && (output_beats_remaining != 0))
                        $fatal(1, "GI2AXI payload FIFO underflow while discarding a frame");
                    if (!rx_fifo_empty) begin
                        if (output_beats_remaining == 1) begin
                            output_beats_remaining <= '0;
                            output_state <= ST_OUT_IDLE;
                        end
                        else begin
                            output_beats_remaining <= output_beats_remaining - 1'b1;
                        end
                    end
                end

                default: begin
                    output_state           <= ST_OUT_IDLE;
                    output_beats_remaining <= '0;
                end
            endcase
        end
    end
    


endmodule

