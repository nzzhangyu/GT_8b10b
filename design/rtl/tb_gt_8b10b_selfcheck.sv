`timescale 1ns / 1ps

module tb_gt_8b10b_selfcheck;

    localparam int SCOREBOARD_DEPTH = 2048;
    localparam int ALIGN_TIMEOUT     = 10000;
    localparam int DRAIN_TIMEOUT     = 20000;
    localparam int CRC_TIMEOUT       = 2000;

    logic        sys_clk;
    logic        sys_reset;

    logic [63:0] s_axi_tdata;
    logic [7:0]  s_axi_tkeep;
    logic        s_axi_tvalid;
    logic        s_axi_tready;
    logic        s_axi_tlast;

    logic [63:0] m_axi_tdata;
    logic [7:0]  m_axi_tkeep;
    logic        m_axi_tvalid;
    logic        m_axi_tready;
    logic        m_axi_tlast;

    logic [11:0] inj_skew_lane;
    logic [1:0]  inj_bit_flip;
    logic        inj_link_drop;

    logic        lane_aligned;
    logic        rx_crc_error;

    logic [63:0] expected_data [0:SCOREBOARD_DEPTH-1];
    logic [7:0]  expected_keep [0:SCOREBOARD_DEPTH-1];
    logic        expected_last [0:SCOREBOARD_DEPTH-1];
    integer      scoreboard_wr_idx;
    integer      scoreboard_rd_idx;

    integer      sent_packets;
    integer      sent_beats;
    integer      checked_packets;
    integer      checked_beats;
    integer      error_rx_beats;
    integer      error_rx_packets;

    integer      packet_lengths [0:9];
    logic [31:0] source_lfsr;
    logic [31:0] ready_lfsr;
    logic        random_ready_enable;
    logic        compare_enable;
    logic        normal_phase;

    logic        stalled_d;
    logic [63:0] stalled_data_d;
    logic [7:0]  stalled_keep_d;
    logic        stalled_last_d;

    function automatic logic [31:0] lfsr_next(input logic [31:0] value);
        lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    tb_gt_8b10b_top dut (
        .sys_clk        (sys_clk        ),
        .sys_reset      (sys_reset      ),
        .s_axi_tdata    (s_axi_tdata    ),
        .s_axi_tkeep    (s_axi_tkeep    ),
        .s_axi_tvalid   (s_axi_tvalid   ),
        .s_axi_tready   (s_axi_tready   ),
        .s_axi_tlast    (s_axi_tlast    ),
        .m_axi_tdata    (m_axi_tdata    ),
        .m_axi_tkeep    (m_axi_tkeep    ),
        .m_axi_tvalid   (m_axi_tvalid   ),
        .m_axi_tready   (m_axi_tready   ),
        .m_axi_tlast    (m_axi_tlast    ),
        .inj_skew_lane  (inj_skew_lane  ),
        .inj_bit_flip   (inj_bit_flip   ),
        .inj_link_drop  (inj_link_drop  ),
        .lane_aligned   (lane_aligned   ),
        .rx_crc_error   (rx_crc_error   )
    );

    initial begin
        sys_clk = 1'b0;
        forever #3.2 sys_clk = ~sys_clk;
    end

    task automatic apply_reset;
        begin
            sys_reset           = 1'b1;
            s_axi_tdata         = 64'd0;
            s_axi_tkeep         = 8'hFF;
            s_axi_tvalid        = 1'b0;
            s_axi_tlast         = 1'b0;
            inj_skew_lane       = 12'd0;
            inj_bit_flip        = 2'b00;
            inj_link_drop       = 1'b0;
            random_ready_enable = 1'b0;
            compare_enable      = 1'b1;
            normal_phase        = 1'b0;

            repeat (20) @(posedge sys_clk);
            @(negedge sys_clk);
            sys_reset = 1'b0;
            repeat (50) @(posedge sys_clk);
        end
    endtask

    task automatic wait_lane_aligned(input integer max_cycles);
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge sys_clk);
                if (lane_aligned === 1'b1) begin
                    $display("[%0t] Lane alignment completed after %0d cycles", $time, cycle + 1);
                    return;
                end
            end
            $fatal(1, "Lane alignment timed out after %0d cycles", max_cycles);
        end
    endtask

    task automatic push_expected(
        input logic [63:0] data,
        input logic [7:0]  keep,
        input logic        last
    );
        begin
            if (scoreboard_wr_idx >= SCOREBOARD_DEPTH)
                $fatal(1, "Scoreboard overflow at beat %0d", scoreboard_wr_idx);

            expected_data[scoreboard_wr_idx] = data;
            expected_keep[scoreboard_wr_idx] = keep;
            expected_last[scoreboard_wr_idx] = last;
            scoreboard_wr_idx = scoreboard_wr_idx + 1;
        end
    endtask

    task automatic send_axi_packet(
        input integer packet_id,
        input integer beat_count,
        input logic   check_data
    );
        integer beat;
        logic [63:0] beat_data;
        begin
            for (beat = 0; beat < beat_count; beat = beat + 1) begin
                source_lfsr = lfsr_next(source_lfsr);
                beat_data[31:0] = source_lfsr ^ packet_id;
                source_lfsr = lfsr_next(source_lfsr);
                beat_data[63:32] = source_lfsr ^ beat;

                @(negedge sys_clk);
                s_axi_tdata  = beat_data;
                s_axi_tkeep  = 8'hFF;
                s_axi_tlast  = (beat == beat_count - 1);
                s_axi_tvalid = 1'b1;

                do begin
                    @(posedge sys_clk);
                end while (s_axi_tready !== 1'b1);

                if (check_data)
                    push_expected(beat_data, 8'hFF, beat == beat_count - 1);
                sent_beats = sent_beats + 1;
            end

            @(negedge sys_clk);
            s_axi_tvalid = 1'b0;
            s_axi_tlast  = 1'b0;
            s_axi_tdata  = 64'd0;
            sent_packets = sent_packets + 1;
        end
    endtask

    task automatic wait_scoreboard_empty(input integer max_cycles);
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge sys_clk);
                if (scoreboard_rd_idx == scoreboard_wr_idx)
                    return;
            end
            $fatal(1, "Scoreboard did not drain: expected=%0d received=%0d",
                   scoreboard_wr_idx, scoreboard_rd_idx);
        end
    endtask

    task automatic inject_payload_error;
        integer cycle;
        logic   found_sof;
        logic   found_payload;
        begin
            found_sof = 1'b0;
            for (cycle = 0; cycle < ALIGN_TIMEOUT; cycle = cycle + 1) begin
                @(posedge sys_clk);
                if ((dut.tx_ctrl_packed === 8'hFF) &&
                    (dut.tx_data_packed === 64'h1C1C1C1C1C1C1C1C)) begin
                    found_sof = 1'b1;
                    break;
                end
            end
            if (!found_sof)
                $fatal(1, "Could not locate SOF for CRC error injection");

            found_payload = 1'b0;
            for (cycle = 0; cycle < 128; cycle = cycle + 1) begin
                @(posedge sys_clk);
                if (dut.tx_ctrl_packed === 8'h00) begin
                    found_payload = 1'b1;
                    break;
                end
            end
            if (!found_payload)
                $fatal(1, "Could not locate payload for CRC error injection");

            @(negedge sys_clk);
            inj_bit_flip = 2'b01;
            @(negedge sys_clk);
            inj_bit_flip = 2'b00;
            $display("[%0t] Injected one-cycle lane-0 data error", $time);

            for (cycle = 0; cycle < CRC_TIMEOUT; cycle = cycle + 1) begin
                @(posedge sys_clk);
                if (rx_crc_error === 1'b1) begin
                    $display("[%0t] CRC error detected", $time);
                    return;
                end
            end
            $fatal(1, "CRC error was not detected within %0d cycles", CRC_TIMEOUT);
        end
    endtask

    // Deterministic receive backpressure.
    always @(posedge sys_clk) begin
        if (sys_reset) begin
            ready_lfsr  <= 32'h1BAD_F00D;
            m_axi_tready <= 1'b0;
        end
        else if (random_ready_enable) begin
            ready_lfsr  <= lfsr_next(ready_lfsr);
            m_axi_tready <= ready_lfsr[0] | ready_lfsr[2] | ready_lfsr[5];
        end
        else begin
            m_axi_tready <= 1'b1;
        end
    end

    // Beat-level scoreboard and error-packet drain monitor.
    always @(posedge sys_clk) begin
        if (sys_reset) begin
            scoreboard_rd_idx <= 0;
            checked_packets   <= 0;
            checked_beats     <= 0;
            error_rx_beats    <= 0;
            error_rx_packets  <= 0;
        end
        else if (m_axi_tvalid && m_axi_tready) begin
            if (compare_enable) begin
                if (scoreboard_rd_idx >= scoreboard_wr_idx)
                    $fatal(1, "Unexpected AXI output beat (scoreboard underflow)");
                if (m_axi_tdata !== expected_data[scoreboard_rd_idx])
                    $fatal(1, "AXI data mismatch at beat %0d: expected=%016h actual=%016h",
                           scoreboard_rd_idx, expected_data[scoreboard_rd_idx], m_axi_tdata);
                if (m_axi_tkeep !== expected_keep[scoreboard_rd_idx])
                    $fatal(1, "AXI TKEEP mismatch at beat %0d", scoreboard_rd_idx);
                if (m_axi_tlast !== expected_last[scoreboard_rd_idx])
                    $fatal(1, "AXI TLAST mismatch at beat %0d", scoreboard_rd_idx);

                if (m_axi_tlast)
                    checked_packets <= checked_packets + 1;
                checked_beats <= checked_beats + 1;
                scoreboard_rd_idx <= scoreboard_rd_idx + 1;
            end
            else begin
                error_rx_beats <= error_rx_beats + 1;
                if (m_axi_tlast)
                    error_rx_packets <= error_rx_packets + 1;
            end
        end
    end

    // AXI output must remain stable while back-pressured and contain no X/Z
    // values on valid transfers.
    always @(posedge sys_clk) begin
        if (sys_reset) begin
            stalled_d      <= 1'b0;
            stalled_data_d <= 64'd0;
            stalled_keep_d <= 8'd0;
            stalled_last_d <= 1'b0;
        end
        else begin
            if (stalled_d) begin
                if ((m_axi_tvalid !== 1'b1) ||
                    (m_axi_tdata !== stalled_data_d) ||
                    (m_axi_tkeep !== stalled_keep_d) ||
                    (m_axi_tlast !== stalled_last_d))
                    $fatal(1, "AXI output changed while stalled");
            end

            if (m_axi_tvalid && $isunknown({m_axi_tdata, m_axi_tkeep, m_axi_tlast}))
                $fatal(1, "AXI output contains X/Z while TVALID is asserted");

            stalled_d      <= m_axi_tvalid && !m_axi_tready;
            stalled_data_d <= m_axi_tdata;
            stalled_keep_d <= m_axi_tkeep;
            stalled_last_d <= m_axi_tlast;
        end
    end

    // A CRC error during normal traffic is always a failure.
    always @(posedge sys_clk) begin
        if (!sys_reset && normal_phase && (rx_crc_error === 1'b1))
            $fatal(1, "Unexpected CRC error during normal traffic");
    end

    initial begin : test_sequence
        integer packet;
        integer cycle;

        scoreboard_wr_idx = 0;
        scoreboard_rd_idx = 0;
        sent_packets      = 0;
        sent_beats        = 0;
        checked_packets   = 0;
        checked_beats     = 0;
        error_rx_beats    = 0;
        error_rx_packets  = 0;
        source_lfsr       = 32'hC001_CAFE;
        ready_lfsr        = 32'h1BAD_F00D;

        packet_lengths[0] = 1;
        packet_lengths[1] = 2;
        packet_lengths[2] = 3;
        packet_lengths[3] = 4;
        packet_lengths[4] = 8;
        packet_lengths[5] = 16;
        packet_lengths[6] = 24;
        packet_lengths[7] = 32;
        packet_lengths[8] = 48;
        packet_lengths[9] = 64;

        apply_reset();

        inj_skew_lane[5:0]  = 6'd5;
        inj_skew_lane[11:6] = 6'd28;
        wait_lane_aligned(ALIGN_TIMEOUT);

        $display("[%0t] Starting normal loopback regression", $time);
        random_ready_enable = 1'b1;
        normal_phase        = 1'b1;

        for (packet = 0; packet < 10; packet = packet + 1)
            send_axi_packet(packet, packet_lengths[packet], 1'b1);

        wait_scoreboard_empty(DRAIN_TIMEOUT);
        repeat (16) @(posedge sys_clk);
        if (rx_crc_error !== 1'b0)
            $fatal(1, "CRC check failed after normal traffic drained");
        normal_phase = 1'b0;

        if (checked_packets != 10)
            $fatal(1, "Expected 10 checked packets, received %0d", checked_packets);

        $display("[%0t] Starting CRC error-injection scenario", $time);
        compare_enable      = 1'b0;
        random_ready_enable = 1'b0;

        fork
            send_axi_packet(100, 32, 1'b0);
            inject_payload_error();
        join

        for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
            @(posedge sys_clk);
            if ((error_rx_beats == 32) && (error_rx_packets == 1))
                break;
        end
        if ((error_rx_beats != 32) || (error_rx_packets != 1))
            $fatal(1, "Error packet did not drain correctly: beats=%0d packets=%0d",
                   error_rx_beats, error_rx_packets);

        $display("============================================================");
        $display("TEST PASS");
        $display("Normal packets checked : %0d", checked_packets);
        $display("Normal beats checked   : %0d", checked_beats);
        $display("Total packets sent     : %0d", sent_packets);
        $display("Total beats sent       : %0d", sent_beats);
        $display("============================================================");
        $finish;
    end

    initial begin : global_timeout
        repeat (200000) @(posedge sys_clk);
        $fatal(1, "Global simulation timeout");
    end

endmodule

