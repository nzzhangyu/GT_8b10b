module CRC_16 (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_crc_clear,
    input  wire        i_crc_en,   
    input  wire [15:0] i_data,
    output wire [15:0] o_crc
);
    
    wire [15:0] crc_data_r;
    reg  [15:0] crc_temp;

    assign o_crc      = crc_temp;
    assign crc_data_r = i_data ^ crc_temp;

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst | i_crc_clear) 
            crc_temp <= 16'h0000;
        else if (i_crc_en) begin
            crc_temp[0]  <= crc_data_r[12] ^ crc_data_r[8]  ^ crc_data_r[5]  ^ crc_data_r[4]; 
            crc_temp[1]  <= crc_data_r[13] ^ crc_data_r[9]  ^ crc_data_r[6]  ^ crc_data_r[5];
            crc_temp[2]  <= crc_data_r[14] ^ crc_data_r[10] ^ crc_data_r[7]  ^ crc_data_r[6];
            crc_temp[3]  <= crc_data_r[15] ^ crc_data_r[11] ^ crc_data_r[8]  ^ crc_data_r[7]  ^ crc_data_r[0];
            crc_temp[4]  <= crc_data_r[9]  ^ crc_data_r[5]  ^ crc_data_r[4]  ^ crc_data_r[1]  ^ crc_data_r[0];
            crc_temp[5]  <= crc_data_r[10] ^ crc_data_r[6]  ^ crc_data_r[5]  ^ crc_data_r[2]  ^ crc_data_r[1];
            crc_temp[6]  <= crc_data_r[11] ^ crc_data_r[7]  ^ crc_data_r[6]  ^ crc_data_r[3]  ^ crc_data_r[2]  ^ crc_data_r[0];
            crc_temp[7]  <= crc_data_r[12] ^ crc_data_r[8]  ^ crc_data_r[7]  ^ crc_data_r[4]  ^ crc_data_r[3]  ^ crc_data_r[1]  ^ crc_data_r[0];
            
            crc_temp[8]  <= crc_data_r[13] ^ crc_data_r[9]  ^ crc_data_r[8]  ^ crc_data_r[5]  ^ crc_data_r[4]  ^ crc_data_r[2]  ^ crc_data_r[1]  ^ crc_data_r[0];           
            crc_temp[9]  <= crc_data_r[14] ^ crc_data_r[10] ^ crc_data_r[9]  ^ crc_data_r[6]  ^ crc_data_r[5]  ^ crc_data_r[3]  ^ crc_data_r[2]  ^ crc_data_r[1];
            crc_temp[10] <= crc_data_r[15] ^ crc_data_r[11] ^ crc_data_r[10] ^ crc_data_r[7]  ^ crc_data_r[6]  ^ crc_data_r[4]  ^ crc_data_r[3]  ^ crc_data_r[2];
            crc_temp[11] <= crc_data_r[11] ^ crc_data_r[7]  ^ crc_data_r[3]  ^ crc_data_r[0];
            crc_temp[12] <= crc_data_r[12] ^ crc_data_r[8]  ^ crc_data_r[4]  ^ crc_data_r[1]  ^ crc_data_r[0];
            crc_temp[13] <= crc_data_r[13] ^ crc_data_r[9]  ^ crc_data_r[5]  ^ crc_data_r[2]  ^ crc_data_r[1];
            crc_temp[14] <= crc_data_r[14] ^ crc_data_r[10] ^ crc_data_r[6]  ^ crc_data_r[3]  ^ crc_data_r[2];
            crc_temp[15] <= crc_data_r[15] ^ crc_data_r[11] ^ crc_data_r[7]  ^ crc_data_r[4]  ^ crc_data_r[3];
        end  
    end

endmodule
