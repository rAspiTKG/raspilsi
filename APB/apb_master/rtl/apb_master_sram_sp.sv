//=============================================================================
// apb_master_sram_sp.sv
//-----------------------------------------------------------------------------
//  シングルポート同期メモリの動作モデル (1RW、読み出しレイテンシ 1)。
//  apb_master_mem の内部メモリ (汎用レジスタ / データバッファ) として使う。
//
//  ワード数が少ないときはこのまま合成すればフリップフロップになる。
//  ワード数が多いときは、メモリコンパイラの 1RW マクロに置き換える。
//      ce   : チップイネーブル (1 でアクセス)
//      we   : 1 = 書き込み / 0 = 読み出し
//      addr : ワードアドレス
//      wdata: 書き込みデータ
//      rdata: ce&&!we の次サイクルに有効
//  ビット単位のライトマスクは使わない (常にワード全体を書く)。
//
//  上位 (apb_master_mem) は rdata を「読み出しの次の 1 サイクルだけ」使う。
//  マクロ側の rdata 保持 / ライトスルーの仕様には依存しない。
//
//  `define APB_MASTER_SRAM_POISON を付けてシミュレーションすると、読み出しの
//  次サイクル以外の rdata を乱数にする (保持に依存した回路になっていないことの確認用)。
//=============================================================================
`timescale 1ns / 1ps

module apb_master_sram_sp #(
  parameter int unsigned DEPTH      = 16
 ,parameter int unsigned DATA_WIDTH = 32
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

`ifdef APB_MASTER_SRAM_POISON
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

  //---------------------------------------------------------------------------
  // シミュレーション用チェック (合成では `define SYNTHESIS で外れる)
  //   sim_oor_cnt : DEPTH 以上のアドレスへアクセスした回数
  //   テストベンチがこれが 0 のままであることを確認する
  //---------------------------------------------------------------------------
`ifndef SYNTHESIS
  int unsigned sim_oor_cnt;

  initial begin
    sim_oor_cnt = 0;
  end

  always @(posedge clk) begin
    int unsigned a;
    a = 32'(addr);
    if( ce&&(a>=DEPTH) ) begin
      sim_oor_cnt <= sim_oor_cnt + 1;
      $display("[%0t] apb_master_sram_sp : ERROR : access out of range (addr %0d, depth %0d)", $time, a, DEPTH);
    end
  end
`endif

endmodule
