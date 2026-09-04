`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/03 11:38:53
// Design Name: 
// Module Name: gt_8b10b_dual_lane
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module gt_8b10b_dual_lane(
    input  wire mgtrefclk,
    input  wire sys_rst,

    input  wire [1:0]  RXP,
    input  wire [1:0]  RXN,
    output wire [1:0]  TXP,
    output wire [1:0]  TXN,

    input  wire [0:0]  INIT_CLK_IN,

    output wire [0:0]  gt_tx_channel_up,
    output wire        gt_tx_lock,

    input  wire [63:0] gt_s_axis_tdata,
    input  wire [7:0]  gt_s_axis_tkeep,
    input  wire        gt_s_axis_tvalid,
    output wire        gt_s_axis_tready,
    input  wire        gt_s_axis_tlast,

    output wire [31:0] gt0_m_axis_tdata,
    output wire [3:0]  gt0_m_axis_tkeep,
    output wire        gt0_m_axis_tvalid,
    input  wire        gt0_m_axis_tready,
    output wire        gt0_m_axis_tlast,

    output wire [31:0] gt1_m_axis_tdata,
    output wire [3:0]  gt1_m_axis_tkeep,
    output wire        gt1_m_axis_tvalid,
    input  wire        gt1_m_axis_tready,
    output wire        gt1_m_axis_tlast
    );

    localparam logic [9:0] CNT_1MS = 10'h3E7;
    localparam int WORDS_IN_BRAM = 512;
    localparam int LANE_NUM      = 2;

    // GTY Quad PLL signals
    logic qpll0lock_int;
    logic qpll0outclk_int;
    logic qpll0outrefclk_int;
    logic qpll0reset_int;

    logic qpll1lock_int;
    logic qpll1outclk_int;
    logic qpll1outrefclk_int;
    logic qpll1reset_int;

    assign gt_tx_lock = qpll0lock_int & qpll1lock_int;

    logic gtwiz_reset_clk_freerun_int;
    assign gtwiz_reset_clk_freerun_int = INIT_CLK_IN;

    logic gt0_tx_usrclk;
    logic gt0_rx_usrclk;
    logic gt1_tx_usrclk;
    logic gt1_rx_usrclk;

    // System Reset Logic
    logic gtwiz_reset_all_int;

    logic sys_rst_d1;
    logic sys_rst_d2;
    logic sys_rst_d3;
    logic sys_rst_d4;
    logic sys_rst_pulse;

    always @(posedge gtwiz_reset_clk_freerun_int) begin
        sys_rst_d1 <= sys_rst;
        sys_rst_d2 <= sys_rst_d1;
        sys_rst_d3 <= sys_rst_d2;
        sys_rst_d4 <= sys_rst_d3;
    end

    assign gtwiz_reset_all_int = sys_rst_d3;
    assign sys_rst_pulse = ~sys_rst_d3 & sys_rst_d4;
    
    // TX User Reset Logic
    logic gt0_tx_reset_done;
    logic gt0_tx_reset_done_d1;
    logic gt0_tx_reset_done_d2;
    logic gt1_tx_reset_done;
    logic gt1_tx_reset_done_d1;
    logic gt1_tx_reset_done_d2;

    always_ff @(posedge gt0_tx_usrclk or negedge gt0_tx_reset_done) begin
        if (~gt0_tx_reset_done) begin
            gt0_tx_reset_done_d1 <= 1'b0;
            gt0_tx_reset_done_d2 <= 1'b0;
        end
        else begin
            gt0_tx_reset_done_d1 <= gt0_tx_reset_done;
            gt0_tx_reset_done_d2 <= gt0_tx_reset_done_d1;
        end
    end

    always_ff @(posedge gt1_tx_usrclk or negedge gt1_tx_reset_done) begin
        if (~gt1_tx_reset_done) begin
            gt1_tx_reset_done_d1 <= 1'b0;
            gt1_tx_reset_done_d2 <= 1'b0;
        end
        else begin
            gt1_tx_reset_done_d1 <= gt1_tx_reset_done;
            gt1_tx_reset_done_d2 <= gt1_tx_reset_done_d1;
        end
    end

    logic gt0_tx_sys_rst;
    logic gt1_tx_sys_rst;
    logic gt_sys_rst;
    logic gt_tx_reset_done;
    logic gt_tx_reset_done_d1;
    logic gt_tx_reset_done_pulse;

    assign gt0_tx_sys_rst = ~gt0_tx_reset_done_d2;
    assign gt1_tx_sys_rst = ~gt1_tx_reset_done_d2;
    assign gt_sys_rst = gt0_tx_sys_rst | gt1_tx_sys_rst;
    assign gt_tx_reset_done = gt0_tx_reset_done && gt1_tx_reset_done;

    always_ff @(posedge gtwiz_reset_clk_freerun_int)
        gt_tx_reset_done_d1 <= gt_tx_reset_done;
    
    assign gt_tx_reset_done_pulse = gt_tx_reset_done & ~gt_tx_reset_done_d1;    

    // RX User Reset Logic
    logic gt0_rx_reset_done;
    logic gt0_rx_reset_done_d1;
    logic gt0_rx_reset_done_d2;
    logic gt0_rx_reset_done_d3;
    logic gt1_rx_reset_done;
    logic gt1_rx_reset_done_d1;
    logic gt1_rx_reset_done_d2;
    logic gt1_rx_reset_done_d3;

    always_ff @(posedge gt0_rx_usrclk or negedge gt0_rx_reset_done) begin
        if (~gt0_rx_reset_done) begin
            gt0_rx_reset_done_d1 <= 1'b0;
            gt0_rx_reset_done_d2 <= 1'b0;
            gt0_rx_reset_done_d3 <= 1'b0;
        end
        else begin
            gt0_rx_reset_done_d1 <= gt0_rx_reset_done;
            gt0_rx_reset_done_d2 <= gt0_rx_reset_done_d1;
            gt0_rx_reset_done_d3 <= gt0_rx_reset_done_d2;
        end
    end

    always_ff @(posedge gt1_rx_usrclk or negedge gt1_rx_reset_done) begin
        if (~gt1_rx_reset_done) begin
            gt1_rx_reset_done_d1 <= 1'b0;
            gt1_rx_reset_done_d2 <= 1'b0;
            gt1_rx_reset_done_d3 <= 1'b0;
        end
        else begin
            gt1_rx_reset_done_d1 <= gt1_rx_reset_done;
            gt1_rx_reset_done_d2 <= gt1_rx_reset_done_d1;
            gt1_rx_reset_done_d3 <= gt1_rx_reset_done_d2;
        end
    end

    logic gt0_rx_sys_rst;
    logic gt1_rx_sys_rst;

    assign gt0_rx_sys_rst = ~gt0_rx_reset_done_d3;
    assign gt1_rx_sys_rst = ~gt1_rx_reset_done_d3;

    // Link Initialization
    typedef enum logic {
        ST_IDLE,
        ST_DELAY
    } init_state_t;

    init_state_t init_state;

    logic [7:0] us_counter;
    logic       flag_1us;
    logic [9:0] ms_counter;
    logic       flag_1ms;
    logic [9:0] delay_1ms;

    logic       gt_tx_channel_up_int;

    always_ff @(posedge gtwiz_reset_clk_freerun_int) begin
        if (gtwiz_reset_all_int) begin
            us_counter <= 8'h00;
            flag_1us   <= 1'b0;
        end
        else if (us_counter == 8'h63) begin
            us_counter <= 8'h00;
            flag_1us   <= 1'b1;
        end
        else begin
            us_counter <= us_counter + 1'b1;
            flag_1us   <= 1'b0;
        end
    end

    always_ff @(posedge gtwiz_reset_clk_freerun_int) begin
        if (gtwiz_reset_all_int) begin
            ms_counter <= 10'h000;
            flag_1ms   <= 1'b0;
        end
        else if (ms_counter == CNT_1MS) begin
            ms_counter <= 10'h000;
            flag_1ms   <= 1'b1;
        end
        else begin
            if (flag_1us == 1'b1) begin
                ms_counter <= ms_counter + 1'b1;
                flag_1ms   <= 1'b0;
            end
        end
    end

    always @(posedge gtwiz_reset_clk_freerun_int) begin
        if (gtwiz_reset_all_int) begin
            init_state        <= ST_IDLE;
            delay_1ms         <= 10'h000;
            gt_tx_channel_up_int <= 1'b0;
        end
        else begin
            case (init_state)
                ST_IDLE: begin
                    delay_1ms <= 10'h000;
                    if (gt_tx_reset_done_pulse || sys_rst_pulse) begin
                        init_state <= ST_DELAY;
                    end
                    else begin
                        init_state <= ST_IDLE;
                    end
                end

                ST_DELAY: begin
                    if (delay_1ms == CNT_1MS) begin
                        delay_1ms            <= 10'h000;
                        init_state           <= ST_IDLE;
                        gt_tx_channel_up_int <= 1'b1;
                    end
                    else begin
                        gt_tx_channel_up_int <= 1'b0;
                        init_state           <= ST_DELAY;
                        if (flag_1us == 1'b1)
                            delay_1ms <= delay_1ms + 1'b1;
                    end
                end
                
                default: begin
                    gt_tx_channel_up_int <= 1'b0;
                    init_state        <= ST_IDLE;
                end
            endcase
        end
    end

    logic gt_tx_channel_up_d1;
    logic gt_tx_channel_up_d2;
    logic gt_tx_channel_up_d3;

    always_ff @(posedge gt0_tx_usrclk) begin
        gt_tx_channel_up_d1 <= gt_tx_channel_up_int && ~sys_rst_d3 && gt_tx_reset_done_d1;
        gt_tx_channel_up_d2 <= gt_tx_channel_up_d1;
        gt_tx_channel_up_d3 <= gt_tx_channel_up_d2;
    end

    assign gt_tx_channel_up = gt_tx_channel_up_d3;

    // TX Data and Control Signals
    logic [63:0] gt_txdata;
    logic [7:0]  gt_txctrl;
    logic [31:0] gt0_txdata;
    logic [7:0]  gt0_txctrl;
    logic [31:0] gt1_txdata;
    logic [7:0]  gt1_txctrl;

    assign gt0_txdata = gt_txdata[31:0];
    assign gt0_txctrl = {4'h0,gt_txctrl[3:0]};
    assign gt1_txdata = gt_txdata[63:32];
    assign gt1_txctrl = {4'h0,gt_txctrl[7:4]};

    logic gt0_rxbyterealign;
    logic gt1_rxbyterealign;

    // RX Data and Control Signals
    logic [31:0] gt0_rxdata;
    logic [7:0]  gt0_rxctrl;
    logic [31:0] gt1_rxdata;
    logic [7:0]  gt1_rxctrl;

    gtwizard_ultrascale_0_gtye4_common_wrapper gtye4_common_wrapper_inst (
        .GTYE4_COMMON_BGBYPASSB         (1'b1),
        .GTYE4_COMMON_BGMONITORENB      (1'b1),
        .GTYE4_COMMON_BGPDB             (1'b1),
        .GTYE4_COMMON_BGRCALOVRD        (5'b10000),
        .GTYE4_COMMON_BGRCALOVRDENB     (1'b1),

        .GTYE4_COMMON_DRPADDR           (16'b0000000000000000),
        .GTYE4_COMMON_DRPCLK            (1'b0),
        .GTYE4_COMMON_DRPDI             (16'b0000000000000000),
        .GTYE4_COMMON_DRPEN             (1'b0),
        .GTYE4_COMMON_DRPWE             (1'b0),

        .GTYE4_COMMON_GTGREFCLK0        (1'b0),
        .GTYE4_COMMON_GTGREFCLK1        (1'b0),
        .GTYE4_COMMON_GTNORTHREFCLK00   (1'b0),
        .GTYE4_COMMON_GTNORTHREFCLK01   (1'b0),
        .GTYE4_COMMON_GTNORTHREFCLK10   (1'b0),
        .GTYE4_COMMON_GTNORTHREFCLK11   (1'b0),
        .GTYE4_COMMON_GTREFCLK00        (mgtrefclk),
        .GTYE4_COMMON_GTREFCLK01        (mgtrefclk),
        .GTYE4_COMMON_GTREFCLK10        (1'b0),
        .GTYE4_COMMON_GTREFCLK11        (1'b0),
        .GTYE4_COMMON_GTSOUTHREFCLK00   (1'b0),
        .GTYE4_COMMON_GTSOUTHREFCLK01   (1'b0),
        .GTYE4_COMMON_GTSOUTHREFCLK10   (1'b0),
        .GTYE4_COMMON_GTSOUTHREFCLK11   (1'b0),
        .GTYE4_COMMON_PCIERATEQPLL0     (3'b000),
        .GTYE4_COMMON_PCIERATEQPLL1     (3'b000),
        .GTYE4_COMMON_PMARSVD0          (8'b00000000),
        .GTYE4_COMMON_PMARSVD1          (8'b00000000),

        .GTYE4_COMMON_QPLL0CLKRSVD0     (1'b0),
        .GTYE4_COMMON_QPLL0CLKRSVD1     (1'b0),
        .GTYE4_COMMON_QPLL0FBDIV        (8'b00000000),
        .GTYE4_COMMON_QPLL0LOCKDETCLK   (1'b0),
        .GTYE4_COMMON_QPLL0LOCKEN       (1'b1),
        .GTYE4_COMMON_QPLL0PD           (1'b0),
        .GTYE4_COMMON_QPLL0REFCLKSEL    (3'b001),
        .GTYE4_COMMON_QPLL0RESET        (qpll0reset_int),

        .GTYE4_COMMON_QPLL1CLKRSVD0     (1'b0),
        .GTYE4_COMMON_QPLL1CLKRSVD1     (1'b0),
        .GTYE4_COMMON_QPLL1FBDIV        (8'b00000000),
        .GTYE4_COMMON_QPLL1LOCKDETCLK   (1'b0),
        .GTYE4_COMMON_QPLL1LOCKEN       (1'b1),
        .GTYE4_COMMON_QPLL1PD           (1'b0),
        .GTYE4_COMMON_QPLL1REFCLKSEL    (3'b001),
        .GTYE4_COMMON_QPLL1RESET        (qpll1reset_int),

        .GTYE4_COMMON_QPLLRSVD1         (8'b00000000),
        .GTYE4_COMMON_QPLLRSVD2         (5'b00000),
        .GTYE4_COMMON_QPLLRSVD3         (5'b00000),
        .GTYE4_COMMON_QPLLRSVD4         (8'b00000000),
        .GTYE4_COMMON_RCALENB           (1'b1),
        .GTYE4_COMMON_SDM0DATA          (25'b0000000000000000000000000),
        .GTYE4_COMMON_SDM0RESET         (1'b0),
        .GTYE4_COMMON_SDM0TOGGLE        (1'b0),
        .GTYE4_COMMON_SDM0WIDTH         (2'b00),
        .GTYE4_COMMON_SDM1DATA          (25'b0000000000000000000000000),
        .GTYE4_COMMON_SDM1RESET         (1'b0),
        .GTYE4_COMMON_SDM1TOGGLE        (1'b0),
        .GTYE4_COMMON_SDM1WIDTH         (2'b00),
        .GTYE4_COMMON_UBCFGSTREAMEN     (1'b0),
        .GTYE4_COMMON_UBDO              (16'b0000000000000000),
        .GTYE4_COMMON_UBDRDY            (1'b0),
        .GTYE4_COMMON_UBENABLE          (1'b0),
        .GTYE4_COMMON_UBGPI             (2'b00),
        .GTYE4_COMMON_UBINTR            (2'b00),
        .GTYE4_COMMON_UBIOLMBRST        (1'b0),
        .GTYE4_COMMON_UBMBRST           (1'b0),
        .GTYE4_COMMON_UBMDMCAPTURE      (1'b0),
        .GTYE4_COMMON_UBMDMDBGRST       (1'b0),
        .GTYE4_COMMON_UBMDMDBGUPDATE    (1'b0),
        .GTYE4_COMMON_UBMDMREGEN        (4'b0000),
        .GTYE4_COMMON_UBMDMSHIFT        (1'b0),
        .GTYE4_COMMON_UBMDMSYSRST       (1'b0),
        .GTYE4_COMMON_UBMDMTCK          (1'b0),
        .GTYE4_COMMON_UBMDMTDI          (1'b0),
        .GTYE4_COMMON_DRPDO             (),
        .GTYE4_COMMON_DRPRDY            (),
        .GTYE4_COMMON_PMARSVDOUT0       (),
        .GTYE4_COMMON_PMARSVDOUT1       (),
        .GTYE4_COMMON_QPLL0FBCLKLOST    (), 
        // Lane 0 QPLL Signals
        .GTYE4_COMMON_QPLL0LOCK         (qpll0lock_int),
        .GTYE4_COMMON_QPLL0OUTCLK       (qpll0outclk_int),
        .GTYE4_COMMON_QPLL0OUTREFCLK    (qpll0outrefclk_int),
        .GTYE4_COMMON_QPLL0REFCLKLOST   (),
        .GTYE4_COMMON_QPLL1FBCLKLOST    (),
        // Lane 1 QPLL Signals
        .GTYE4_COMMON_QPLL1LOCK         (qpll1lock_int),
        .GTYE4_COMMON_QPLL1OUTCLK       (qpll1outclk_int),
        .GTYE4_COMMON_QPLL1OUTREFCLK    (qpll1outrefclk_int),
        .GTYE4_COMMON_QPLL1REFCLKLOST   (),
        .GTYE4_COMMON_QPLLDMONITOR0     (),
        .GTYE4_COMMON_QPLLDMONITOR1     (),
        .GTYE4_COMMON_REFCLKOUTMONITOR0 (),
        .GTYE4_COMMON_REFCLKOUTMONITOR1 (),
        .GTYE4_COMMON_RXRECCLK0SEL      (),
        .GTYE4_COMMON_RXRECCLK1SEL      (),
        .GTYE4_COMMON_SDM0FINALOUT      (),
        .GTYE4_COMMON_SDM0TESTDATA      (),
        .GTYE4_COMMON_SDM1FINALOUT      (),
        .GTYE4_COMMON_SDM1TESTDATA      (),
        .GTYE4_COMMON_UBDADDR           (),
        .GTYE4_COMMON_UBDEN             (),
        .GTYE4_COMMON_UBDI              (),
        .GTYE4_COMMON_UBDWE             (),
        .GTYE4_COMMON_UBMDMTDO          (),
        .GTYE4_COMMON_UBRSVDOUT         (),
        .GTYE4_COMMON_UBTXUART          ()
    );

    gtwizard_ultrascale_0_example_top  gtwizard_ultrascale_0_example_top_inst (
        .qpll0lock_in               (qpll0lock_int),
        .qpll0clk_in                (qpll0outclk_int),
        .qpll0outrefclk_in          (qpll0outrefclk_int),
        .qpll0_rst_out              (qpll0reset_int),
        .ch0_gtyrxn_in              (RXN[0]),
        .ch0_gtyrxp_in              (RXP[0]),
        .ch0_gtytxn_out             (TXN[0]),
        .ch0_gtytxp_out             (TXP[0]),
        .gtwiz_reset_clk_freerun_in (gtwiz_reset_clk_freerun_int),
        .gtwiz_reset_all_in         (gtwiz_reset_all_int),
        .gtwiz_reset_tx_datapath_in (1'b0),
        .gtwiz_reset_rx_datapath_in (1'b0),
        .txdata_in                  (gt0_txdata),
        .txctrl0_in                 (),
        .txctrl1_in                 (),
        .txctrl2_in                 (gt0_txctrl),
        .rxdata_out                 (gt0_rxdata),
        .rxctrl0_out                (),
        .rxctrl1_out                (),
        .rxctrl2_out                (gt0_rxctrl),
        .rxctrl3_out                (),
        .tx_usrclk2_out             (gt0_tx_usrclk),
        .rx_usrclk2_out             (gt0_rx_usrclk),
        .tx_reset_done_out          (gt0_tx_reset_done),
        .rx_reset_done_out          (gt0_rx_reset_done),
        .rxbyterealign_out          (gt0_rxbyterealign)
    );

    gtwizard_ultrascale_1_example_top  gtwizard_ultrascale_1_example_top_inst (
        .qpll1lock_in               (qpll1lock_int),
        .qpll1clk_in                (qpll1outclk_int),
        .qpll1outrefclk_in          (qpll1outrefclk_int),
        .qpll1_rst_out              (qpll1reset_int),
        .ch0_gtyrxn_in              (RXN[1]),
        .ch0_gtyrxp_in              (RXP[1]),
        .ch0_gtytxn_out             (TXN[1]),
        .ch0_gtytxp_out             (TXP[1]),
        .gtwiz_reset_clk_freerun_in (gtwiz_reset_clk_freerun_int),
        .gtwiz_reset_all_in         (gtwiz_reset_all_int),
        .gtwiz_reset_tx_datapath_in (1'b0),
        .gtwiz_reset_rx_datapath_in (1'b0),
        .txdata_in                  (gt1_txdata),
        .txctrl0_in                 (),
        .txctrl1_in                 (),
        .txctrl2_in                 (gt1_txctrl),
        .rxdata_out                 (gt1_rxdata),
        .rxctrl0_out                (),
        .rxctrl1_out                (),
        .rxctrl2_out                (gt1_rxctrl),
        .rxctrl3_out                (),
        .tx_usrclk2_out             (gt1_tx_usrclk),
        .rx_usrclk2_out             (gt1_rx_usrclk),
        .tx_reset_done_out          (gt1_tx_reset_done),
        .rx_reset_done_out          (gt1_rx_reset_done),
        .rxbyterealign_out          (gt1_rxbyterealign)
    );

    AXI2GI # (
        .WORDS_IN_BRAM(WORDS_IN_BRAM),
        .LANE_NUM(LANE_NUM)
    ) TX_AXI2GI (
        .i_gt_txresetdone   ({gt1_tx_reset_done, gt0_tx_reset_done} ),
        .i_s_axi_rx_tdata   (gt_s_axis_tdata                        ),
        .i_s_axi_rx_tkeep   (gt_s_axis_tkeep                        ),
        .i_s_axi_rx_tvalid  (gt_s_axis_tvalid                       ),
        .o_s_axi_rx_tready  (gt_s_axis_tready                       ),
        .i_s_axi_rx_tlast   (gt_s_axis_tlast                        ),
        .o_tx_data_out      (gt_txdata                              ),
        .o_txctrl_out       (gt_txctrl                              ), 
        .i_user_clk         (gt0_tx_usrclk                          ),
        .i_system_reset     (gt_sys_rst | ~gt_tx_channel_up         )
    );

    GI2AXI # (
        .WORDS_IN_BRAM(WORDS_IN_BRAM),
        .LANE_NUM(LANE_NUM)
    ) RX_GI2AXI0 (
        .i_gt_rxresetdone   (gt0_rx_reset_done),
        .i_rx_data_in       (gt0_rxdata),
        .i_rxctrl_in        (gt0_rxctrl),
        .i_rx_clk           (),
        .o_m_axi_tx_tdata   (gt0_m_axis_tdata),
        .o_m_axi_tx_tkeep   (gt0_m_axis_tkeep),
        .o_m_axi_tx_tvalid  (gt0_m_axis_tvalid),
        .i_m_axi_tx_tready  (gt0_m_axis_tready),
        .o_m_axi_tx_tlast   (gt0_m_axis_tlast),
        .i_user_clk         (gt0_rx_usrclk),
        .i_system_reset     (i_system_reset),
        .o_lane_aligned     (o_lane_aligned),
        .o_rx_crc_error     (o_rx_crc_error)
    );

    GI2AXI # (
        .WORDS_IN_BRAM(WORDS_IN_BRAM),
        .LANE_NUM(LANE_NUM)
    ) RX_GI2AXI1 (
        .i_gt_rxresetdone   (gt1_rx_reset_done),
        .i_rx_data_in       (gt1_rxdata),
        .i_rxctrl_in        (gt1_rxctrl),
        .i_rx_clk           (),
        .o_m_axi_tx_tdata   (gt1_m_axis_tdata),
        .o_m_axi_tx_tkeep   (gt1_m_axis_tkeep),
        .o_m_axi_tx_tvalid  (gt1_m_axis_tvalid),
        .i_m_axi_tx_tready  (gt1_m_axis_tready),
        .o_m_axi_tx_tlast   (gt1_m_axis_tlast),
        .i_user_clk         (gt1_rx_usrclk),
        .i_system_reset     (i_system_reset),
        .o_lane_aligned     (o_lane_aligned),
        .o_rx_crc_error     (o_rx_crc_error)
    );

endmodule
