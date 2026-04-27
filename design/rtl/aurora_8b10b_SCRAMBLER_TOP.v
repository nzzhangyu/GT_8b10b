`timescale 1ns / 1ps

module aurora_8b10b_SCRAMBLER_TOP (
    output wire [31:0] DATA_OUT,
    output reg  [3:0]  CHAR_IS_K_OUT,

    input  wire [31:0] DATA,
    input  wire [3:0]  CHAR_IS_K,

    // System Interface
    input  wire        CLEAR,
    input  wire        RESET,
    input  wire        USER_CLK
);

    // ************************************** Signal Declarations ***************************
    wire [1:0]  en_scrambler;
    wire [1:0]  bypass_w;
    reg  [1:0]  bypass_r;
    wire        seed_lfsr;
    wire [31:0] user_data;
    wire [31:0] scrambled_data;
    reg         clear_nxt;
    reg         clear_nxt2;
    reg  [31:0] data_nxt;

    // ********************************* Main Body of Code **********************************

    // data pipeline
    always @(posedge USER_CLK) begin
        data_nxt <= DATA;
    end

    // bypass pipeline
    always @(posedge USER_CLK) begin
        bypass_r <= bypass_w;
    end

    // register clear to reset scrambler when CC is being sent from SYM_GEN
    always @(posedge USER_CLK) begin
        clear_nxt  <= CLEAR;
        clear_nxt2 <= clear_nxt;
    end

    assign seed_lfsr = clear_nxt2;

    // bypass_w generation using reduction OR
    assign bypass_w[0] = (RESET == 1'b1) ? 1'b1 :
                         (|CHAR_IS_K[1:0]) ? 1'b1 : 1'b0;

    assign bypass_w[1] = (RESET == 1'b1) ? 1'b1 :
                         (|CHAR_IS_K[3:2]) ? 1'b1 : 1'b0;

    // user_data generation
    assign user_data[15:0]  = (bypass_w[0] == 1'b1) ? 16'h0000 : DATA[15:0];
    assign user_data[31:16] = (bypass_w[1] == 1'b1) ? 16'h0000 : DATA[31:16];

    assign en_scrambler[0]  = ~bypass_w[0];
    assign en_scrambler[1]  = ~bypass_w[1];

    // Scrambler Instantiations
    aurora_8b10b_SCRAMBLER #(
        .C_SEED(16'hFFFF)
    ) aurora_8b10b_scrambler0_i (
        .DOUT   (scrambled_data[15:0]),
        .DIN    (user_data[15:0]),
        .BYPASS (bypass_w[0]),
        .EN     (en_scrambler[0]),
        .CLEAR  (seed_lfsr),
        .RESET  (RESET),
        .CLK    (USER_CLK)
    );

    aurora_8b10b_SCRAMBLER #(
        .C_SEED(16'hFFFF)
    ) aurora_8b10b_scrambler1_i (
        .DOUT   (scrambled_data[31:16]),
        .DIN    (user_data[31:16]),
        .BYPASS (bypass_w[1]),
        .EN     (en_scrambler[1]),
        .CLEAR  (seed_lfsr),
        .RESET  (RESET),
        .CLK    (USER_CLK)
    );

    // Outputs
    assign DATA_OUT[15:0]  = (bypass_r[0] == 1'b1) ? data_nxt[15:0]  : scrambled_data[15:0];
    assign DATA_OUT[31:16] = (bypass_r[1] == 1'b1) ? data_nxt[31:16] : scrambled_data[31:16];

    // CHAR_IS_K pipeline
    always @(posedge USER_CLK) begin
        CHAR_IS_K_OUT <= CHAR_IS_K;
    end

endmodule
