//-----------------------------------------------------------------------------
// (c) Copyright 2012 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property laws.
// [Disclaimer truncated for brevity, same as original VHDL]
//-----------------------------------------------------------------------------

module aurora_8b10b_SCRAMBLER #(
    parameter [15:0] C_SEED = 16'hFFFF
)(
    output reg  [15:0] DOUT = 16'h0000,

    input  wire [15:0] DIN,
    input  wire        BYPASS,
    input  wire        EN,

    // System Interface
    input  wire        CLEAR,
    input  wire        RESET,
    input  wire        CLK
);

    //**************************************Signal Declarations***************************
    wire [15:0] dataNext;
    wire [15:0] lfsrNext;
    reg  [15:0] lfsr = 16'h0000;
    wire [15:0] dout_temp;

    //*********************************Main Body of Code**********************************

    assign dout_temp = (BYPASS == 1'b1) ? DIN : dataNext;
    
    //-----------------------------------------------------------------------------
    // Scrambler / De-Scrambler Register
    //-----------------------------------------------------------------------------
    always @(posedge CLK) begin
        if (EN == 1'b1) begin
            DOUT <= dout_temp;
        end
    end

    //-----------------------------------------------------------------------------
    // 16-bit LFSR
    //-----------------------------------------------------------------------------
    always @(posedge CLK) begin
        if ((RESET | CLEAR) == 1'b1) begin
            lfsr <= C_SEED;
        end else if (EN == 1'b1) begin
            lfsr <= lfsrNext;
        end
    end

    //-----------------------------------------------------------------------------
    // LFSR XORs
    //-----------------------------------------------------------------------------
    assign lfsrNext[0]  = lfsr[8];
    assign lfsrNext[1]  = lfsr[9];
    assign lfsrNext[2]  = lfsr[10];
    assign lfsrNext[3]  = lfsr[8]  ^ lfsr[11];
    assign lfsrNext[4]  = lfsr[8]  ^ lfsr[9]  ^ lfsr[12];
    assign lfsrNext[5]  = lfsr[8]  ^ lfsr[9]  ^ lfsr[10] ^ lfsr[13];
    assign lfsrNext[6]  = lfsr[9]  ^ lfsr[10] ^ lfsr[11] ^ lfsr[14];
    assign lfsrNext[7]  = lfsr[10] ^ lfsr[11] ^ lfsr[12] ^ lfsr[15];
    assign lfsrNext[8]  = lfsr[0]  ^ lfsr[11] ^ lfsr[12] ^ lfsr[13];
    assign lfsrNext[9]  = lfsr[1]  ^ lfsr[12] ^ lfsr[13] ^ lfsr[14];
    assign lfsrNext[10] = lfsr[2]  ^ lfsr[13] ^ lfsr[14] ^ lfsr[15];
    assign lfsrNext[11] = lfsr[3]  ^ lfsr[14] ^ lfsr[15];
    assign lfsrNext[12] = lfsr[4]  ^ lfsr[15];
    assign lfsrNext[13] = lfsr[5];
    assign lfsrNext[14] = lfsr[6];
    assign lfsrNext[15] = lfsr[7];

    //-----------------------------------------------------------------------------
    // Additive Scrambler / De-Scrambler XORs
    //-----------------------------------------------------------------------------
    assign dataNext[0]  = EN & (DIN[0]  ^ lfsr[15]);
    assign dataNext[1]  = EN & (DIN[1]  ^ lfsr[14]);
    assign dataNext[2]  = EN & (DIN[2]  ^ lfsr[13]);
    assign dataNext[3]  = EN & (DIN[3]  ^ lfsr[12]);
    assign dataNext[4]  = EN & (DIN[4]  ^ lfsr[11]);
    assign dataNext[5]  = EN & (DIN[5]  ^ lfsr[10]);
    assign dataNext[6]  = EN & (DIN[6]  ^ lfsr[9]);
    assign dataNext[7]  = EN & (DIN[7]  ^ lfsr[8]);
    assign dataNext[8]  = EN & (DIN[8]  ^ lfsr[7]);
    assign dataNext[9]  = EN & (DIN[9]  ^ lfsr[6]);
    assign dataNext[10] = EN & (DIN[10] ^ lfsr[5]);
    assign dataNext[11] = EN & (DIN[11] ^ lfsr[4]);
    assign dataNext[12] = EN & (DIN[12] ^ lfsr[3]);
    assign dataNext[13] = EN & (DIN[13] ^ lfsr[2]);
    assign dataNext[14] = EN & (DIN[14] ^ lfsr[1]);
    assign dataNext[15] = EN & (DIN[15] ^ lfsr[0]);

endmodule