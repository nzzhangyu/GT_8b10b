module gtwizard_2_GT_INITSEQ_GEN (
    output reg [31:0] TX_DATA_OUT,
    output reg [3:0]  TXCTRL_OUT,
    input  wire       USER_CLK,
    input  wire       ENABLE
);
    always_ff @(posedge USER_CLK) begin
        if (ENABLE) begin
            TX_DATA_OUT <= 32'hBCBCBCBC; 
            TXCTRL_OUT  <= 4'hF;
        end else begin
            TX_DATA_OUT <= 32'h0;
            TXCTRL_OUT  <= 4'h0;
        end
    end
endmodule
