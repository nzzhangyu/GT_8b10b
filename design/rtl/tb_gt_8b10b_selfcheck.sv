`timescale 1ns / 1ps

module tb_gt_8b10b_selfcheck #(
    parameter integer  CASE_ID          = 0,            // 矩阵用例编号
    parameter bit      MATRIX_MODE      = 1'b0,         // 精简矩阵回归开关
    parameter realtime RX_PPM           = 0.0,          // RX相对TX频偏
    parameter realtime TX1_PHASE_NS     = 0.0,          // TX Lane 1相位
    parameter realtime RX0_PHASE_NS     = 0.0,          // RX Lane 0相位
    parameter realtime RX1_PHASE_NS     = 0.0,          // RX Lane 1相位
    parameter int      LANE0_DELAY      = 5,            // Dummy lane 0初始队列余量
    parameter int      LANE1_DELAY      = 28,           // Dummy lane 1初始队列余量
    parameter bit      LONG_RUN          = 1'b0,         // 长稳测试开关
    parameter realtime LONG_RUN_TIME_NS = 10_000_000.0, // 长稳测试时长
    parameter realtime MATRIX_RUN_TIME_NS = 50_000.0,   // 每组持续流量时长
    parameter bit      RUN_MIDFRAME_DIAGNOSTIC = 1'b1   // 包中溢出诊断
)(
    output logic test_done,
    output logic test_pass
);

    timeunit 1ns;
    timeprecision 1fs;

    localparam int ALIGN_TIMEOUT     = 10000; // 对齐超时
    localparam int DRAIN_TIMEOUT     = 20000; // 排空超时
    localparam int CRC_TIMEOUT       = 2000;  // CRC检测超时
    localparam realtime LINK_NOMINAL_PERIOD_NS = 1000.0 / 257.8125; // 257.8125 MHz
    localparam realtime TX_PERIOD_NS = LINK_NOMINAL_PERIOD_NS;
    localparam realtime RX_PERIOD_NS =
        LINK_NOMINAL_PERIOD_NS / (1.0 + RX_PPM * 1.0e-6);

    logic [1:0]  tx_usrclk;    // Lane发送时钟
    logic [1:0]  rx_usrclk;    // Lane接收时钟
    wire         rx_core_clk = rx_usrclk[0]; // RX处理时钟
    logic        sys_reset;    // 系统复位

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

    logic [11:0] inj_skew_lane; // Lane延迟注入
    logic [1:0]  inj_bit_flip;  // Lane位翻转注入
    logic        inj_link_drop; // 断链注入

    logic        lane_aligned; // Lane对齐状态
    logic        rx_crc_error; // 接收CRC错误
    logic        rx_frame_drop; // 接收整帧丢弃脉冲

    logic [72:0] expected_queue[$]; // 期望数据队列
    logic [72:0] expected_actual;   // 当前期望数据

    integer      sent_packets;     // 已发送包数
    integer      sent_beats;       // 已发送beat数
    integer      checked_packets;  // 已检查包数
    integer      checked_beats;    // 已检查beat数
    integer      error_rx_beats;   // 错误场景beat数
    integer      error_rx_packets; // 错误场景包数
    integer      dropped_frames;   // 被原子丢弃的帧数

    integer      packet_lengths [0:9]; // 测试包长表
    logic [31:0] source_lfsr;           // 数据随机源
    logic [31:0] ready_lfsr;            // 背压随机源
    logic        random_ready_enable;   // 随机背压使能
    logic        force_rx_stall;        // 强制接收暂停
    logic        compare_enable;        // Scoreboard使能
    logic        normal_phase;          // 正常流量阶段
    logic        overflow_phase;        // 溢出测试阶段
    logic        long_run_done;         // 长稳结束标志

    logic        stalled_d;      // 上周期背压状态
    logic [63:0] stalled_data_d; // 背压数据快照
    logic [7:0]  stalled_keep_d; // 背压TKEEP快照
    logic        stalled_last_d; // 背压TLAST快照

    // LFSR步进
    function automatic logic [31:0] lfsr_next(input logic [31:0] value);
        lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    // DUT封装实例
    tb_gt_8b10b_top dut (
        .tx_usrclk      (tx_usrclk      ),
        .rx_usrclk      (rx_usrclk      ),
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
        .rx_crc_error   (rx_crc_error   ),
        .rx_frame_drop  (rx_frame_drop  )
    );

    initial begin
        tx_usrclk[0] = 1'b0;
        forever #(TX_PERIOD_NS / 2.0) tx_usrclk[0] = ~tx_usrclk[0];
    end

    initial begin
        tx_usrclk[1] = 1'b0;
        #(TX1_PHASE_NS);
        forever #(TX_PERIOD_NS / 2.0) tx_usrclk[1] = ~tx_usrclk[1];
    end

    initial begin
        rx_usrclk[0] = 1'b0;
        #(RX0_PHASE_NS);
        forever #(RX_PERIOD_NS / 2.0) rx_usrclk[0] = ~rx_usrclk[0];
    end

    initial begin
        rx_usrclk[1] = 1'b0;
        #(RX1_PHASE_NS);
        forever #(RX_PERIOD_NS / 2.0) rx_usrclk[1] = ~rx_usrclk[1];
    end

    // 复位激励
    task automatic apply_reset;
        begin
            sys_reset           = 1'b1;
            s_axi_tdata         = 64'd0;
            s_axi_tkeep         = 8'hFF;
            s_axi_tvalid        = 1'b0;
            s_axi_tlast         = 1'b0;
            inj_skew_lane[5:0]  = LANE0_DELAY;
            inj_skew_lane[11:6] = LANE1_DELAY;
            inj_bit_flip        = 2'b00;
            inj_link_drop       = 1'b0;
            random_ready_enable = 1'b0;
            force_rx_stall      = 1'b0;
            compare_enable      = 1'b1;
            normal_phase        = 1'b0;
            overflow_phase      = 1'b0;

            repeat (20) @(posedge rx_core_clk);
            @(negedge rx_core_clk);
            sys_reset = 1'b0;
            repeat (50) @(posedge rx_core_clk);
        end
    endtask

    // 等待Lane对齐
    task automatic wait_lane_aligned(input integer max_cycles);
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (lane_aligned === 1'b1) begin
                    $display("[CASE %0d][%0t] Lane alignment completed after %0d cycles",
                             CASE_ID, $time, cycle + 1);
                    return;
                end
            end
            $fatal(1, "[CASE %0d] Lane alignment timed out after %0d cycles",
                   CASE_ID, max_cycles);
        end
    endtask

    // 压入期望数据
    task automatic push_expected(
        input logic [63:0] data,
        input logic [7:0]  keep,
        input logic        last
    );
        begin
            expected_queue.push_back({last, keep, data});
        end
    endtask

    // 发送AXI数据包
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

                @(negedge tx_usrclk[0]);
                s_axi_tdata  = beat_data;
                s_axi_tkeep  = 8'hFF;
                s_axi_tlast  = (beat == beat_count - 1);
                s_axi_tvalid = 1'b1;

                do begin
                    @(posedge tx_usrclk[0]);
                end while (s_axi_tready !== 1'b1);

                if (check_data)
                    push_expected(beat_data, 8'hFF, beat == beat_count - 1);
                sent_beats = sent_beats + 1;
            end

            @(negedge tx_usrclk[0]);
            s_axi_tvalid = 1'b0;
            s_axi_tlast  = 1'b0;
            s_axi_tdata  = 64'd0;
            sent_packets = sent_packets + 1;
        end
    endtask

    // 等待Scoreboard排空
    task automatic wait_scoreboard_empty(input integer max_cycles);
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (expected_queue.size() == 0)
                    return;
            end
            $fatal(1, "[CASE %0d] Scoreboard did not drain: queued=%0d checked=%0d",
                   CASE_ID, expected_queue.size(), checked_beats);
        end
    endtask

    // 等待Lane对齐状态变化
    task automatic wait_lane_aligned_state(
        input logic   expected,
        input integer max_cycles
    );
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (lane_aligned === expected) begin
                    $display("[CASE %0d][%0t] Lane aligned became %0b after %0d cycles",
                             CASE_ID, $time, expected, cycle + 1);
                    return;
                end
            end
            $fatal(1, "[CASE %0d] Lane aligned did not become %0b within %0d cycles",
                   CASE_ID, expected, max_cycles);
        end
    endtask

    // 等待RX AXI复位状态变化
    task automatic wait_rx_axi_resetn(
        input logic   expected,
        input integer max_cycles
    );
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dut.m_axi_aresetn === expected) begin
                    $display("[CASE %0d][%0t] RX AXI aresetn became %0b after %0d cycles",
                             CASE_ID, $time, expected, cycle + 1);
                    return;
                end
            end
            $fatal(1, "[CASE %0d] RX AXI aresetn did not become %0b within %0d cycles",
                   CASE_ID, expected, max_cycles);
        end
    endtask

    // 等待故障流量从TX/RX路径完全排空
    task automatic wait_link_idle(input integer max_cycles);
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if ((dut.tx_inst.link_state  === 3'd0) &&
                    (dut.tx_inst.fifo_empty  === 1'b1) &&
                    (dut.tx_inst.pkt_in_fifo === 16'd0) &&
                    (dut.rx_inst.rx_fifo_empty === 1'b1) &&
                    (dut.rx_inst.frame_desc_empty === 1'b1) &&
                    (dut.rx_inst.output_state === 2'd0) &&
                    (m_axi_tvalid === 1'b0))
                    return;
            end
            $fatal(1, "[CASE %0d] Link datapath did not become idle within %0d cycles",
                   CASE_ID, max_cycles);
        end
    endtask

    task automatic wait_dropped_frames(
        input integer expected_count,
        input integer max_cycles
    );
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dropped_frames >= expected_count)
                    return;
            end
            $fatal(1, "[CASE %0d] Frame-drop count did not reach %0d within %0d cycles",
                   CASE_ID, expected_count, max_cycles);
        end
    endtask

    // Inject one decoded protocol symbol.  Force only literal constants:
    // Vivado does not reliably update a procedural force whose RHS is a task
    // argument.  Drive an explicit idle symbol before release so the forced
    // EOF/SOF cannot remain visible after the task returns.
    task automatic inject_decoded_symbol(
        input logic [63:0] data,
        input logic [7:0]  ctrl
    );
        begin
            @(negedge rx_core_clk);
            if ((data == {2{32'h1C1C1C1C}}) && (ctrl == 8'hFF)) begin
                force dut.rx_inst.desc_data = {2{32'h1C1C1C1C}};
                force dut.rx_inst.desc_ctrl = 8'hFF;
            end
            else if ((data == {2{32'hFDFDFDFD}}) && (ctrl == 8'hFF)) begin
                force dut.rx_inst.desc_data = {2{32'hFDFDFDFD}};
                force dut.rx_inst.desc_ctrl = 8'hFF;
            end
            else if ((data == 64'd0) && (ctrl == 8'h00)) begin
                force dut.rx_inst.desc_data = 64'd0;
                force dut.rx_inst.desc_ctrl = 8'h00;
            end
            else begin
                $fatal(1, "Unsupported decoded-symbol injection data=%016h ctrl=%02h",
                       data, ctrl);
            end

            @(negedge rx_core_clk);
            force dut.rx_inst.desc_data = {2{32'hF7F7F7F7}};
            force dut.rx_inst.desc_ctrl = 8'hFF;
            @(negedge rx_core_clk);
            release dut.rx_inst.desc_data;
            release dut.rx_inst.desc_ctrl;
        end
    endtask

    // Suppress the next EOF at the two protocol decisions it controls:
    // payload TLAST generation and frame finalization.  Force the combinational
    // decisions rather than a pipeline register, whose deferred procedural
    // assignment can reappear when a force is released.
    task automatic suppress_next_eof;
        integer cycle;
        begin
            for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
                @(negedge rx_core_clk);
                if (dut.rx_inst.is_eof_raw === 1'b1) begin
                    force dut.rx_inst.axi_tlast_d2  = 1'b0;
                    force dut.rx_inst.frame_end_event = 1'b0;
                    repeat (4) @(negedge rx_core_clk);
                    release dut.rx_inst.axi_tlast_d2;
                    release dut.rx_inst.frame_end_event;
                    return;
                end
            end
            $fatal(1, "[CASE %0d] Could not locate EOF for suppression", CASE_ID);
        end
    endtask

    // Replace one decoded payload word with a second SOF.
    task automatic inject_repeated_sof;
        integer cycle;
        begin
            for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
                @(negedge rx_core_clk);
                if (dut.rx_inst.payload_valid_d2 === 1'b1) begin
                    force dut.rx_inst.desc_data = {2{32'h1C1C1C1C}};
                    force dut.rx_inst.desc_ctrl = 8'hFF;
                    @(negedge rx_core_clk);
                    release dut.rx_inst.desc_data;
                    release dut.rx_inst.desc_ctrl;
                    return;
                end
            end
            $fatal(1, "[CASE %0d] Could not locate payload for repeated SOF", CASE_ID);
        end
    endtask

    // 在发送端已经进入payload阶段后注入完整GT掉线
    task automatic inject_midpacket_link_drop;
        integer cycle;
        logic   found_payload;
        begin
            found_payload = 1'b0;
            for (cycle = 0; cycle < ALIGN_TIMEOUT; cycle = cycle + 1) begin
                @(posedge tx_usrclk[0]);
                if ((dut.tx_inst.link_state === 3'd3) &&
                    (dut.tx_ctrl_packed[3:0] === 4'h0)) begin
                    found_payload = 1'b1;
                    break;
                end
            end
            if (!found_payload)
                $fatal(1, "[CASE %0d] Could not locate TX payload for mid-packet link drop",
                       CASE_ID);

            @(negedge tx_usrclk[0]);
            inj_link_drop = 1'b1;
            $display("[CASE %0d][%0t] Injected link drop during TX payload",
                     CASE_ID, $time);

            wait_lane_aligned_state(1'b0, ALIGN_TIMEOUT);
            wait_rx_axi_resetn(1'b0, ALIGN_TIMEOUT);
            repeat (32) begin
                @(posedge rx_core_clk);
                if (m_axi_tvalid !== 1'b0)
                    $fatal(1, "[CASE %0d] AXI output remained valid while link was down",
                           CASE_ID);
            end

            @(negedge rx_core_clk);
            inj_link_drop = 1'b0;
            $display("[CASE %0d][%0t] Released mid-packet link drop", CASE_ID, $time);
        end
    endtask

    task automatic wait_tx_posedge(input int unsigned lane);
        begin
            case (lane)
                0: @(posedge tx_usrclk[0]);
                1: @(posedge tx_usrclk[1]);
                default: $fatal(1, "Invalid lane %0d for TX posedge wait", lane);
            endcase
        end
    endtask

    task automatic wait_tx_negedge(input int unsigned lane);
        begin
            case (lane)
                0: @(negedge tx_usrclk[0]);
                1: @(negedge tx_usrclk[1]);
                default: $fatal(1, "Invalid lane %0d for TX negedge wait", lane);
            endcase
        end
    endtask

    // Payload错误注入
    task automatic inject_payload_error(input int unsigned lane);
        integer cycle;
        logic   found_sof;
        logic   found_payload;
        logic   crc_error_cleared;
        begin
            if (lane >= 2)
                $fatal(1, "Invalid lane %0d for CRC error injection", lane);

            found_sof = 1'b0;
            for (cycle = 0; cycle < ALIGN_TIMEOUT; cycle = cycle + 1) begin
                wait_tx_posedge(lane);
                if ((dut.tx_ctrl_packed[lane*4 +: 4] === 4'hF) &&
                    (dut.tx_data_packed[lane*32 +: 32] === 32'h1C1C1C1C)) begin
                    found_sof = 1'b1;
                    break;
                end
            end
            if (!found_sof)
                $fatal(1, "Could not locate lane-%0d SOF for CRC error injection", lane);

            found_payload = 1'b0;
            for (cycle = 0; cycle < 128; cycle = cycle + 1) begin
                wait_tx_posedge(lane);
                if (dut.tx_ctrl_packed[lane*4 +: 4] === 4'h0) begin
                    found_payload = 1'b1;
                    break;
                end
            end
            if (!found_payload)
                $fatal(1, "Could not locate lane-%0d payload for CRC error injection", lane);

            wait_tx_negedge(lane);
            inj_bit_flip = 2'b01 << lane;
            wait_tx_negedge(lane);
            inj_bit_flip = 2'b00;
            $display("[%0t] Injected one-cycle lane-%0d data error", $time, lane);

            crc_error_cleared = (rx_crc_error === 1'b0);
            for (cycle = 0; cycle < CRC_TIMEOUT; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (rx_crc_error === 1'b0)
                    crc_error_cleared = 1'b1;
                else if (crc_error_cleared && (rx_crc_error === 1'b1)) begin
                    $display("[%0t] Lane %0d CRC error detected", $time, lane);
                    return;
                end
            end
            $fatal(1, "Lane %0d CRC error was not detected within %0d cycles",
                   lane, CRC_TIMEOUT);
        end
    endtask

    // Corrupt the transmitted CRC word itself, rather than a payload beat.
    task automatic inject_crc_word_error(input int unsigned lane);
        integer cycle;
        logic   found_crc;
        logic   crc_error_cleared;
        begin
            if (lane >= 2)
                $fatal(1, "Invalid lane %0d for CRC-word error injection", lane);

            found_crc = 1'b0;
            for (cycle = 0; cycle < ALIGN_TIMEOUT; cycle = cycle + 1) begin
                wait_tx_posedge(lane);
                if (dut.tx_inst.link_state === 3'd4) begin
                    found_crc = 1'b1;
                    break;
                end
            end
            if (!found_crc)
                $fatal(1, "Could not locate TX CRC word for lane-%0d injection", lane);

            wait_tx_negedge(lane);
            inj_bit_flip = 2'b01 << lane;
            wait_tx_negedge(lane);
            inj_bit_flip = 2'b00;
            $display("[%0t] Injected one-cycle lane-%0d CRC-word error", $time, lane);

            crc_error_cleared = (rx_crc_error === 1'b0);
            for (cycle = 0; cycle < CRC_TIMEOUT; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (rx_crc_error === 1'b0)
                    crc_error_cleared = 1'b1;
                else if (crc_error_cleared && (rx_crc_error === 1'b1))
                    return;
            end
            $fatal(1, "Lane %0d CRC-word error was not detected within %0d cycles",
                   lane, CRC_TIMEOUT);
        end
    endtask

    // CRC错误场景
    task automatic run_crc_error_scenario(
        input int unsigned lane,
        input integer      packet_id,
        input integer      beat_count
    );
        integer cycle;
        integer start_error_beats;
        integer start_error_packets;
        integer start_dropped_frames;
        begin
            start_error_beats   = error_rx_beats;
            start_error_packets = error_rx_packets;
            start_dropped_frames = dropped_frames;

            fork
                send_axi_packet(packet_id, beat_count, 1'b0);
                inject_payload_error(lane);
            join

            wait_link_idle(DRAIN_TIMEOUT);
            repeat (8) @(posedge rx_core_clk);

            if ((error_rx_beats - start_error_beats) != 0)
                $fatal(1, "Lane %0d CRC-bad frame leaked %0d AXI beats",
                       lane, error_rx_beats - start_error_beats);
            if ((error_rx_packets - start_error_packets) != 0)
                $fatal(1, "Lane %0d CRC-bad frame leaked an AXI TLAST", lane);
            if ((dropped_frames - start_dropped_frames) != 1)
                $fatal(1, "Lane %0d CRC-bad frame drop count mismatch: expected=1 actual=%0d",
                       lane, dropped_frames - start_dropped_frames);
        end
    endtask

    task automatic run_crc_word_error_scenario;
        integer start_error_beats;
        integer start_error_packets;
        integer start_dropped_frames;
        begin
            $display("[CASE %0d][%0t] Starting CRC-field corruption scenario",
                     CASE_ID, $time);
            start_error_beats    = error_rx_beats;
            start_error_packets  = error_rx_packets;
            start_dropped_frames = dropped_frames;

            fork
                send_axi_packet(5999, 16, 1'b0);
                inject_crc_word_error(0);
            join

            wait_link_idle(DRAIN_TIMEOUT);
            repeat (8) @(posedge rx_core_clk);
            if ((error_rx_beats - start_error_beats) != 0)
                $fatal(1, "CRC-field-corrupt frame leaked %0d AXI beats",
                       error_rx_beats - start_error_beats);
            if ((error_rx_packets - start_error_packets) != 0)
                $fatal(1, "CRC-field-corrupt frame leaked an AXI TLAST");
            if ((dropped_frames - start_dropped_frames) != 1)
                $fatal(1, "CRC-field-corrupt frame drop count mismatch: expected=1 actual=%0d",
                       dropped_frames - start_dropped_frames);
            $display("[CASE %0d][%0t] CRC-field corruption atomic-drop TEST PASS",
                     CASE_ID, $time);
        end
    endtask

    // 非法帧必须整帧丢弃，且后续合法帧可以重新同步
    task automatic run_format_error_scenarios;
        integer start_dropped_frames;
        integer start_error_beats;
        begin
            $display("[CASE %0d][%0t] Starting malformed-frame scenarios",
                     CASE_ID, $time);
            wait_link_idle(DRAIN_TIMEOUT);
            compare_enable      = 1'b0;
            random_ready_enable = 1'b0;
            start_error_beats   = error_rx_beats;

            // EOF outside a frame.
            start_dropped_frames = dropped_frames;
            inject_decoded_symbol({2{32'hFDFDFDFD}}, 8'hFF);
            wait_dropped_frames(start_dropped_frames + 1, DRAIN_TIMEOUT);

            // Empty frame: SOF, CRC placeholder, EOF with no payload beats.
            start_dropped_frames = dropped_frames;
            inject_decoded_symbol({2{32'h1C1C1C1C}}, 8'hFF);
            inject_decoded_symbol(64'd0, 8'h00);
            inject_decoded_symbol({2{32'hFDFDFDFD}}, 8'hFF);
            wait_dropped_frames(start_dropped_frames + 1, DRAIN_TIMEOUT);

            // Missing EOF: suppress one real EOF; the next SOF must abort the
            // unterminated frame before starting the recovery frame.
            start_dropped_frames = dropped_frames;
            fork
                send_axi_packet(6000, 16, 1'b0);
                suppress_next_eof();
            join
            compare_enable = 1'b1;
            send_axi_packet(6001, 8, 1'b1);
            wait_dropped_frames(start_dropped_frames + 1, DRAIN_TIMEOUT);
            wait_scoreboard_empty(DRAIN_TIMEOUT);

            // Repeated SOF inside payload aborts the old frame.  Its remaining
            // payload/CRC is also invalid and must not leak to AXI.
            compare_enable = 1'b0;
            start_dropped_frames = dropped_frames;
            fork
                send_axi_packet(6002, 32, 1'b0);
                inject_repeated_sof();
            join
            wait_dropped_frames(start_dropped_frames + 1, DRAIN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);

            if ((error_rx_beats - start_error_beats) != 0)
                $fatal(1, "Malformed frames leaked %0d AXI beats",
                       error_rx_beats - start_error_beats);

            compare_enable = 1'b1;
            send_axi_packet(6003, 8, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            if (rx_crc_error !== 1'b0)
                $fatal(1, "CRC status did not clear after malformed-frame recovery");

            $display("[CASE %0d][%0t] Malformed-frame atomic-drop TEST PASS",
                     CASE_ID, $time);
        end
    endtask

    // 空闲期及包中断链重连场景
    task automatic run_link_reconnect_scenario;
        begin
            $display("[CASE %0d][%0t] Starting idle link reconnect scenario",
                     CASE_ID, $time);
            random_ready_enable = 1'b0;
            force_rx_stall      = 1'b0;
            normal_phase        = 1'b0;
            overflow_phase      = 1'b0;
            compare_enable      = 1'b1;

            wait_scoreboard_empty(DRAIN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);

            @(negedge rx_core_clk);
            inj_link_drop = 1'b1;
            wait_lane_aligned_state(1'b0, ALIGN_TIMEOUT);
            wait_rx_axi_resetn(1'b0, ALIGN_TIMEOUT);

            repeat (32) begin
                @(posedge rx_core_clk);
                if (m_axi_tvalid !== 1'b0)
                    $fatal(1, "[CASE %0d] AXI output remained valid during idle link drop",
                           CASE_ID);
            end

            @(negedge rx_core_clk);
            inj_link_drop = 1'b0;
            wait_rx_axi_resetn(1'b1, ALIGN_TIMEOUT);
            wait_lane_aligned(ALIGN_TIMEOUT);

            send_axi_packet(2000, 8, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            if (rx_crc_error !== 1'b0)
                $fatal(1, "[CASE %0d] CRC error detected after idle link reconnect",
                       CASE_ID);
            $display("[CASE %0d][%0t] Idle link reconnect TEST PASS", CASE_ID, $time);

            $display("[CASE %0d][%0t] Starting mid-packet link reconnect scenario",
                     CASE_ID, $time);
            wait_link_idle(DRAIN_TIMEOUT);
            compare_enable = 1'b0;

            fork
                send_axi_packet(2001, 256, 1'b0);
                inject_midpacket_link_drop();
            join

            wait_rx_axi_resetn(1'b1, ALIGN_TIMEOUT);
            wait_lane_aligned(ALIGN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);

            if (expected_queue.size() != 0)
                $fatal(1, "[CASE %0d] Scoreboard retained %0d beats after mid-packet reconnect",
                       CASE_ID, expected_queue.size());

            compare_enable = 1'b1;
            send_axi_packet(2002, 16, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            if (rx_crc_error !== 1'b0)
                $fatal(1, "[CASE %0d] CRC error detected after mid-packet link reconnect",
                       CASE_ID);
            $display("[CASE %0d][%0t] Mid-packet link reconnect TEST PASS",
                     CASE_ID, $time);
        end
    endtask

    // 矩阵模式持续流量窗口
    task automatic run_matrix_stream_window;
        integer packet;
        begin
            $display("[CASE %0d][%0t] Starting %0.0f ns PPM/phase stream: rx_ppm=%0.3f",
                     CASE_ID, $time, MATRIX_RUN_TIME_NS, RX_PPM);
            random_ready_enable = 1'b1;
            normal_phase        = 1'b1;
            long_run_done       = 1'b0;

            fork
                begin
                    #(MATRIX_RUN_TIME_NS);
                    long_run_done = 1'b1;
                end
            join_none

            packet = 0;
            while (!long_run_done) begin
                send_axi_packet(3000 + packet, 64, 1'b1);
                packet = packet + 1;
            end

            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            normal_phase        = 1'b0;
            random_ready_enable = 1'b0;

            if (rx_crc_error !== 1'b0)
                $fatal(1, "[CASE %0d] CRC error during PPM/phase stream", CASE_ID);
            $display("[CASE %0d][%0t] PPM/phase stream PASS: packets=%0d beats=%0d",
                     CASE_ID, $time, packet, packet * 64);
        end
    endtask

    // 单个矩阵实例的精简链路回归
    task automatic run_matrix_case;
        integer packet;
        begin
            $display("============================================================");
            $display("[CASE %0d] MATRIX CASE START", CASE_ID);
            $display("RX ppm=%0.3f TX1 phase=%0.3f ns RX0 phase=%0.3f ns RX1 phase=%0.3f ns",
                     RX_PPM, TX1_PHASE_NS, RX0_PHASE_NS, RX1_PHASE_NS);
            $display("Lane delays=%0d/%0d", LANE0_DELAY, LANE1_DELAY);
            $display("============================================================");

            random_ready_enable = 1'b1;
            normal_phase        = 1'b1;
            for (packet = 0; packet < 4; packet = packet + 1)
                send_axi_packet(2500 + packet, packet_lengths[packet], 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            normal_phase = 1'b0;

            if (rx_crc_error !== 1'b0)
                $fatal(1, "[CASE %0d] CRC error after matrix smoke packets", CASE_ID);

            run_matrix_stream_window();
            run_link_reconnect_scenario();

            $display("[CASE %0d][%0t] Starting dual-lane CRC injection", CASE_ID, $time);
            compare_enable      = 1'b0;
            random_ready_enable = 1'b0;
            run_crc_error_scenario(0, 5000, 32);
            run_crc_error_scenario(1, 5001, 32);

            // A clean frame clears the sticky CRC indication and proves that
            // the datapath remains usable after both injected errors.
            compare_enable = 1'b1;
            send_axi_packet(5002, 8, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);

            if (rx_crc_error !== 1'b0)
                $fatal(1, "[CASE %0d] CRC error did not clear after clean recovery frame",
                       CASE_ID);
            if (expected_queue.size() != 0)
                $fatal(1, "[CASE %0d] Scoreboard not empty at matrix completion", CASE_ID);

            $display("[CASE %0d] MATRIX CASE PASS: checked_packets=%0d checked_beats=%0d",
                     CASE_ID, checked_packets, checked_beats);
        end
    endtask

    // 等待FIFO阈值状态
    task automatic wait_rx_prog_full(
        input logic   expected,
        input integer max_cycles
    );
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dut.rx_inst.rx_fifo_prog_full === expected)
                    return;
            end
            $fatal(1, "RX prog_full did not become %0b within %0d cycles",
                   expected, max_cycles);
        end
    endtask

    // 等待溢出丢包状态
    task automatic wait_rx_overflow_drop(
        input logic   expected,
        input integer max_cycles
    );
        integer cycle;
        begin
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dut.rx_inst.rx_overflow_drop === expected)
                    return;
            end
            $fatal(1, "RX overflow_drop did not become %0b within %0d cycles",
                   expected, max_cycles);
        end
    endtask

    // 溢出恢复场景
    task automatic run_rx_overflow_recovery;
        integer packet;
        integer cycle;
        integer start_dropped_frames;
        begin
            $display("[%0t] Starting RX overflow recovery scenario", $time);
            compare_enable      = 1'b1;
            random_ready_enable = 1'b0;
            normal_phase        = 1'b0;
            overflow_phase      = 1'b1;
            force_rx_stall      = 1'b1;

            @(posedge rx_core_clk);
            @(negedge rx_core_clk);
            if (m_axi_tready !== 1'b0)
                $fatal(1, "RX backpressure was not applied");

            for (packet = 0; packet < 48; packet = packet + 1)
                send_axi_packet(1000 + packet, 64, 1'b1);

            wait_rx_prog_full(1'b1, DRAIN_TIMEOUT);
            $display("[%0t] RX prog_full asserted", $time);

            if (dut.rx_inst.rx_fifo_full !== 1'b0)
                $fatal(1, "RX FIFO reached full before drop protection");

            start_dropped_frames = dropped_frames;
            send_axi_packet(1100, 32, 1'b0);
            for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dropped_frames == start_dropped_frames + 1)
                    break;
            end
            if (cycle == DRAIN_TIMEOUT)
                $fatal(1, "Overflow frame did not produce a frame-drop pulse");
            if (rx_crc_error !== 1'b0)
                $fatal(1, "Unexpected CRC error while dropping overflow packet");
            $display("[%0t] Overflow frame atomically suppressed", $time);

            force_rx_stall = 1'b0;
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            wait_rx_prog_full(1'b0, DRAIN_TIMEOUT);
            $display("[%0t] RX prog_full cleared", $time);

            send_axi_packet(1101, 16, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);

            if (dut.rx_inst.rx_fifo_full !== 1'b0)
                $fatal(1, "RX FIFO full remained asserted after recovery");
            if (rx_crc_error !== 1'b0)
                $fatal(1, "CRC error detected after RX overflow recovery");

            overflow_phase = 1'b0;
            $display("[%0t] RX overflow recovery TEST PASS", $time);
        end
    endtask

    // 包中溢出诊断
    task automatic run_midframe_overflow_diagnostic;
        integer cycle;
        integer leaked_beats;
        integer leaked_tlast;
        integer start_dropped_frames;
        begin
            $display("[%0t] Starting mid-frame overflow diagnostic", $time);
            compare_enable      = 1'b0;
            random_ready_enable = 1'b0;
            normal_phase        = 1'b0;
            overflow_phase      = 1'b1;
            force_rx_stall      = 1'b1;
            leaked_beats        = 0;
            leaked_tlast        = 0;
            start_dropped_frames = dropped_frames;

            @(posedge rx_core_clk);
            @(negedge rx_core_clk);
            if (m_axi_tready !== 1'b0)
                $fatal(1, "RX backpressure was not applied for mid-frame diagnostic");
            send_axi_packet(1200, 3200, 1'b0);
            for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (dropped_frames == start_dropped_frames + 1)
                    break;
            end
            if (cycle == DRAIN_TIMEOUT)
                $fatal(1, "Mid-frame overflow did not produce a frame-drop pulse");

            force_rx_stall = 1'b0;
            for (cycle = 0; cycle < DRAIN_TIMEOUT; cycle = cycle + 1) begin
                @(posedge rx_core_clk);
                if (m_axi_tvalid && m_axi_tready) begin
                    leaked_beats = leaked_beats + 1;
                    if (m_axi_tlast)
                        leaked_tlast = leaked_tlast + 1;
                end
                if ((dut.rx_inst.rx_fifo_empty === 1'b1) &&
                    (dut.rx_inst.frame_desc_empty === 1'b1) &&
                    (m_axi_tvalid === 1'b0))
                    break;
            end

            if (cycle == DRAIN_TIMEOUT)
                $fatal(1, "Mid-frame diagnostic FIFO drain timed out");

            $display("[%0t] Mid-frame diagnostic: output_beats=%0d tlast=%0d",
                     $time, leaked_beats, leaked_tlast);
            if ((leaked_beats != 0) || (leaked_tlast != 0))
                $fatal(1, "Overflow frame leaked to AXI: beats=%0d tlast=%0d",
                       leaked_beats, leaked_tlast);

            overflow_phase = 1'b0;
            compare_enable = 1'b1;
            send_axi_packet(1201, 16, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            wait_link_idle(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            if (rx_crc_error !== 1'b0)
                $fatal(1, "CRC error detected after mid-frame overflow recovery");
            $display("[%0t] Mid-frame overflow atomic-drop TEST PASS", $time);
        end
    endtask

    // 接收背压控制
    always @(posedge rx_core_clk) begin
        if (sys_reset) begin
            ready_lfsr  <= 32'h1BAD_F00D;
            m_axi_tready <= 1'b0;
        end
        else if (force_rx_stall) begin
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

    // Beat级Scoreboard
    always @(posedge rx_core_clk) begin
        if (sys_reset) begin
            expected_queue.delete();
            checked_packets   <= 0;
            checked_beats     <= 0;
            error_rx_beats    <= 0;
            error_rx_packets  <= 0;
        end
        else if (m_axi_tvalid && m_axi_tready) begin
            if (compare_enable) begin
                if (expected_queue.size() == 0)
                    $fatal(1, "Unexpected AXI output beat (scoreboard underflow)");
                expected_actual = expected_queue.pop_front();
                if (m_axi_tdata !== expected_actual[63:0])
                    $fatal(1, "AXI data mismatch at beat %0d: expected=%016h actual=%016h",
                           checked_beats, expected_actual[63:0], m_axi_tdata);
                if (m_axi_tkeep !== expected_actual[71:64])
                    $fatal(1, "AXI TKEEP mismatch at beat %0d", checked_beats);
                if (m_axi_tlast !== expected_actual[72])
                    $fatal(1, "AXI TLAST mismatch at beat %0d", checked_beats);

                if (m_axi_tlast)
                    checked_packets <= checked_packets + 1;
                checked_beats <= checked_beats + 1;
            end
            else begin
                error_rx_beats <= error_rx_beats + 1;
                if (m_axi_tlast)
                    error_rx_packets <= error_rx_packets + 1;
            end
        end
    end

    // 原子丢帧计数
    always @(posedge rx_core_clk) begin
        if (sys_reset)
            dropped_frames <= 0;
        else if (rx_frame_drop)
            dropped_frames <= dropped_frames + 1;
    end

    always @(posedge rx_core_clk) begin
        if (!sys_reset && overflow_phase) begin
            if (dut.rx_inst.rx_fifo_full === 1'b1)
                $fatal(1, "RX FIFO full asserted during overflow protection test");
            if ((dut.rx_inst.rx_overflow_drop === 1'b1) &&
                (dut.rx_inst.write_to_axi === 1'b1))
                $fatal(1, "RX FIFO write occurred while overflow_drop was asserted");
            if (rx_crc_error === 1'b1)
                $fatal(1, "Unexpected CRC error during RX overflow test");
        end
    end

    // AXI背压稳定性检查
    always @(posedge rx_core_clk) begin
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

    // 正常流量错误检查
    always @(posedge rx_core_clk) begin
        if (!sys_reset && normal_phase && (rx_crc_error === 1'b1))
            $fatal(1, "Unexpected CRC error during normal traffic");

        if (!sys_reset && normal_phase && (rx_frame_drop === 1'b1))
            $fatal(1, "Unexpected frame drop during normal traffic");

        if (!sys_reset && normal_phase &&
            (dut.rx_inst.rx_overflow_drop === 1'b1))
            $fatal(1,
                   "RX overflow/drop asserted during normal traffic: prog_full=%b full=%b",
                   dut.rx_inst.rx_fifo_prog_full,
                   dut.rx_inst.rx_fifo_full);
    end

    // 主测试流程
    initial begin : test_sequence
        integer packet;

        expected_queue.delete();
        sent_packets      = 0;
        sent_beats        = 0;
        checked_packets   = 0;
        checked_beats     = 0;
        error_rx_beats    = 0;
        error_rx_packets  = 0;
        dropped_frames    = 0;
        source_lfsr       = 32'hC001_CAFE;
        ready_lfsr        = 32'h1BAD_F00D;
        long_run_done     = 1'b0;
        test_done         = 1'b0;
        test_pass         = 1'b0;

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

        wait_lane_aligned(ALIGN_TIMEOUT);

        if (MATRIX_MODE) begin
            run_matrix_case();
            test_pass = 1'b1;
            test_done = 1'b1;
            disable test_sequence;
        end

        if (LONG_RUN) begin
            $display("[%0t] Starting long-run regression: rx_ppm=%0.3f duration_ns=%0.0f",
                     $time, RX_PPM, LONG_RUN_TIME_NS);
            random_ready_enable = 1'b0;
            normal_phase        = 1'b1;

            fork
                begin
                    #(LONG_RUN_TIME_NS);
                    long_run_done = 1'b1;
                end
            join_none

            packet = 0;
            while (!long_run_done) begin
                send_axi_packet(packet, 64, 1'b1);
                packet = packet + 1;
            end

            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            normal_phase = 1'b0;

            $display("============================================================");
            $display("LONG-RUN TEST PASS");
            $display("RX ppm                : %0.3f", RX_PPM);
            $display("Packets checked       : %0d", checked_packets);
            $display("Beats checked         : %0d", checked_beats);
            $display("============================================================");
            test_pass = 1'b1;
            test_done = 1'b1;
            $finish;
        end

        $display("[%0t] Starting normal loopback regression", $time);
        random_ready_enable = 1'b1;
        normal_phase        = 1'b1;

        for (packet = 0; packet < 10; packet = packet + 1)
            send_axi_packet(packet, packet_lengths[packet], 1'b1);

        wait_scoreboard_empty(DRAIN_TIMEOUT);
        repeat (16) @(posedge rx_core_clk);
        if (rx_crc_error !== 1'b0)
            $fatal(1, "CRC check failed after normal traffic drained");
        normal_phase = 1'b0;

        if (checked_packets != 10)
            $fatal(1, "Expected 10 checked packets, received %0d", checked_packets);

        run_link_reconnect_scenario();

        run_rx_overflow_recovery();

        $display("[%0t] Starting CRC error-injection scenario", $time);
        compare_enable      = 1'b0;
        random_ready_enable = 1'b0;

        run_crc_error_scenario(0, 100, 32);
        run_crc_error_scenario(1, 101, 32);
        run_crc_word_error_scenario();

        compare_enable = 1'b1;
        send_axi_packet(5900, 8, 1'b1);
        wait_scoreboard_empty(DRAIN_TIMEOUT);
        wait_link_idle(DRAIN_TIMEOUT);
        repeat (16) @(posedge rx_core_clk);
        if (rx_crc_error !== 1'b0)
            $fatal(1, "CRC status did not clear after CRC recovery frame");

        run_format_error_scenarios();

        if (RUN_MIDFRAME_DIAGNOSTIC) begin
            compare_enable = 1'b1;
            send_axi_packet(102, 1, 1'b1);
            wait_scoreboard_empty(DRAIN_TIMEOUT);
            repeat (16) @(posedge rx_core_clk);
            if (rx_crc_error !== 1'b0)
                $fatal(1, "CRC error did not clear before mid-frame diagnostic");
            run_midframe_overflow_diagnostic();
        end

        $display("============================================================");
        $display("TEST PASS");
        $display("Scoreboard packets checked : %0d", checked_packets);
        $display("Scoreboard beats checked   : %0d", checked_beats);
        $display("Total packets sent     : %0d", sent_packets);
        $display("Total beats sent       : %0d", sent_beats);
        $display("============================================================");
        test_pass = 1'b1;
        test_done = 1'b1;
        $finish;
    end

    // 全局超时保护
    initial begin : global_timeout
        if (LONG_RUN)
            #(LONG_RUN_TIME_NS + 1_000_000.0);
        else
            repeat (200000) @(posedge rx_core_clk);
        $fatal(1, "[CASE %0d] Global simulation timeout", CASE_ID);
    end

endmodule

