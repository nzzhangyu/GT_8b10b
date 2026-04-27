module xpm_fifo_sync #(
    parameter FIFO_MEMORY_TYPE  = "block",
    parameter FIFO_WRITE_DEPTH  = 4096,
    parameter READ_MODE         = "fwft",
    parameter FIFO_READ_LATENCY = 0,
    parameter WRITE_DATA_WIDTH  = 65,
    parameter READ_DATA_WIDTH   = 65,
    parameter PROG_FULL_THRESH  = 3072,
    parameter PROG_EMPTY_THRESH = 512,
    parameter USE_ADV_FEATURES  = "0A02"
)(
    input  wire                        rst,
    input  wire                        wr_clk,
    input  wire                        wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0] din,
    output wire                        full,
    output wire                        prog_full,
    input  wire                        rd_en,
    output wire [READ_DATA_WIDTH-1:0]  dout,
    output wire                        empty,
    output wire                        prog_empty
    );

    reg [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];
    int wr_ptr;
    int rd_ptr;
    int count;

    always_ff @(posedge wr_clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end
        else begin 
            if (wr_en && !full && rd_en && !empty) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= (wr_ptr + 1) % FIFO_WRITE_DEPTH;
                rd_ptr      <= (rd_ptr + 1) % FIFO_WRITE_DEPTH;
            end 
            // write only
            else if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= (wr_ptr + 1) % FIFO_WRITE_DEPTH;
                count       <= count + 1;
            end 
            // read only
            else if (rd_en && !empty) begin
                rd_ptr      <= (rd_ptr + 1) % FIFO_WRITE_DEPTH;
                count       <= count - 1;
            end
        end
    end

        assign empty      = (count == 0);
        assign full       = (count == FIFO_WRITE_DEPTH);
        assign prog_empty = (count <= PROG_EMPTY_THRESH);
        assign prog_full  = (count >= PROG_FULL_THRESH);

        assign dout = empty ? '0 : mem[rd_ptr];


endmodule
