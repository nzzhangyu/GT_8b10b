`timescale 1ns / 1ps
module xpm_fifo_async #(
    parameter FIFO_MEMORY_TYPE  = "block",
    parameter FIFO_WRITE_DEPTH  = 4096,
    parameter READ_MODE         = "fwft",
    parameter WRITE_DATA_WIDTH  = 65,
    parameter READ_DATA_WIDTH   = 65,
    parameter PROG_FULL_THRESH  = 3072,
    parameter PROG_EMPTY_THRESH = 512,
    parameter USE_ADV_FEATURES  = "0A02",
    parameter CDC_SYNC_STAGES   = 3
)(  
    input  wire                         rst,

    input  wire                         wr_clk,
    input  wire                         wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0]  din,
    output wire                         full,
    output wire                         prog_full,
    output wire                         wr_rst_busy,

    input  wire                         rd_clk,
    input  wire                         rd_en,
    output wire [READ_DATA_WIDTH-1:0]   dout,
    output wire                         empty,
    output wire                         prog_empty,
    output wire                         rd_rst_busy
);  
    // ==========================================
    // Parameter and Memory Definitions
    // ==========================================
    localparam int AW = $clog2(FIFO_WRITE_DEPTH);

    logic [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];

    // ==========================================
    // Reset Busy
    // ==========================================
    logic [2:0] wr_rst_pipe;
    logic [2:0] rd_rst_pipe;
    
    assign wr_rst_busy = wr_rst_pipe[2];
    assign rd_rst_busy = rd_rst_pipe[2];
    
    always_ff @(posedge wr_clk or posedge rst) begin
        if (rst) 
            wr_rst_pipe <= 3'b111;
        else
            wr_rst_pipe <= {wr_rst_pipe[1:0], 1'b0};
    end

    always_ff @(posedge rd_clk or posedge rst) begin
        if (rst)
            rd_rst_pipe <= 3'b111;
        else 
            rd_rst_pipe <= {rd_rst_pipe[1:0], 1'b0};
    end

    // ==========================================
    // Write/Read Pointer (Bianary & Gray Code)
    // ========================================== 
    logic [AW:0] wr_ptr_bin;
    logic [AW:0] rd_ptr_bin;
    logic [AW:0] wr_ptr_gray;
    logic [AW:0] rd_ptr_gray;

    // functions: convertation between binary and gray codes
    function automatic logic [AW:0] bin2gray(input logic [AW:0] bin_val);
        return bin_val ^ (bin_val >> 1);
    endfunction

    function automatic logic [AW:0] gray2bin(input logic [AW:0] gray_val);
        logic [AW:0] bin_val;
        bin_val[AW] = gray_val[AW];
        for (int i = AW-1; i >= 0; i--) begin
            bin_val[i] = bin_val[i+1] ^ gray_val[i];
        end
        return bin_val;
    endfunction

    // ==========================================
    // Pointer CDC Synchronizer
    // ==========================================
    logic [AW:0] wr_ptr_gray_meta;
    logic [AW:0] wr_ptr_gray_sync;
    logic [AW:0] rd_ptr_gray_meta;
    logic [AW:0] rd_ptr_gray_sync;

    always_ff @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            rd_ptr_gray_meta <= {(AW+1){1'b0}};
            rd_ptr_gray_sync <= {(AW+1){1'b0}};
        end
        else begin
            rd_ptr_gray_meta <= rd_ptr_gray;
            rd_ptr_gray_sync <= rd_ptr_gray_meta;
        end
    end

    always_ff @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            wr_ptr_gray_meta <= {(AW+1){1'b0}};
            wr_ptr_gray_sync <= {(AW+1){1'b0}};
        end
        else begin
            wr_ptr_gray_meta <= wr_ptr_gray;
            wr_ptr_gray_sync <= wr_ptr_gray_meta;
        end
    end
    
    // ==========================================
    // Write logic and full judgment
    // ==========================================
    logic  int_full;
    assign int_full = (wr_ptr_gray == {~rd_ptr_gray_sync[AW:AW-1], rd_ptr_gray_sync[AW-2:0]});
    assign full     = int_full;

    always_ff @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wr_ptr_bin  <= {(AW+1){1'b0}};
            wr_ptr_gray <= {(AW+1){1'b0}};
        end
        else if (!wr_rst_busy) begin
            if (wr_en && !int_full) begin
                mem[wr_ptr_bin[AW-1:0]] <= din;
                wr_ptr_bin              <= wr_ptr_bin + 1'b1;
                wr_ptr_gray             <= bin2gray(wr_ptr_bin + 1'b1);
            end
        end
    end

    // ==========================================
    // Dynamic FIFO Capacity Calculation: prog_full
    // ==========================================
    logic [AW:0] wr_count;

    assign wr_count  = wr_ptr_bin - gray2bin(rd_ptr_gray_sync);
    assign prog_full = (wr_count >= PROG_FULL_THRESH);

    // ==========================================
    // Read Logic & FWFT Prefetching
    // ==========================================
    logic  int_empty; 
    assign int_empty = (rd_ptr_gray == wr_ptr_gray_sync);
    
    logic                       fwft_valid;
    logic [READ_DATA_WIDTH-1:0] fwft_data;

    wire int_rd_en = !int_empty && (!fwft_valid || rd_en);

    always_ff @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rd_ptr_bin  <= {(AW+1){1'b0}};
            rd_ptr_gray <= {(AW+1){1'b0}};
            fwft_data   <= {READ_DATA_WIDTH{1'b0}};
            fwft_valid  <= 1'b0;
        end
        else if (!rd_rst_busy) begin
            if (int_rd_en) begin
                rd_ptr_bin  <= rd_ptr_bin + 1'b1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
                fwft_data   <= mem[rd_ptr_bin[AW-1:0]];
                fwft_valid  <= 1'b1;
            end
            else if (rd_en)
                fwft_valid <= 1'b0;
        end
    end

    assign empty = ~fwft_valid;
    assign dout  = fwft_data;

    // Dynamic FIFO Capacity Calculation: prog_empty 
    logic [AW:0] rd_count;
    assign rd_count   = gray2bin(wr_ptr_gray_sync) - rd_ptr_bin + fwft_valid;
    assign prog_empty = (rd_count <= PROG_EMPTY_THRESH);

endmodule
