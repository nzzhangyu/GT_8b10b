module fifo_rx_gtdata(
    input  logic        rst,
    input  logic        wr_clk,
    input  logic        rd_clk,
    input  logic [35:0] din,
    input  logic        wr_en,
    input  logic        rd_en,
    output logic [35:0] dout,
    output logic        full,
    output logic        empty
    );

    logic [35:0] mem [0:127];

    int wr_ptr = 0;
    int rd_ptr = 0;
    int count  = 0;

    always_ff @(posedge wr_clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end
        else begin 
            if (wr_en && !full && rd_en && !empty) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= (wr_ptr + 1) % 128;
                rd_ptr      <= (rd_ptr + 1) % 128;
            end 
            else if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= (wr_ptr + 1) % 128;
                count       <= count + 1;
            end 
            else if (rd_en && !empty) begin
                rd_ptr      <= (rd_ptr + 1) % 128;
                count       <= count - 1;
            end
        end
    end

    assign empty = (count == 0);
    assign full  = (count >= 128);
    assign dout  = mem[rd_ptr];
    
endmodule
