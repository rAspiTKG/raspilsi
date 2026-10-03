//=============================================================================
// axi4_lb_sram_sp.sv
//-----------------------------------------------------------------------------
//  シングルポート同期 SRAM の動作モデル (1RW、読み出しレイテンシ 1)。
//
//  ASIC ではこのモジュールをメモリコンパイラの生成マクロに置き換える。
//  ピンの意味は一般的な 1RW マクロに合わせている。
//      ce   : チップイネーブル (1 でアクセス)
//      we   : 1 = 書き込み / 0 = 読み出し
//      addr : ワードアドレス
//      wdata: 書き込みデータ
//      rdata: ce&&!we の次サイクルに有効
//  ビット単位のライトマスクは使わない (常にワード全体を書く)。
//
//  上位 (axi4_lb_scratchpad) は rdata を「読み出しの次の 1 サイクルだけ」使う。
//  マクロ側の rdata 保持 / ライトスルーの仕様には依存しない。
//
//  `define AXI4_LB_SRAM_POISON を付けてシミュレーションすると、読み出しの
//  次サイクル以外の rdata を乱数にする (保持に依存した回路になっていないことの確認用)。
//=============================================================================
`timescale 1ns / 1ps

module axi4_lb_sram_sp #(
  parameter int unsigned DEPTH      = 1024
 ,parameter int unsigned DATA_WIDTH = 8
 ,parameter int unsigned ADDR_WIDTH = (DEPTH<2) ? 1 : $clog2(DEPTH)
) (
  input  logic                  clk
 ,input  logic                  ce
 ,input  logic                  we
 ,input  logic [ADDR_WIDTH-1:0] addr
 ,input  logic [DATA_WIDTH-1:0] wdata
 ,output logic [DATA_WIDTH-1:0] rdata
);

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

`ifdef AXI4_LB_SRAM_POISON
  // 検証用: 有効な読み出しデータ以外は乱数にする
  always @(posedge clk) begin
    if( ce&&we ) begin
      mem[addr] <= wdata;
    end
    if( ce&&!we ) begin
      rdata <= mem[addr];
    end else begin
      for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
        rdata[i] <= 1'($urandom());
      end
    end
  end
`else
  always @(posedge clk) begin
    if( ce ) begin
      if( we ) begin
        mem[addr] <= wdata;
      end else begin
        rdata <= mem[addr];
      end
    end
  end
`endif

endmodule
