module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,

    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,

    inout wire [3:0]  I_button,

    output wire       O_uart_tx,
    input  wire       I_uart_rx,

    input  wire       I_sw_clear,
    input  wire       I_sw_diag,
    input  wire       I_sw_aux,
    input  wire       I_sw_contour,

    output wire       O_screen_pwm,
    output wire       O_servo_pwm,

    output wire [3:0] O_led,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n,
    inout wire        IO_rx_clk_pad_p,
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n
);

    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;

	wire        	S_pll_lock;
    wire        	S_rst_n;

	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req;

	wire        	S_csi_rx_clk;
    wire        	S_hs_rx_valid;
    wire[15:0]  	S_hs_rx_data;
	wire[1:0]   	S_lane_error;

	wire        	S_csi_frame_start;
	wire        	S_csi_frame_end;
	wire        	S_csi_valid;
	wire[31:0]  	S_csi_data;

	wire        	S_raw10_frame_start;
	wire        	S_raw10_frame_end;
	wire        	S_raw10_valid;
	wire [39:0] 	S_raw10_data;

	wire 			S_axis_tlast;
	wire 			S_axis_tuser;
	wire [39:0]		S_axis_tdata;
	wire 			S_axis_tvalid;

	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;

	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid;

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;

    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;
    wire[127:0] S_vi_128b_data;

    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy;
    wire[1:0]   S_video_out_rp;

    wire[3:0]   S_lat_frames_ddr;
    wire[3:0]   S_lat_frames;

    wire        S_ddr_user_wr_en;
    wire        S_ddr_user_rd_en;
    wire[24:0]  S_ddr_user_addr;
    wire[127:0] S_ddr_user_wr_data;
    wire        S_ddr_user_ready;
    wire        S_ddr_user_rd_valid;
    wire[127:0] S_ddr_user_rd_data;

    wire        S_vi_ddr_wr_en;
    wire[24:0]  S_vi_ddr_wr_addr;
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;
    wire[24:0]  S_vo_ddr_rd_addr;
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete;
    wire[24:0]  S_mc_app_addr;
    wire[2:0]   S_mc_app_cmd;
    wire        S_mc_app_en;
    wire[127:0] S_mc_app_wdf_data;
    wire        S_mc_app_wdf_end;
    wire[15:0]  S_mc_app_wdf_mask;
    wire        S_mc_app_wdf_wren;
    wire[127:0] S_mc_app_rd_data;
    wire        S_mc_app_rd_data_end;
    wire        S_mc_app_rd_data_valid;
    wire        S_mc_app_rdy;
    wire        S_mc_app_wdf_rdy;
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;

    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;

    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };

	assign O_cam_rst 	= 1'b1;
    assign O_cam_24m 	= S_24m_clk;

    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),

        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );

  reg [1:0] S_ae_sw_sync;
  always @(posedge S_24m_clk or negedge S_rst_n) begin
      if (!S_rst_n) S_ae_sw_sync <= 2'b00;
      else          S_ae_sw_sync <= { S_ae_sw_sync[0], I_sw_aux };
  end

  wire S_ae_en;
  wire S_ae_hi;

  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_rst_n),

      .I_btn(4'b1111),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),

      .I_y_med(S_cart_med),
      .I_y_med_tog(S_cart_med_tog),

      .I_ae_en(S_ae_en),

      .I_ae_kick(1'b0),

      .I_ae_hi(S_ae_hi),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );

    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),
      .I_rst_n(S_rst_n),
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),
      .IO_cam_sda(IO_cam_sda),
      .O_cfg_done(S_cam_cfg_done),
      .O_ae_cfg_done(S_ae_cfg_done)
  );

    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),
        .HS_VGA_GAIN           ( "8dB" ),
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),

        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),

        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),

        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),

        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),

        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );

csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);

raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );

uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
)
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);

assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;

