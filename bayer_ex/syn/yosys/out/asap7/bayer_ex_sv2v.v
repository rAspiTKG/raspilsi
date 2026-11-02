module BAYER_EX_PIXCOR (
	clk,
	rst_n,
	i_en,
	i_cfg,
	i_vld,
	i_data,
	o_vld,
	o_data
);
	reg _sv2v_0;
	input wire clk;
	input wire rst_n;
	input wire i_en;
	localparam signed [31:0] BAYER_EX_PKG_GAIN_W = 16;
	localparam signed [31:0] BAYER_EX_PKG_PIX_W = 14;
	input wire [122:0] i_cfg;
	input wire i_vld;
	localparam signed [31:0] BAYER_EX_PKG_BLK_X = 4;
	localparam signed [31:0] BAYER_EX_PKG_BLK_Y = 2;
	input wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] i_data;
	output wire o_vld;
	output wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] o_data;
	localparam signed [31:0] MW = BAYER_EX_PKG_PIX_W + BAYER_EX_PKG_GAIN_W;
	localparam signed [31:0] BAYER_EX_PKG_GAIN_FRAC = 12;
	localparam signed [31:0] TW = (MW - BAYER_EX_PKG_GAIN_FRAC) + 1;
	reg r_vld1;
	reg [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] r_data1;
	reg r_vld2;
	reg [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] r_data2;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 2) - 1:0] s_site;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1:0] s_lvl;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 16) - 1:0] s_gain;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1:0] s_q1;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * MW) - 1:0] s_mul;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * TW) - 1:0] s_t;
	reg [((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1:0] s_q2;
	function automatic [1:0] BAYER_EX_PKG_f_site;
		input reg [1:0] phase;
		input reg ypar;
		input reg xpar;
		BAYER_EX_PKG_f_site = {ypar ^ phase[1], xpar ^ phase[0]};
	endfunction
	function automatic signed [0:0] sv2v_cast_1_signed;
		input reg signed [0:0] inp;
		sv2v_cast_1_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] y;
			for (y = 0; y < BAYER_EX_PKG_BLK_Y; y = y + 1)
				begin : sv2v_autoblock_2
					reg signed [31:0] x;
					for (x = 0; x < BAYER_EX_PKG_BLK_X; x = x + 1)
						begin
							s_site[((y * BAYER_EX_PKG_BLK_X) + x) * 2+:2] = BAYER_EX_PKG_f_site(i_cfg[121-:2], sv2v_cast_1_signed(y), sv2v_cast_1_signed(x));
							case (s_site[((y * BAYER_EX_PKG_BLK_X) + x) * 2+:2])
								2'd0: begin
									s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_cfg[64+:BAYER_EX_PKG_PIX_W];
									s_gain[((y * BAYER_EX_PKG_BLK_X) + x) * 16+:16] = i_cfg[0+:BAYER_EX_PKG_GAIN_W];
								end
								2'd1: begin
									s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_cfg[78+:BAYER_EX_PKG_PIX_W];
									s_gain[((y * BAYER_EX_PKG_BLK_X) + x) * 16+:16] = i_cfg[16+:BAYER_EX_PKG_GAIN_W];
								end
								2'd2: begin
									s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_cfg[92+:BAYER_EX_PKG_PIX_W];
									s_gain[((y * BAYER_EX_PKG_BLK_X) + x) * 16+:16] = i_cfg[32+:BAYER_EX_PKG_GAIN_W];
								end
								default: begin
									s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_cfg[106+:BAYER_EX_PKG_PIX_W];
									s_gain[((y * BAYER_EX_PKG_BLK_X) + x) * 16+:16] = i_cfg[48+:BAYER_EX_PKG_GAIN_W];
								end
							endcase
						end
				end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_3
			reg signed [31:0] y;
			for (y = 0; y < BAYER_EX_PKG_BLK_Y; y = y + 1)
				begin : sv2v_autoblock_4
					reg signed [31:0] x;
					for (x = 0; x < BAYER_EX_PKG_BLK_X; x = x + 1)
						if (i_cfg[122])
							s_q1[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_data[(((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - ((((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - (((y * BAYER_EX_PKG_BLK_X) + x) * 14))+:14];
						else if (i_data[(((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - ((((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - (((y * BAYER_EX_PKG_BLK_X) + x) * 14))+:14] > s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14])
							s_q1[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = i_data[(((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - ((((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - (((y * BAYER_EX_PKG_BLK_X) + x) * 14))+:14] - s_lvl[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14];
						else
							s_q1[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = 1'sb0;
				end
		end
	end
	localparam signed [31:0] BAYER_EX_PKG_PIX_MAX = 16383;
	function automatic [MW - 1:0] sv2v_cast_73DDD;
		input reg [MW - 1:0] inp;
		sv2v_cast_73DDD = inp;
	endfunction
	function automatic signed [MW - 1:0] sv2v_cast_73DDD_signed;
		input reg signed [MW - 1:0] inp;
		sv2v_cast_73DDD_signed = inp;
	endfunction
	function automatic [TW - 1:0] sv2v_cast_C1BC4;
		input reg [TW - 1:0] inp;
		sv2v_cast_C1BC4 = inp;
	endfunction
	function automatic signed [TW - 1:0] sv2v_cast_C1BC4_signed;
		input reg signed [TW - 1:0] inp;
		sv2v_cast_C1BC4_signed = inp;
	endfunction
	function automatic signed [13:0] sv2v_cast_14_signed;
		input reg signed [13:0] inp;
		sv2v_cast_14_signed = inp;
	endfunction
	function automatic [13:0] sv2v_cast_14;
		input reg [13:0] inp;
		sv2v_cast_14 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_5
			reg signed [31:0] y;
			for (y = 0; y < BAYER_EX_PKG_BLK_Y; y = y + 1)
				begin : sv2v_autoblock_6
					reg signed [31:0] x;
					for (x = 0; x < BAYER_EX_PKG_BLK_X; x = x + 1)
						begin
							s_mul[((y * BAYER_EX_PKG_BLK_X) + x) * MW+:MW] = sv2v_cast_73DDD(r_data1[(((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - ((((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - (((y * BAYER_EX_PKG_BLK_X) + x) * 14))+:14]) * sv2v_cast_73DDD(s_gain[((y * BAYER_EX_PKG_BLK_X) + x) * 16+:16]);
							s_t[((y * BAYER_EX_PKG_BLK_X) + x) * TW+:TW] = sv2v_cast_C1BC4((s_mul[((y * BAYER_EX_PKG_BLK_X) + x) * MW+:MW] + sv2v_cast_73DDD_signed(2048)) >> BAYER_EX_PKG_GAIN_FRAC);
							if (i_cfg[122])
								s_q2[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = r_data1[(((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - ((((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1) - (((y * BAYER_EX_PKG_BLK_X) + x) * 14))+:14];
							else if (s_t[((y * BAYER_EX_PKG_BLK_X) + x) * TW+:TW] > sv2v_cast_C1BC4_signed(BAYER_EX_PKG_PIX_MAX))
								s_q2[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = sv2v_cast_14_signed(BAYER_EX_PKG_PIX_MAX);
							else
								s_q2[((y * BAYER_EX_PKG_BLK_X) + x) * 14+:14] = sv2v_cast_14(s_t[((y * BAYER_EX_PKG_BLK_X) + x) * TW+:TW]);
						end
				end
		end
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			r_vld1 <= 1'b0;
			r_vld2 <= 1'b0;
		end
		else if (i_en) begin
			r_vld1 <= i_vld;
			r_vld2 <= r_vld1;
		end
	always @(posedge clk) begin
		if (i_en && i_vld) begin
			r_data1 <= i_data;
			r_data1[((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1-:(BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14] <= s_q1;
		end
		if (i_en && r_vld1) begin
			r_data2 <= r_data1;
			r_data2[((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14) - 1-:(BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14] <= s_q2;
		end
	end
	assign o_vld = r_vld2;
	assign o_data = r_data2;
	initial _sv2v_0 = 0;
endmodule
module BAYER_EX (
	clk,
	rst_n,
	i_cfg,
	i_vld,
	o_busy,
	i_data,
	o_vld,
	i_busy,
	o_data
);
	input wire clk;
	input wire rst_n;
	localparam signed [31:0] BAYER_EX_PKG_GAIN_W = 16;
	localparam signed [31:0] BAYER_EX_PKG_PIX_W = 14;
	input wire [122:0] i_cfg;
	input wire i_vld;
	output wire o_busy;
	localparam signed [31:0] BAYER_EX_PKG_BLK_X = 4;
	localparam signed [31:0] BAYER_EX_PKG_BLK_Y = 2;
	input wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] i_data;
	output wire o_vld;
	input wire i_busy;
	output wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] o_data;
	generate
		if (1) begin : s_i_pix
			localparam signed [31:0] BAYER_EX_PKG_BLK_X = 4;
			localparam signed [31:0] BAYER_EX_PKG_BLK_Y = 2;
			localparam signed [31:0] BAYER_EX_PKG_PIX_W = 14;
			wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] data;
		end
		if (1) begin : s_o_pix
			localparam signed [31:0] BAYER_EX_PKG_BLK_X = 4;
			localparam signed [31:0] BAYER_EX_PKG_BLK_Y = 2;
			localparam signed [31:0] BAYER_EX_PKG_PIX_W = 14;
			wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] data;
		end
	endgenerate
	assign s_i_pix.data = i_data;
	assign o_data = s_o_pix.data;
	generate
		if (1) begin : u_core
			wire clk;
			wire rst_n;
			localparam signed [31:0] BAYER_EX_PKG_GAIN_W = 16;
			localparam signed [31:0] BAYER_EX_PKG_PIX_W = 14;
			wire [122:0] i_cfg;
			wire i_vld;
			wire o_busy;
			wire o_vld;
			wire i_busy;
			reg [122:0] r_cfg;
			reg r_in_vld;
			localparam signed [31:0] BAYER_EX_PKG_BLK_X = 4;
			localparam signed [31:0] BAYER_EX_PKG_BLK_Y = 2;
			reg [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] r_in_data;
			reg r_skd_vld;
			reg [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] r_skd_data;
			wire s_take;
			wire s_en;
			wire s_in_free;
			wire s_pc_vld;
			wire [(3 + ((BAYER_EX_PKG_BLK_Y * BAYER_EX_PKG_BLK_X) * 14)) - 1:0] s_pc_data;
			assign s_take = i_vld && !r_skd_vld;
			assign s_en = !(s_pc_vld && i_busy);
			assign s_in_free = !r_in_vld || s_en;
			assign o_busy = r_skd_vld;
			always @(posedge clk) r_cfg <= i_cfg;
			always @(posedge clk or negedge rst_n)
				if (!rst_n) begin
					r_in_vld <= 1'b0;
					r_skd_vld <= 1'b0;
				end
				else if (s_in_free) begin
					r_in_vld <= r_skd_vld || s_take;
					r_skd_vld <= 1'b0;
				end
				else if (s_take)
					r_skd_vld <= 1'b1;
			always @(posedge clk)
				if (s_in_free) begin
					if (r_skd_vld)
						r_in_data <= r_skd_data;
					else if (s_take)
						r_in_data <= BAYER_EX.s_i_pix.data;
				end
				else if (s_take)
					r_skd_data <= BAYER_EX.s_i_pix.data;
			BAYER_EX_PIXCOR u_pixcor(
				.clk(clk),
				.rst_n(rst_n),
				.i_en(s_en),
				.i_cfg(r_cfg),
				.i_vld(r_in_vld),
				.i_data(r_in_data),
				.o_vld(s_pc_vld),
				.o_data(s_pc_data)
			);
			assign o_vld = s_pc_vld;
			assign BAYER_EX.s_o_pix.data = s_pc_data;
		end
	endgenerate
	assign u_core.clk = clk;
	assign u_core.rst_n = rst_n;
	assign u_core.i_cfg = i_cfg;
	assign u_core.i_vld = i_vld;
	assign o_busy = u_core.o_busy;
	assign o_vld = u_core.o_vld;
	assign u_core.i_busy = i_busy;
endmodule