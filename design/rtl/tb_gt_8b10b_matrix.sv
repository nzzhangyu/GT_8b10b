`timescale 1ns / 1ps

module tb_gt_8b10b_matrix;

    timeunit 1ns;
    timeprecision 1fs;

    logic [7:0] test_done;
    logic [7:0] test_pass;

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(1), .MATRIX_MODE(1'b1), .RX_PPM(0.0),
        .TX1_PHASE_NS(0.0), .RX0_PHASE_NS(0.0), .RX1_PHASE_NS(0.0),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_1 (.test_done(test_done[0]), .test_pass(test_pass[0]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(2), .MATRIX_MODE(1'b1), .RX_PPM(0.0),
        .TX1_PHASE_NS(0.0), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(1.6),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_2 (.test_done(test_done[1]), .test_pass(test_pass[1]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(3), .MATRIX_MODE(1'b1), .RX_PPM(0.0),
        .TX1_PHASE_NS(0.0), .RX0_PHASE_NS(0.8), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_3 (.test_done(test_done[2]), .test_pass(test_pass[2]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(4), .MATRIX_MODE(1'b1), .RX_PPM(0.0),
        .TX1_PHASE_NS(0.8), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_4 (.test_done(test_done[3]), .test_pass(test_pass[3]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(5), .MATRIX_MODE(1'b1), .RX_PPM(100.0),
        .TX1_PHASE_NS(0.8), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_5 (.test_done(test_done[4]), .test_pass(test_pass[4]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(6), .MATRIX_MODE(1'b1), .RX_PPM(-100.0),
        .TX1_PHASE_NS(0.8), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_6 (.test_done(test_done[5]), .test_pass(test_pass[5]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(7), .MATRIX_MODE(1'b1), .RX_PPM(1000.0),
        .TX1_PHASE_NS(0.8), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_7 (.test_done(test_done[6]), .test_pass(test_pass[6]));

    tb_gt_8b10b_selfcheck #(
        .CASE_ID(8), .MATRIX_MODE(1'b1), .RX_PPM(-1000.0),
        .TX1_PHASE_NS(0.8), .RX0_PHASE_NS(1.6), .RX1_PHASE_NS(2.4),
        .LANE0_DELAY(32), .LANE1_DELAY(48),
        .RUN_MIDFRAME_DIAGNOSTIC(1'b0)
    ) case_8 (.test_done(test_done[7]), .test_pass(test_pass[7]));

    initial begin : matrix_completion
        wait (&test_done);
        #1.0;

        $display("============================================================");
        $display("8B10B PPM/PHASE MATRIX SUMMARY");
        for (int case_idx = 0; case_idx < 8; case_idx = case_idx + 1)
            $display("CASE %0d : %s", case_idx + 1,
                     test_pass[case_idx] ? "PASS" : "FAIL");
        $display("============================================================");

        if (&test_pass) begin
            $display("MATRIX TEST PASS");
            $finish;
        end
        else begin
            $fatal(1, "MATRIX TEST FAIL: pass_bitmap=%b", test_pass);
        end
    end

    initial begin : matrix_timeout
        #500_000.0;
        $fatal(1, "MATRIX TEST TIMEOUT: done_bitmap=%b pass_bitmap=%b",
               test_done, test_pass);
    end

endmodule

