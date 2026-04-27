module gt_idle_Kcode_gen(
    input  logic        USER_CLK,
    input  logic        ENABLE,    
    output logic [31:0] TX_DATA_OUT,
    output logic [3:0]  TXCTRL_OUT
    );

    always_ff @(posedge USER_CLK) begin
        if (ENABLE) begin
            TX_DATA_OUT <= 32'hF7F7F7F7;
            TXCTRL_OUT  <= 4'hF;
        end
        else begin
            TX_DATA_OUT <= 32'h0;
            TXCTRL_OUT  <= 4'h0;
        end
    end

endmodule