isp_top u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
  );

    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),
        .O_lat_frames         ( S_lat_frames_ddr      ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );

    reg [3:0] S_lat_s1, S_lat_s2;
    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n) begin
            S_lat_s1 <= 4'd0;
            S_lat_s2 <= 4'd0;
        end
        else begin
            S_lat_s1 <= S_lat_frames_ddr;
            S_lat_s2 <= S_lat_s1;
        end
    end
    assign S_lat_frames = S_lat_s2;

    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;

    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),

        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),

        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );

    wire S_btn_next;
    wire S_btn_next_long;
    wire S_btn_line;
    wire S_btn_filt;
    wire S_btn_raw;
    wire S_btn_long;

    key_long_press u_key_next (
        .I_clk          ( S_hdmi_pixel_clk ),
        .I_rst_n        ( S_rst_n          ),
        .I_key_in       ( I_button[2]      ),
        .O_short        ( S_btn_next       ),
        .O_long         ( S_btn_next_long  )
    );

    key_remove_shakes u_key_line (
        .I_clk          ( S_hdmi_pixel_clk ),
        .I_rst_n        ( S_rst_n          ),
        .I_key_in       ( I_button[1]      ),
        .O_key_trig_out ( S_btn_line       )
    );

    key_remove_shakes u_key_filt (
        .I_clk          ( S_hdmi_pixel_clk ),
        .I_rst_n        ( S_rst_n          ),
        .I_key_in       ( I_button[0]      ),
        .O_key_trig_out ( S_btn_filt       )
    );

    key_long_press u_key_raw (
        .I_clk          ( S_hdmi_pixel_clk ),
        .I_rst_n        ( S_rst_n          ),
        .I_key_in       ( I_button[3]      ),
        .O_short        ( S_btn_raw        ),
        .O_long         ( S_btn_long       )
    );

    reg S_osd_on;

    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n)
            S_osd_on <= 1'b0;
        else if (S_btn_line)
            S_osd_on <= ~S_osd_on;
    end

    wire [2:0]  S_sport_mode;
    wire [1:0]  S_sm_use_y0;
    wire [8:0]  S_sm_hold;
    wire [7:0]  S_sm_refr;
    wire [7:0]  S_sm_tol;
    wire [24:0] S_sm_min_amp;

    sport_mode u_sport_mode (
        .I_clk        ( S_hdmi_pixel_clk ),
        .I_rst_n      ( S_rst_n          ),
        .I_btn_next   ( S_btn_next       ),
        .I_btn_prev   ( 1'b0             ),
        .O_mode       ( S_sport_mode     ),
        .O_use_y0     ( S_sm_use_y0      ),
        .O_hold       ( S_sm_hold        ),
        .O_refractory ( S_sm_refr        ),
        .O_rhythm_tol ( S_sm_tol         ),
        .O_min_amp    ( S_sm_min_amp     )
    );

    reg [3:0] S_disp_mode;

    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n)
            S_disp_mode <= 4'd0;

        else if (S_btn_filt)
            S_disp_mode <= (S_disp_mode >= 4'd13) ? 4'd0 : S_disp_mode + 1'b1;
    end

    reg [1:0] S_ae_mode;
    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n)
            S_ae_mode <= 2'd0;
        else if (S_btn_long)
            S_ae_mode <= 2'd2;
        else if (S_btn_raw)
            S_ae_mode <= (S_ae_mode == 2'd0) ? 2'd1 : 2'd0;
    end

    wire S_ae_en_new = (S_ae_mode == 2'd2);
    wire S_ae_hi_new = (S_ae_mode == 2'd1);

    assign S_ae_en = S_ae_en_new;
    assign S_ae_hi = S_ae_hi_new;

    wire        W_cart_on   = (S_disp_mode >= 4'd10);

    assign S_enh_mode  = W_cart_on ? 4'd0 : S_disp_mode;
    assign S_cart_mode = (S_disp_mode == 4'd10) ? 2'd3 :
                         (S_disp_mode == 4'd11) ? 2'd0 :
                         (S_disp_mode == 4'd12) ? 2'd1 :
                                                  2'd2;
    assign S_cart_qen  = (S_disp_mode == 4'd13);

    wire        S_enh_de;
    wire [23:0] S_enh_data;

    wire        S_cart_de;
    wire [23:0] S_cart_data;
    reg         S_cart_de_d;
    wire [ 7:0] S_cart_med;
    wire        S_cart_med_tog;
    wire [ 1:0] S_cart_mode;
    wire        S_cart_qen;
    wire [ 3:0] S_enh_mode;
    wire        S_enh_de;
    wire [23:0] S_enh_data;
    wire [ 7:0] S_p_edge_th;
    wire [ 7:0] S_p_bin_th;
    wire [ 3:0] S_p_ev_gain;
    wire [ 7:0] S_p_cart_edge_th;

    wire [ 3:0] S_p_quant_hi;
    wire [ 7:0] S_p_k_us_q4;
    wire [ 3:0] S_p_sat_k;
    wire        S_p_sat_en;
    wire [ 1:0] S_p_edge_dark;
    wire [ 7:0] S_p_contrast_q4;

    wire [ 2:0] S_p_lift_shift;
    wire [ 2:0] S_p_enh_sat_k;
    wire        S_gamma_de;
    wire [23:0] S_gamma_data;

    wire        S_dehaze_vsync;
    wire        S_dehaze_hsync;
    wire        S_dehaze_de;
    wire [23:0] S_dehaze_data;

    reg  [23:0] S_dh2_data;
    reg         S_dh2_de;
    reg         S_dh2_vs;
    reg         S_dh2_hs;

    reg  [15:0] S_ag_px_d1, S_ag_px_d2;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_ag_px_d1 <= 16'd968;
            S_ag_px_d2 <= 16'd968;
        end else begin
            S_ag_px_d1 <= S_ag;
            S_ag_px_d2 <= S_ag_px_d1;
        end
    end

    dehaze #(
        .BLACK_LEVEL   ( 8'd16  ),
        .BL_GAIN_TRACK ( 1'b0   )
    ) u_dehaze (
        .I_clk   ( S_hdmi_pixel_clk  ),
        .I_rst_n ( S_hdmi_rst_n      ),
        .I_vsync ( S_hdmi_out_vsync  ),
        .I_hsync ( S_hdmi_out_hsync  ),
        .I_de    ( S_hdmi_out_de     ),
        .I_data  ( S_hdmi_out_data   ),
        .I_ag    ( S_ag_px_d2        ),
        .O_vsync ( S_dehaze_vsync    ),
        .O_hsync ( S_dehaze_hsync    ),
        .O_de    ( S_dehaze_de       ),
        .O_data  ( S_dehaze_data     )
    );

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_dh2_data <= 24'd0;
            S_dh2_de   <= 1'b0;
            S_dh2_vs   <= 1'b1;
            S_dh2_hs   <= 1'b1;
        end else begin
            S_dh2_data <= S_dehaze_data;
            S_dh2_de   <= S_dehaze_de;
            S_dh2_vs   <= S_dehaze_vsync;
            S_dh2_hs   <= S_dehaze_hsync;
        end
    end

    reg S_hm_vsync_d, S_hm_hsync_d;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_hm_vsync_d <= 1'b1;
            S_hm_hsync_d <= 1'b1;
        end else begin
            S_hm_vsync_d <= S_dh2_vs;
            S_hm_hsync_d <= S_dh2_hs;
        end
    end

    gamma_correction #(
        .BLACK_LEVEL  ( 8'd0  ),
        .CHROMA_KEEP  ( 1     ),
        .SAT_BOOST_Q4 ( 8'd16 )
    ) u_gamma (
        .I_clk   ( S_hdmi_pixel_clk    ),
        .I_rst_n ( S_hdmi_rst_n        ),
        .I_de    ( S_dh2_de            ),
        .I_data  ( S_dh2_data          ),
        .O_de    ( S_gamma_de          ),
        .O_data  ( S_gamma_data        )
    );

    enhance #(
        .IMG_WIDTH  ( 1280   ),
        .IMG_HEIGHT ( 720    ),
        .LIFT_SHIFT ( 3      ),
        .SAT_K      ( 3'd2   ),
        .DE_LAG     ( 1      )
    ) u_enhance (
        .I_clk   ( S_hdmi_pixel_clk ),
        .I_rst_n ( S_hdmi_rst_n     ),
        .I_de    ( S_cart_de        ),
        .I_data  ( S_cart_data      ),
        .I_mode  ( S_enh_mode       ),
        .I_edge_th ( S_p_edge_th    ),
        .I_bin_th  ( S_p_bin_th     ),

        .I_lift_shift ( S_p_lift_shift ),
        .I_enh_sat_k  ( S_p_enh_sat_k  ),
        .O_de    ( S_enh_de         ),
        .O_data  ( S_enh_data       )
    );

    cartoonize #(
        .IMG_WIDTH       ( 1280    ),
        .IMG_HEIGHT      ( 720     ),

        .QUANT_HI        ( 7       ),
        .EDGE_DILATE     ( 0       ),
        .EDGE_DARK       ( 1       ),
        .EDGE_SRC        ( 1       ),
        .E_GAIN_S        ( 4       ),
        .K_US_Q4         ( 8'd0    ),
        .CONTRAST_Q4     ( 8'd16   ),
        .BRIGHT_OFF      ( 0       ),
        .PRE_SAT_K       ( 1       ),
        .SAT_K           ( 2       ),
        .SAT_EN          ( 0       ),
        .MONO            ( 0       ),
        .DIAG_MODE       ( 0       ),
        .DE_LAG          ( 0       ),
        .QEN_NR_TH       ( 2       ),
        .K_QEN_Q4        ( 48      ),
        .QEN_MID_Q4      ( 0       ),
        .QEN_DCAP        ( 80      ),
        .CART_DN_Q4      ( 8'd0    ),
        .QEN_MID_US_Q4   ( 8'd0    ),
        .TONE_EN         ( 0       ),
        .TONE_S4         ( 8'd16   ),
        .TONE_TARGET     ( 8'd150  ),
        .TONE_GAIN_MIN_Q8( 9'd154  ),
        .TONE_GAIN_MAX_Q8( 9'd410  ),
        .TONE_IIR_SHIFT  ( 4       )
    ) u_cartoonize (
        .I_clk       ( S_hdmi_pixel_clk ),
        .I_rst_n     ( S_hdmi_rst_n     ),
        .I_de        ( S_gamma_de       ),
        .I_user      ( S_hm_vsync_d & ~S_dh2_vs ),
        .I_last      ( S_hm_hsync_d & ~S_dh2_hs ),
        .I_mode      ( S_cart_mode      ),
        .I_qen       ( S_cart_qen       ),
        .I_ev_gain   ( S_p_ev_gain      ),
        .I_edge_th   ( S_p_cart_edge_th ),

        .I_quant_hi    ( S_p_quant_hi    ),
        .I_k_us_q4     ( S_p_k_us_q4     ),
        .I_sat_k       ( S_p_sat_k       ),
        .I_sat_en      ( S_p_sat_en      ),
        .I_edge_dark   ( S_p_edge_dark   ),
        .I_contrast_q4 ( S_p_contrast_q4 ),
        .I_data      ( S_gamma_data     ),
        .O_de        ( S_cart_de        ),
        .O_user      (                  ),
        .O_last      (                  ),
        .O_data      ( S_cart_data      ),
        .O_y_med     ( S_cart_med       ),
        .O_y_med_tog ( S_cart_med_tog   )
    );

    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),

        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );

    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );

    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    reg S_sw_clear_s1, S_sw_clear_s2;
    reg S_sw_diag_s1,  S_sw_diag_s2;
    reg S_sw_aux_s1,   S_sw_aux_s2;
    reg S_sw_ctr_s1,   S_sw_ctr_s2;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_sw_clear_s1 <= 1'b0;
            S_sw_clear_s2 <= 1'b0;
            S_sw_diag_s1  <= 1'b0;
            S_sw_diag_s2  <= 1'b0;
            S_sw_aux_s1   <= 1'b0;
            S_sw_aux_s2   <= 1'b0;
            S_sw_ctr_s1   <= 1'b0;
            S_sw_ctr_s2   <= 1'b0;
        end
        else begin
            S_sw_clear_s1 <= I_sw_clear;
            S_sw_clear_s2 <= S_sw_clear_s1;
            S_sw_diag_s1  <= I_sw_diag;
            S_sw_diag_s2  <= S_sw_diag_s1;
            S_sw_aux_s1   <= I_sw_aux;
            S_sw_aux_s2   <= S_sw_aux_s1;
            S_sw_ctr_s1   <= I_sw_contour;
            S_sw_ctr_s2   <= S_sw_ctr_s1;
        end
    end

    wire S_sw_clear_sync   = S_sw_clear_s2;
    wire S_sw_contour_sync = S_sw_ctr_s2;

    wire S_tgt_en = S_sw_contour_sync;

    reg S_fd_en;
    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n)          S_fd_en <= 1'b0;
        else if (S_btn_next_long) S_fd_en <= ~S_fd_en;
    end

    wire S_recog_en = S_sw_clear_sync;

    reg S_sw1_d;
    always @(posedge S_hdmi_pixel_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_sw1_d <= 1'b0;
        else          S_sw1_d <= S_recog_en;
    end
    wire S_clr_pulse = S_recog_en && !S_sw1_d;

    wire S_line_en_hw = S_recog_en;
    wire S_contour_en = S_recog_en;

    wire S_dyn_osd_en = S_osd_on;

    wire S_osd_full = S_osd_on &&  S_recog_en;
    wire S_osd_lite = S_osd_on && !S_recog_en;

    wire [7:0] S_diff_th_sw = 8'd10;

    wire [7:0]  S_p_diff_th;
    wire [7:0]  S_p_gray_lo;
    wire [7:0]  S_p_gray_hi;
    wire [7:0]  S_p_proj_th;

    wire [3:0]  S_p_bg_shift;

    wire [7:0]  S_p_fd_th;

    wire [7:0]  S_p_tgt_orange_th;
    wire [15:0] S_p_tgt_min_pix;
    wire [7:0]  S_p_tgt_blk_th;
    wire [7:0]  S_p_tgt_vivid_sat;
    wire [7:0]  S_p_tgt_orange_rmin;
    wire [24:0] S_p_min_amp;
    wire [8:0]  S_p_hold;
    wire [7:0]  S_p_refractory;
    wire [7:0]  S_p_rhythm_tol;
    wire        S_p_clear;
    wire        S_p_any_cmd;
    wire [1:0]  S_p_use_y0;
    wire        S_p_manual;
    wire        S_p_line_en;
    wire        S_p_diff_set;
    wire [7:0]  S_rx_byte;
    wire        S_rx_valid;

    uart_rx #(

        .CLK_FRE   ( 74250000   ),
        .BAUD_RATE ( 115200     )
    ) u_uart_rx (
        .clk            ( S_hdmi_pixel_clk ),
        .rst_n          ( S_hdmi_rst_n     ),
        .rx_data        ( S_rx_byte        ),
        .rx_data_valid  ( S_rx_valid       ),
        .rx_data_ready  ( 1'b1             ),
        .rx_pin         ( I_uart_rx        )
    );

    param_ctrl u_param_ctrl (
        .I_clk        ( S_hdmi_pixel_clk ),
        .I_rst_n      ( S_hdmi_rst_n     ),
        .I_rx_data    ( S_rx_byte        ),
        .I_rx_valid   ( S_rx_valid       ),

        .I_mode       ( S_sport_mode     ),
        .I_sm_use_y0  ( S_sm_use_y0      ),
        .I_sm_hold    ( S_sm_hold        ),
        .I_sm_refr    ( S_sm_refr        ),
        .I_sm_tol     ( S_sm_tol         ),
        .I_sm_min_amp ( S_sm_min_amp     ),
        .O_diff_th    ( S_p_diff_th      ),
        .O_gray_lo    ( S_p_gray_lo      ),
        .O_gray_hi    ( S_p_gray_hi      ),
        .O_proj_th    ( S_p_proj_th      ),
        .O_min_amp    ( S_p_min_amp      ),
        .O_hold       ( S_p_hold         ),
        .O_refractory ( S_p_refractory   ),
        .O_rhythm_tol ( S_p_rhythm_tol   ),
        .O_clear      ( S_p_clear        ),
        .O_use_y0     ( S_p_use_y0       ),
        .O_manual     ( S_p_manual       ),
        .O_line_en    ( S_p_line_en      ),
        .O_edge_th    ( S_p_edge_th      ),
        .O_bin_th     ( S_p_bin_th       ),
        .O_ev_gain    ( S_p_ev_gain      ),
        .O_cart_edge_th( S_p_cart_edge_th),

        .O_quant_hi    ( S_p_quant_hi    ),
        .O_k_us_q4     ( S_p_k_us_q4     ),
        .O_sat_k       ( S_p_sat_k       ),
        .O_sat_en      ( S_p_sat_en      ),
        .O_edge_dark   ( S_p_edge_dark   ),
        .O_contrast_q4 ( S_p_contrast_q4 ),
        .O_lift_shift  ( S_p_lift_shift  ),
        .O_enh_sat_k   ( S_p_enh_sat_k   ),
        .O_bg_shift    ( S_p_bg_shift    ),
        .O_fd_th       ( S_p_fd_th       ),

        .O_tgt_orange_th   ( S_p_tgt_orange_th   ),
        .O_tgt_min_pix     ( S_p_tgt_min_pix     ),
        .O_tgt_blk_th      ( S_p_tgt_blk_th      ),
        .O_tgt_vivid_sat   ( S_p_tgt_vivid_sat   ),
        .O_tgt_orange_rmin ( S_p_tgt_orange_rmin ),
        .O_diff_set   ( S_p_diff_set     ),
        .O_last_byte  (                  ),
        .O_last_pulse (                  ),
        .O_any_cmd    ( S_p_any_cmd      )
    );

    reg [27:0] S_led_rx_cnt;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n)
            S_led_rx_cnt <= 28'd0;
        else if (S_rx_valid)
            S_led_rx_cnt <= 28'd148500000;
        else if (S_led_rx_cnt != 28'd0)
            S_led_rx_cnt <= S_led_rx_cnt - 28'd1;
    end

    reg [27:0] S_led_parsed_cnt;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n)
            S_led_parsed_cnt <= 28'd0;
        else if (S_p_any_cmd)
            S_led_parsed_cnt <= 28'd148500000;
        else if (S_led_parsed_cnt != 28'd0)
            S_led_parsed_cnt <= S_led_parsed_cnt - 28'd1;
    end

    reg [25:0] S_led_blink;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) S_led_blink <= 26'd0;
        else               S_led_blink <= S_led_blink + 26'd1;
    end
    wire W_led_blink = S_led_blink[25];

    assign O_led[0] = (S_led_rx_cnt != 28'd0);

    assign O_led[1] = (S_led_parsed_cnt != 28'd0);

    assign O_led[2] = (S_disp_mode == 4'd5);

    assign O_led[3] = W_led_blink;

    wire [7:0] S_diff_th = S_p_diff_set ? S_p_diff_th : S_diff_th_sw;

    wire S_clear_all = S_clr_pulse | S_p_clear;

    wire        S_mot_valid;
    wire [16:0] S_mot_area;
    wire [24:0] S_mot_sy;
    wire [24:0] S_mot_sx;
    wire [29:0] S_mot_sx2;
    wire [29:0] S_mot_sy2;
    wire [ 8:0] S_mot_x0;
    wire [ 8:0] S_mot_x1;
    wire [ 7:0] S_mot_y0;
    wire [ 7:0] S_mot_y1;

    wire        S_contour_valid;
    wire [6:0]  S_contour_idx;
    wire [7:0]  S_contour_min;
    wire [7:0]  S_contour_max;

    wire [23:0] S_bcd_amp;
    wire [23:0] S_bcd_pix;
    wire [23:0] S_bcd_raw;

    wire [23:0] S_bcd_cx;
    wire [23:0] S_bcd_cy;

    wire [7:0]  S_mot_cx;
    wire [6:0]  S_mot_cy;

    motion_stats #(
        .IMG_WIDTH  ( 1280   ),
        .IMG_HEIGHT ( 720    ),

        .DS_LOG2    ( 3      ),

        .BG_SHIFT   ( 3      ),

        .BG_SHIFT   ( 5      ),
        .DE_LAG     ( 2      )
    ) u_motion_stats (
        .I_clk   ( S_hdmi_pixel_clk    ),
        .I_rst_n ( S_hdmi_rst_n        ),
        .I_de    ( S_hdmi_window_rd_en ),
        .I_data  ( S_video_rd_data     ),
        .I_diff_th ( S_diff_th         ),
        .I_gray_lo ( S_p_gray_lo       ),
        .I_gray_hi ( S_p_gray_hi       ),
        .I_proj_th ( S_p_proj_th       ),
        .I_bg_shift ( S_p_bg_shift      ),
        .I_fd_en    ( S_fd_en            ),
        .I_fd_th    ( S_p_fd_th          ),
        .O_valid ( S_mot_valid         ),
        .O_area  ( S_mot_area          ),
        .O_sy    ( S_mot_sy            ),
        .O_sx    ( S_mot_sx            ),
        .O_sx2   ( S_mot_sx2           ),
        .O_sy2   ( S_mot_sy2           ),
        .O_x0    ( S_mot_x0            ),
        .O_x1    ( S_mot_x1            ),
        .O_y0    ( S_mot_y0            ),
        .O_y1    ( S_mot_y1            ),

        .O_row_valid ( S_contour_valid ),
        .O_row_idx   ( S_contour_idx   ),
        .O_row_min   ( S_contour_min   ),
        .O_row_max   ( S_contour_max   )
    );

    localparam [8:0] BB_MAX_STEP = 9'd40;
    localparam [2:0] BB_MAX_REJ  = 3'd4;

    localparam [7:0] BB_HOLD_MISS = 8'd60;

    function [8:0] F_absd9;
        input [8:0] a, b;
        begin
            F_absd9 = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    function [7:0] F_absd8;
        input [7:0] a, b;
        begin
            F_absd8 = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    wire W_bb_fg_ok = S_mot_valid &&
                      (S_mot_y0 != 8'hFF) &&
                      (S_mot_x0 <= S_mot_x1) &&
                      (S_mot_y0 <= S_mot_y1);

    wire W_bb_cur_valid = (S_bbf_x0 <= S_bbf_x1) && (S_bbf_y0 <= S_bbf_y1);

    wire W_bb_jump_ok =
        (F_absd9(S_mot_x0, S_bbf_x0) <= BB_MAX_STEP) &&
        (F_absd9(S_mot_x1, S_bbf_x1) <= BB_MAX_STEP) &&
        (F_absd8(S_mot_y0, S_bbf_y0) <= BB_MAX_STEP[7:0]) &&
        (F_absd8(S_mot_y1, S_bbf_y1) <= BB_MAX_STEP[7:0]);

    reg [7:0] S_bb_miss;
    reg [2:0] S_bb_rej;
    reg [8:0] S_bbf_x0, S_bbf_x1;
    reg [7:0] S_bbf_y0, S_bbf_y1;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_bb_miss <= 8'd0;
            S_bb_rej  <= 3'd0;
            S_bbf_x0  <= 9'h1FF;
            S_bbf_x1  <= 9'd0;
            S_bbf_y0  <= 8'hFF;
            S_bbf_y1  <= 8'd0;
        end
        else if (S_mot_valid) begin
            if (W_bb_fg_ok) begin

                if ((!W_bb_cur_valid) || W_bb_jump_ok || (S_bb_rej >= BB_MAX_REJ)) begin

                    S_bbf_x0  <= S_mot_x0;
                    S_bbf_x1  <= S_mot_x1;
                    S_bbf_y0  <= S_mot_y0;
                    S_bbf_y1  <= S_mot_y1;
                    S_bb_rej  <= 3'd0;
                end
                else begin

                    S_bb_rej  <= S_bb_rej + 3'd1;
                end
                S_bb_miss <= 8'd0;
            end
            else begin

                S_bb_rej <= 3'd0;
                if (S_bb_miss != 8'hFF) S_bb_miss <= S_bb_miss + 8'd1;
                if (S_bb_miss >= BB_HOLD_MISS) begin

                    S_bbf_x0 <= 9'h1FF;
                    S_bbf_x1 <= 9'd0;
                    S_bbf_y0 <= 8'hFF;
                    S_bbf_y1 <= 8'd0;
                end
            end

        end
    end

    wire [8:0] S_bb_x0 = S_bbf_x0;
    wire [8:0] S_bb_x1 = S_bbf_x1;
    wire [7:0] S_bb_y0 = S_bbf_y0;
    wire [7:0] S_bb_y1 = S_bbf_y1;

    wire [23:0] S_jump_bcd;
    wire [23:0] S_jump_bin;
    wire [23:0] S_jump_raw;
    wire [24:0] S_jc_peak_hi;
    wire [24:0] S_jc_peak_lo;
    wire [24:0] S_jc_amp;
    wire        S_jc_in_air;
    wire [ 9:0] S_jump_interval;
    wire [11:0] S_speed_x10;
    wire [11:0] S_speed_bcd;

    motion_report u_motion_report (
        .I_clk       ( S_hdmi_pixel_clk ),
        .I_rst_n     ( S_hdmi_rst_n     ),
        .I_valid     ( S_mot_valid      ),
        .I_area      ( S_mot_area       ),
        .I_sy        ( S_mot_sy         ),
        .I_sx        ( S_mot_sx         ),
        .I_sx2       ( S_mot_sx2        ),
        .I_sy2       ( S_mot_sy2        ),
        .I_y0        ( S_mot_y0         ),
        .I_y1        ( S_mot_y1         ),
        .I_x0        ( S_mot_x0         ),
        .I_x1        ( S_mot_x1         ),
        .I_val_amp   ( S_jc_amp         ),
        .I_val_raw   ( S_jump_raw       ),
        .O_uart_tx   ( O_uart_tx        ),
        .O_bcd_amp   ( S_bcd_amp        ),
        .O_bcd_pix   ( S_bcd_pix        ),
        .O_bcd_raw   ( S_bcd_raw        ),
        .O_bcd_cx    ( S_bcd_cx         ),
        .O_bcd_cy    ( S_bcd_cy         ),
        .O_cx        ( S_mot_cx         ),
        .O_cy        ( S_mot_cy         )
    );

    localparam [16:0] Y0_AREA_MIN = 17'd16;

    wire W_y0_fg_ok = S_mot_valid &&
                      (S_bb_y0 != 8'hFF) &&
                      (S_bb_x0 <= S_bb_x1) &&
                      (S_mot_area >= Y0_AREA_MIN);

    reg [7:0] S_y0_hold;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n)
            S_y0_hold <= 8'd45;

        else if (W_y0_fg_ok)
            S_y0_hold <= S_bb_y0;
    end

    wire [24:0] S_head_src = {17'b0, S_y0_hold} << 7;

    wire [1:0]  S_src_sel      = S_p_manual ? S_p_use_y0   : S_sm_use_y0;
    wire [7:0]  S_hold_final   = S_p_manual ? S_p_hold     : S_sm_hold;
    wire [7:0]  S_refr_final   = S_p_manual ? S_p_refractory : S_sm_refr;
    wire [7:0]  S_tol_final    = S_p_manual ? S_p_rhythm_tol : S_sm_tol;
    wire [24:0] S_minamp_final = S_p_manual ? S_p_min_amp  : S_sm_min_amp;

    reg [7:0] S_hold_final_r;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) S_hold_final_r <= 8'd0;
        else              S_hold_final_r <= S_hold_final;
    end

    wire [9:0]  S_xc_sum = {1'b0, S_bb_x0} + {1'b0, S_bb_x1};
    wire [8:0]  S_xc     = S_xc_sum[9:1];
    wire [24:0] S_xc_src = {16'b0, S_xc} << 7;

    wire [24:0] S_count_src = (S_src_sel == 2'd0) ? S_mot_sy :
                              (S_src_sel == 2'd1) ? S_head_src : S_xc_src;

    localparam [2:0] LPF_K = 3'd3;

    reg  [8:0] S_xc_lpf;

    wire W_srv_follow_tgt = S_recog_en && S_sw_diag_s2 && S_sw_aux_s2 && S_tgt_en;

    wire [9:0]  W_tgt_cx_sum = {1'b0, S_tgt_x0} + {1'b0, S_tgt_x1};
    wire [8:0]  W_tgt_cx     = W_tgt_cx_sum[9:1];

    wire [8:0]  W_lpf_src = W_srv_follow_tgt ? W_tgt_cx : S_xc;
    wire        W_lpf_en  = S_mot_valid &&
                            (W_srv_follow_tgt ? S_tgt_valid : W_bb_cur_valid);

    wire [8:0] W_lpf_diff = (W_lpf_src > S_xc_lpf) ? (W_lpf_src - S_xc_lpf)
                                                  : (S_xc_lpf - W_lpf_src);

    wire [8:0] W_lpf_step = ((W_lpf_diff >> LPF_K) == 9'd0) ? 9'd1
                                                           : (W_lpf_diff >> LPF_K);

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n)
            S_xc_lpf <= 9'd80;
        else if (W_lpf_en) begin
            if (W_lpf_src > S_xc_lpf)      S_xc_lpf <= S_xc_lpf + W_lpf_step;
            else if (W_lpf_src < S_xc_lpf) S_xc_lpf <= S_xc_lpf - W_lpf_step;
        end
    end

    localparam [8:0]  SRV_ENTER   = 9'd40;
    localparam [7:0]  SRV_CONF    = 8'd9;
    localparam [7:0]  HOLD_FRMS   = 8'd120;
    localparam [17:0] SRV_DUTY_MIN = 18'd37_500;
    localparam [17:0] SRV_DUTY_MAX = 18'd187_500;

    wire [8:0] W_srv_mag = (S_xc_lpf >= 9'd80) ? (S_xc_lpf - 9'd80)
                                               : (9'd80 - S_xc_lpf);

    reg        S_srv_track;
    reg [7:0]  S_srv_cnt;
    reg [7:0]  S_hold_cnt;
    reg [17:0] S_srv_cmd;

    wire [17:0] W_srv_delta = ({9'd0, W_srv_mag} << 8)
                            + ({9'd0, W_srv_mag} << 7)
                            + ({9'd0, W_srv_mag} << 5);

    wire        W_srv_right = (S_xc_lpf > 9'd80);

    wire [17:0] W_srv_dec = (S_srv_cmd < (SRV_DUTY_MIN + W_srv_delta))
                          ? SRV_DUTY_MIN : (S_srv_cmd - W_srv_delta);
    wire [17:0] W_srv_inc = ((S_srv_cmd + W_srv_delta) > SRV_DUTY_MAX)
                          ? SRV_DUTY_MAX : (S_srv_cmd + W_srv_delta);
    wire [17:0] W_srv_cmd_nxt = W_srv_right ? W_srv_dec : W_srv_inc;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_srv_track <= 1'b0;
            S_srv_cnt   <= 8'd0;
            S_hold_cnt  <= 8'd0;
            S_srv_cmd   <= 18'd112_500;
        end
        else if (S_mot_valid) begin
            if (!S_srv_track) begin

                if (W_srv_mag >= SRV_ENTER) begin
                    if (S_srv_cnt < 8'd10) S_srv_cnt <= S_srv_cnt + 8'd1;
                    if (S_srv_cnt >= SRV_CONF) begin
                        S_srv_cmd   <= W_srv_cmd_nxt;
                        S_srv_track <= 1'b1;
                        S_hold_cnt  <= 8'd0;
                        S_srv_cnt   <= 8'd0;
                    end
                end
                else begin
                    S_srv_cnt <= 8'd0;
                end
            end
            else begin

                if (S_hold_cnt < HOLD_FRMS) begin
                    S_hold_cnt <= S_hold_cnt + 8'd1;
                end
                else begin

                    S_srv_track <= 1'b0;
                    S_srv_cnt   <= 8'd0;
                end
            end
        end
    end

    localparam        SRV_SELFTEST = 1'b0;
    localparam [9:0]  TEST_FRAMES  = 10'd320;

    reg [20:0] S_test_div;
    reg [9:0]  S_test_cnt;
    reg [17:0] S_test_duty;
    reg        S_test_dir;

    wire W_test_tick = (S_test_div == 21'd1_249_999);
    wire W_test_on   = SRV_SELFTEST && (S_test_cnt != TEST_FRAMES);

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_test_div  <= 21'd0;
            S_test_cnt  <= 10'd0;
            S_test_duty <= 18'd112_500;
            S_test_dir  <= 1'b0;
        end
        else begin
            S_test_div <= W_test_tick ? 21'd0 : (S_test_div + 21'd1);

            if (W_test_on && W_test_tick) begin
                S_test_cnt <= S_test_cnt + 10'd1;

                if (!S_test_dir) begin
                    if (S_test_duty >= 18'd185_500) S_test_dir  <= 1'b1;
                    else                            S_test_duty <= S_test_duty + 18'd2_000;
                end
                else begin
                    if (S_test_duty <= 18'd39_500)  S_test_dir  <= 1'b0;
                    else                            S_test_duty <= S_test_duty - 18'd2_000;
                end
            end
        end
    end

    wire [17:0] W_srv_duty  = W_test_on ? S_test_duty : S_srv_cmd;
    wire        W_srv_valid = W_test_on ? W_test_tick : (S_mot_valid && S_srv_track);

    wire        W_srv_en    = S_recog_en && S_sw_aux_s2;

    wire [17:0] S_srv_duty;

    servo_pwm u_servo_pwm (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_en       ( W_srv_en         ),
        .I_valid    ( W_srv_valid      ),
        .I_duty_tgt ( W_srv_duty       ),
        .O_pwm      ( O_servo_pwm      ),
        .O_duty     ( S_srv_duty       )
    );

    reg [17:0] S_dv_num;
    reg [18:0] S_dv_rem;
    reg [17:0] S_dv_q;
    reg [4:0]  S_dv_cnt;
    reg [7:0]  S_pwm_cs;
    wire [18:0] W_dv_try = {S_dv_rem[17:0], S_dv_num[17]};
    wire        W_dv_ge  = (W_dv_try >= 19'd750);

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_dv_num <= 18'd0;
            S_dv_rem <= 19'd0;
            S_dv_q   <= 18'd0;
            S_dv_cnt <= 5'd0;
            S_pwm_cs <= 8'd150;
        end
        else if (S_dv_cnt == 5'd18) begin
            S_pwm_cs <= S_dv_q[7:0];
            S_dv_num <= S_srv_duty;
            S_dv_rem <= 19'd0;
            S_dv_q   <= 18'd0;
            S_dv_cnt <= 5'd0;
        end
        else begin
            S_dv_cnt <= S_dv_cnt + 5'd1;
            S_dv_num <= {S_dv_num[16:0], 1'b0};
            S_dv_rem <= W_dv_ge ? (W_dv_try - 19'd750) : W_dv_try;
            S_dv_q   <= {S_dv_q[16:0], W_dv_ge};
        end
    end

    wire [17:0] W_ang_off = S_srv_duty - 18'd37_500;
    wire [8:0]  W_ang_raw = {1'b0, (W_ang_off >> 10)} + {2'b0, (W_ang_off >> 12)};
    wire [8:0]  W_ang     = (W_ang_raw > 9'd180) ? 9'd180 : W_ang_raw;
    wire [3:0]  W_ang_h   = (W_ang >= 9'd100) ? 4'd1 : 4'd0;
    wire [8:0]  W_ang_r   = W_ang - {5'd0, W_ang_h} * 9'd100;

    wire [3:0]  W_pwm_h   = (S_pwm_cs >= 8'd200) ? 4'd2 : (S_pwm_cs >= 8'd100) ? 4'd1 : 4'd0;
    wire [7:0]  W_pwm_r   = S_pwm_cs - {4'd0, W_pwm_h} * 8'd100;

    reg [3:0]  S_ang_h, S_pwm_h;
    reg [8:0]  S_ang_r;
    reg [7:0]  S_pwm_r;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_ang_h <= 4'd0;  S_pwm_h <= 4'd0;
            S_ang_r <= 9'd0;  S_pwm_r <= 8'd0;
        end else begin
            S_ang_h <= W_ang_h;  S_pwm_h <= W_pwm_h;
            S_ang_r <= W_ang_r;  S_pwm_r <= W_pwm_r;
        end
    end

    wire [7:0]  W_pwm_t = ({8'd0, S_pwm_r} * 16'd205) >> 11;
    wire [3:0]  W_pwm_o = S_pwm_r - W_pwm_t * 8'd10;
    wire [7:0]  W_ang_t = ({8'd0, S_ang_r[7:0]} * 16'd205) >> 11;
    wire [3:0]  W_ang_o = S_ang_r[7:0] - W_ang_t * 8'd10;

    reg [3:0] S_pwm_t, S_pwm_o, S_ang_t, S_ang_o;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_pwm_t <= 4'd0;  S_pwm_o <= 4'd0;
            S_ang_t <= 4'd0;  S_ang_o <= 4'd0;
        end else begin
            S_pwm_t <= W_pwm_t[3:0];  S_pwm_o <= W_pwm_o;
            S_ang_t <= W_ang_t[3:0];  S_ang_o <= W_ang_o;
        end
    end

    jump_counter #(

        .FAST_SHIFT  ( 5         )

    ) u_jump_counter (
        .I_clk       ( S_hdmi_pixel_clk ),
        .I_rst_n     ( S_hdmi_rst_n     ),
        .I_valid     ( S_mot_valid      ),
        .I_sy        ( S_count_src      ),
        .I_clear     ( S_clear_all      ),
        .I_hold      ( S_hold_final_r   ),
        .I_min_amp   ( S_minamp_final   ),
        .I_refractory( S_refr_final     ),
        .I_rhythm_tol( S_tol_final      ),
        .O_count_bcd ( S_jump_bcd       ),
        .O_count_bin ( S_jump_bin       ),
        .O_raw_events( S_jump_raw       ),
        .O_interval  ( S_jump_interval  ),
        .O_peak_hi   ( S_jc_peak_hi     ),
        .O_peak_lo   ( S_jc_peak_lo     ),
        .O_amp       ( S_jc_amp         ),
        .O_in_air    ( S_jc_in_air      )
    );

    speed_calc u_speed_calc (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_valid    ( S_mot_valid      ),
        .I_interval ( S_jump_interval  ),
        .I_raw      ( S_jump_raw       ),
        .O_bcd      ( S_speed_bcd      )
    );

    wire [7:0] S_line_up;
    wire [7:0] S_line_dn;
    wire [7:0] S_line_amp;

    line_tracker #(

        .FAST_SHIFT ( 5      ),
        .MISS_HOLD  ( 8'd180 ),
        .MAX_ROW    ( 8'd89   )
    ) u_line_tracker (
        .I_clk    ( S_hdmi_pixel_clk ),
        .I_rst_n  ( S_hdmi_rst_n     ),
        .I_valid  ( S_mot_valid      ),

        .I_y0     ( S_y0_hold        ),
        .I_fg_ok  ( W_y0_fg_ok       ),
        .I_hold   ( S_hold_final_r   ),
        .O_line_up( S_line_up        ),
        .O_line_dn( S_line_dn        ),
        .O_amp    ( S_line_amp       )
    );

    wire        S_tgt_or_valid;
    wire [8:0]  S_tgt_or_x0, S_tgt_or_x1;
    wire [7:0]  S_tgt_or_y0, S_tgt_or_y1;
    wire        S_tgt_vi_valid;
    wire [8:0]  S_tgt_vi_x0, S_tgt_vi_x1;
    wire [7:0]  S_tgt_vi_y0, S_tgt_vi_y1;
    wire        S_tgt_dk_valid;
    wire [8:0]  S_tgt_dk_x0, S_tgt_dk_x1;
    wire [7:0]  S_tgt_dk_y0, S_tgt_dk_y1;
    wire [1:0]  S_tgt_class;

    target_detect u_target_detect (
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( S_hdmi_rst_n     ),

        .I_de          ( S_gamma_de       ),
        .I_data        ( S_gamma_data     ),
        .I_orange_th   ( S_p_tgt_orange_th   ),
        .I_orange_rmin ( S_p_tgt_orange_rmin ),
        .I_blk_th      ( S_p_tgt_blk_th      ),
        .I_vivid_sat   ( S_p_tgt_vivid_sat   ),
        .I_min_pix     ( S_p_tgt_min_pix     ),
        .O_orange_valid ( S_tgt_or_valid ),
        .O_orange_x0    ( S_tgt_or_x0 ), .O_orange_x1 ( S_tgt_or_x1 ),
        .O_orange_y0    ( S_tgt_or_y0 ), .O_orange_y1 ( S_tgt_or_y1 ),
        .O_vivid_valid  ( S_tgt_vi_valid ),
        .O_vivid_x0     ( S_tgt_vi_x0 ), .O_vivid_x1 ( S_tgt_vi_x1 ),
        .O_vivid_y0     ( S_tgt_vi_y0 ), .O_vivid_y1 ( S_tgt_vi_y1 ),
        .O_dark_valid   ( S_tgt_dk_valid ),
        .O_dark_x0      ( S_tgt_dk_x0 ), .O_dark_x1 ( S_tgt_dk_x1 ),
        .O_dark_y0      ( S_tgt_dk_y0 ), .O_dark_y1 ( S_tgt_dk_y1 ),
        .O_win_class    ( S_tgt_class )
    );

    wire        S_tgt_valid = S_tgt_en && (S_tgt_or_valid | S_tgt_vi_valid | S_tgt_dk_valid);
    wire [8:0]  S_tgt_x0 = S_tgt_or_valid ? S_tgt_or_x0 : (S_tgt_vi_valid ? S_tgt_vi_x0 : S_tgt_dk_x0);
    wire [8:0]  S_tgt_x1 = S_tgt_or_valid ? S_tgt_or_x1 : (S_tgt_vi_valid ? S_tgt_vi_x1 : S_tgt_dk_x1);
    wire [7:0]  S_tgt_y0 = S_tgt_or_valid ? S_tgt_or_y0 : (S_tgt_vi_valid ? S_tgt_vi_y0 : S_tgt_dk_y0);
    wire [7:0]  S_tgt_y1 = S_tgt_or_valid ? S_tgt_or_y1 : (S_tgt_vi_valid ? S_tgt_vi_y1 : S_tgt_dk_y1);

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_rd_en         ( S_hdmi_de          ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),

        .I_bcd_cnt       ( S_jump_bcd         ),
        .I_bcd_amp       ( S_bcd_amp          ),
        .I_bcd_pix       ( S_bcd_pix          ),
        .I_bcd_raw       ( S_bcd_raw          ),
        .I_speed_bcd     ( S_speed_bcd        ),

        .I_bb_x0         ( S_bb_x0            ),
        .I_bb_x1         ( S_bb_x1            ),
        .I_bb_y0         ( S_bb_y0            ),
        .I_bb_y1         ( S_bb_y1            ),

        .I_tgt_valid     ( S_tgt_valid        ),
        .I_tgt_x0        ( S_tgt_x0           ),
        .I_tgt_x1        ( S_tgt_x1           ),
        .I_tgt_y0        ( S_tgt_y0           ),
        .I_tgt_y1        ( S_tgt_y1           ),
        .I_cx            ( S_mot_cx           ),
        .I_cy            ( S_mot_cy           ),
        .I_row_valid     ( S_contour_valid    ),
        .I_row_idx       ( S_contour_idx      ),
        .I_row_min       ( S_contour_min      ),
        .I_row_max       ( S_contour_max      ),
        .I_contour_sel   ( S_sw_diag_s2      ),
        .I_contour_en    ( S_contour_en       ),

        .I_line_up       ( S_line_up          ),
        .I_line_dn       ( S_line_dn          ),

        .I_extra_en      ( S_p_line_en & S_line_en_hw ),

        .I_sport_mode    ( S_sport_mode       ),
        .I_disp_mode     ( S_disp_mode        ),
        .I_lat_frames    ( S_lat_frames       ),
        .I_dyn_osd_en    ( S_dyn_osd_en       ),

        .I_lat_en        ( 1'b1              ),

        .I_osd_full      ( S_osd_full        ),
        .I_ae_mode       ( S_ae_mode         ),

        .I_gimbal_on     ( S_sw_aux_s2       ),
        .I_bcd_cx        ( S_bcd_cx          ),
        .I_bcd_cy        ( S_bcd_cy          ),
        .I_pwm_h         ( S_pwm_h           ),
        .I_pwm_t         ( S_pwm_t           ),
        .I_pwm_o         ( S_pwm_o           ),
        .I_ang_h         ( S_ang_h           ),
        .I_ang_t         ( S_ang_t           ),
        .I_ang_o         ( S_ang_o           ),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_enh_de          ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_enh_data        ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );

endmodule

module speed_calc (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_valid,
    input  wire [9:0]  I_interval,
    input  wire [23:0] I_raw,
    output reg  [11:0] O_bcd
);

    localparam [12:0] DIVIDEND = 13'd5520;

    reg [3:0]  it;
    reg [13:0] rem;
    reg [11:0] quo;
    reg [11:0] bcd;
    reg [1:0]  st;

    wire [9:0]  iv      = (I_interval < 10'd10) ? 10'd10 : I_interval;
    wire [13:0] div_ext = {4'b0, iv};

    reg [23:0] raw_last;
    reg [9:0]  idle;
    wire       raw_chg = (I_raw != raw_last);
    localparam [9:0] IDLE_CLR = 10'd600;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            raw_last <= 24'd0;
            idle     <= 10'd0;
        end
        else if (I_valid) begin
            raw_last <= I_raw;
            if (raw_chg)
                idle <= 10'd0;
            else if (idle != 10'h3FF)
                idle <= idle + 10'd1;
        end
    end
    wire [13:0] rem_sh  = {rem[12:0], DIVIDEND[12 - it]};
    wire        ge      = (rem_sh >= div_ext);
    wire [11:0] quo_nx  = ge ? {quo[10:0], 1'b1} : {quo[10:0], 1'b0};

    wire [3:0]  b_hi3 = (bcd[11:8] >= 4'd5) ? (bcd[11:8] + 4'd3) : bcd[11:8];
    wire [3:0]  b_md3 = (bcd[7:4]  >= 4'd5) ? (bcd[7:4]  + 4'd3) : bcd[7:4];
    wire [3:0]  b_lo3 = (bcd[3:0]  >= 4'd5) ? (bcd[3:0]  + 4'd3) : bcd[3:0];
    wire [11:0] bcd_sh = {b_hi3, b_md3, b_lo3} << 1;
    wire [11:0] bcd_nx = bcd_sh | {11'b0, quo[11 - it]};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            it  <= 4'd0;
            rem <= 14'd0;
            quo <= 12'd0;
            bcd <= 12'd0;
            st  <= 2'd0;
            O_bcd <= 12'd0;
        end
        else begin
            case (st)
                2'd0: begin
                    if (I_valid) begin
                        if (idle >= IDLE_CLR) begin
                            O_bcd <= 12'd0;
                        end
                        else begin
                            it  <= 4'd0;
                            rem <= 14'd0;
                            quo <= 12'd0;
                            st  <= 2'd1;
                        end
                    end
                end
                2'd1: begin
                    rem <= ge ? (rem_sh - div_ext) : rem_sh;
                    quo <= quo_nx;
                    if (it == 4'd12) begin
                        it  <= 4'd0;
                        bcd <= 12'd0;
                        st  <= 2'd2;
                    end
                    else begin
                        it <= it + 4'd1;
                    end
                end
                2'd2: begin
                    bcd <= bcd_nx;
                    if (it == 4'd11) begin
                        it    <= 4'd0;
                        O_bcd <= bcd_nx;
                        st    <= 2'd0;
                    end
                    else begin
                        it <= it + 4'd1;
                    end
                end
                default: st <= 2'd0;
            endcase
        end
    end

endmodule

module dehaze #(
    parameter [7:0] BLACK_LEVEL = 8'd16,
    parameter BL_GAIN_TRACK = 1'b0
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire [15:0] I_ag,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg  [23:0] O_data
);

    wire [16:0] bl_mul  = {1'b0, I_ag} + {I_ag, 5'b0};
    wire [16:0] bl_calc = (bl_mul + 17'd1024) >> 11;
    reg  [7:0]  bl_eff;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)                              bl_eff <= BLACK_LEVEL;
        else if (BL_GAIN_TRACK != 0 && bl_calc > {9'd0, BLACK_LEVEL})
                                                  bl_eff <= bl_calc[7:0];
        else                                       bl_eff <= BLACK_LEVEL;
    end

    function [7:0] f_dehaze;
        input [7:0] x;
        input [7:0] bl;
        reg [8:0] sub;
        reg [9:0] norm;
        begin
            sub  = (x > bl) ? ({1'b0, x} - {1'b0, bl}) : 9'd0;
            norm = {1'b0, sub} + {1'b0, sub[8:4]};
            f_dehaze = (norm > 10'd255) ? 8'd255 : norm[7:0];
        end
    endfunction

    wire [7:0] d_r = f_dehaze(I_data[23:16], bl_eff);
    wire [7:0] d_g = f_dehaze(I_data[15: 8], bl_eff);
    wire [7:0] d_b = f_dehaze(I_data[ 7: 0], bl_eff);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_vsync <= 1'b1;
            O_hsync <= 1'b1;
            O_de    <= 1'b0;
            O_data  <= 24'd0;
        end
        else begin
            O_vsync <= I_vsync;
            O_hsync <= I_hsync;
            O_de    <= I_de;
            O_data  <= { d_r, d_g, d_b };
        end
    end

endmodule
