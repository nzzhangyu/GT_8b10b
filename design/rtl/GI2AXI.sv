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
    output logic [63:0]  m_axi_tx_tdata,
    output logic [7:0]   m_axi_tx_tkeep,
    output logic         m_axi_tx_tvalid,
    input  logic         m_axi_tx_tready,
    output logic         m_axi_tx_tlast,
    output logic         m_axi_tx_aresetn,

    // AXI Interface
    input  logic         i_user_axi_clk,        // System AXI clock

    // Status Signals           
    output logic         o_lane_aligned,    // Indicates both lanes are deskewed
    output logic         o_rx_crc_error     // Pulses high if CRC mismatch
    );

    // Reset & System Ready
    (* ASYNC_REG = "TRUE" *) logic [1:0]    gt_reset_rx_done_d1;
    (* ASYNC_REG = "TRUE" *) logic [1:0]    gt_reset_rx_done_d2;
    logic          all_lanes_ready;
    logic          axi_domain_reset;
    logic          rx_logic_reset;

    assign m_axi_tx_aresetn = ~axi_domain_reset;

    // Deskew FIFO Signals
    logic [35:0]   fifo_dout [1:0];
    logic [1:0]    fifo_empty;
    logic [1:0]    fifo_full;
    logic [1:0]    fifo_rd_en;
    logic [1:0]    fifo_wr_en;
    logic [1:0]    fifo_wr_rst_busy;
    logic [1:0]    fifo_rd_rst_busy;
    logic [1:0]    lane_is_align;
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
    logic is_eof_d0;
    logic is_eof_d1;
    logic in_frame_d0;
    logic in_frame_d1;
    logic in_frame_d2;

    // RX Elastic FIFO Signals
    logic          write_to_axi;
    logic          axi_tlast_d2;
    logic          rx_fifo_empty;
    logic          rx_fifo_full;
    logic [64:0]   rx_fifo_dout;
    logic          rx_fifo_prog_full;
    logic          rx_overflow_drop;    // drop current frame  

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
        always_ff @(posedge i_user_axi_clk or posedge i_rx_user_reset[lane])
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
    assign axi_domain_reset = ~all_lanes_ready;
    assign rx_logic_reset   = axi_domain_reset | (|fifo_rd_rst_busy);

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
                .rd_clk      (i_user_axi_clk                          ),
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

    always_ff @(posedge i_user_axi_clk) begin 
        if (rx_logic_reset) begin
            dsk_state           <= ST_DSK_INIT;
            o_lane_aligned      <= 1'b0;
            align_mismatch_cnt  <= 4'd0;
        end
        else begin
            case (dsk_state)
                ST_DSK_INIT: begin
                    o_lane_aligned     <= 1'b0;
                    align_mismatch_cnt <= 4'd0;
                    if (!(|fifo_empty))
                        dsk_state <= ST_DSK_WAIT_ALIGN;
                end

                ST_DSK_WAIT_ALIGN: begin
                    o_lane_aligned     <= 1'b0;
                    align_mismatch_cnt <= 4'd0;
                    // Once BOTH lanes hit the alignment character, lock alignment
                    if (&lane_is_align) begin
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
                end
            endcase
        end
    end

    // Deskew Read Logic
    // Advance independent pointers during WAIT until they both point to ALIGN.
    // Once ALIGNED, lock them together and only read when BOTH have data.
    assign aligned_rd_en = 
        (dsk_state == ST_DSK_ALIGNED) && 
        !(|fifo_empty) &&
        !rx_logic_reset;
    
    for (genvar lane = 0; lane < 2; lane++) begin : gen_deskew_read
        assign fifo_rd_en[lane]            = 
            ((dsk_state == ST_DSK_WAIT_ALIGN) && 
            !fifo_empty[lane] && 
            !lane_is_align[lane]) || 
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
            .USER_CLK      (i_user_axi_clk              ),
            .DATA_OUT      (desc_data[lane*32 +: 32]    ),
            .CHAR_IS_K_OUT (desc_ctrl[lane*4  +: 4 ]    )
        );
    end

    // --------------------------------------------------------------------
    // Framer & Delay Line (Look-ahead architecture)
    // --------------------------------------------------------------------
    assign is_sof_raw = (desc_data == {2{32'h1C1C1C1C}}) && (desc_ctrl == {2{4'hF}});
    assign is_eof_raw = (desc_data == {2{32'hFDFDFDFD}}) && (desc_ctrl == {2{4'hF}});

    always_ff @(posedge i_user_axi_clk) begin
        if (rx_logic_reset) begin
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

    always_ff @(posedge i_user_axi_clk) begin
        if (rx_logic_reset) 
            in_frame <= 1'b0;
        else if (aligned_rd_en) begin
            if (is_sof_raw)
                in_frame <= 1'b1;
            else if (is_eof_raw)
                in_frame <= 1'b0;
        end
    end

    always_ff @(posedge i_user_axi_clk) begin
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
    assign axi_tlast_d2 = valid_d2 && is_eof_d0;

    always_ff @(posedge i_user_axi_clk) begin
        if (rx_logic_reset) 
            rx_overflow_drop <= 1'b0;
        else if (rx_fifo_prog_full)
            rx_overflow_drop <= 1'b1;
        else if (valid_d0 && is_sof_raw)
            rx_overflow_drop <= 1'b0; 
    end

    // A byte is valid Payload if it's inside a frame, has no K-chars, 
    // and is NOT the CRC. If d1 is EOF, it guarantees d2 is the CRC.
    assign write_to_axi = 
        valid_d2 && 
        in_frame_d2 && 
        (rx_ctrl_d2 == 8'd0) && 
        !is_eof_d1 && 
        !rx_overflow_drop &&
        !rx_fifo_full;

    // CRC Error Detection
    always_ff @(posedge i_user_axi_clk) begin
        if (rx_logic_reset) 
            o_rx_crc_error <= 1'b0;
        else if (valid_d0 && is_sof_raw) 
            o_rx_crc_error <= 1'b0; // Clear error on new frame
        else if (valid_d2 && is_eof_d1) 
            // When d1 is EOF, d2 contains the CRC received from TX.
            // crc_result contains the CRC just computed up to d3 payload.
            o_rx_crc_error <= (crc_result != rx_data_d2); 
    end

    // CRC Computation Engine
    assign crc_en    = write_to_axi;
    assign crc_clear = valid_d0 && is_sof_raw;

    for (genvar i = 0; i < 4; i++) begin : gen_crc_data
        assign crc_in_bus[i]          = rx_data_d2[i*16 +: 16];
        assign crc_result[i*16 +: 16] = crc_out_bus[i];
    end

    for (genvar i = 0; i < 4; i++) begin : gen_rx_crc
        CRC_16 rx_crc_inst (
            .i_clk       (i_user_axi_clk  ), 
            .i_rst       (rx_logic_reset  ), 
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
        .FIFO_MEMORY_TYPE   ("block"), 
        .FIFO_WRITE_DEPTH   (4096   ),     
        .READ_MODE          ("fwft" ),         
        .FIFO_READ_LATENCY  (0      ),
        .WRITE_DATA_WIDTH   (65     ),
        .READ_DATA_WIDTH    (65     ),
        .USE_ADV_FEATURES   ("0707" )   
    ) rx_elastic_fifo (
        .wr_clk      (i_user_axi_clk                        ),
        .rst         (axi_domain_reset                      ),
        .wr_en       (write_to_axi                          ),
        .din         ({axi_tlast_d2, rx_data_d2}            ),
        .full        (rx_fifo_full                          ), 
        .prog_full   (rx_fifo_prog_full                     ),           
            
        .rd_en       (m_axi_tx_tvalid && m_axi_tx_tready    ),
        .dout        (rx_fifo_dout                          ),
        .empty       (rx_fifo_empty                         ),
        .prog_empty  (                                      )
    );

    // Final AXI-Stream Mapping
    assign m_axi_tx_tvalid = !rx_fifo_empty && !axi_domain_reset;
    assign m_axi_tx_tdata  = rx_fifo_dout[63:0];
    assign m_axi_tx_tlast  = rx_fifo_dout[64];
    assign m_axi_tx_tkeep  = 8'hFF;
    


endmodule
