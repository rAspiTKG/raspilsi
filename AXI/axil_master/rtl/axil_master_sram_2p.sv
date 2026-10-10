//=============================================================================
// axil_master_sram_2p.sv
//-----------------------------------------------------------------------------
//  2 ポート (1R1W) 同期メモリの動作モデル。読み出しレイテンシ 1。
//  axil_master_mem の内部メモリ (汎用レジスタ / データバッファ) として使う。
//
//      書き込みポート : we / waddr / wdata          (読み出しコマンドの結果、ローカルの書き込み)
//      読み出しポート : re / raddr -> 次サイクル rdata (書き込みコマンドの送信データ、ローカルの読み出し)
//
//  ワード数が少ないときはこのまま合成すればフリップフロップになる。
//  ワード数が多いときは、メモリコンパイラの 2 ポート (1R1W) マクロに置き換える。
//
//  上位 (axil_master_mem) は次のことに依存しない:
//    - rdata を「読み出しの次の 1 サイクル」以外で使うこと
//    - 同じサイクルに同じアドレスを読み書きしたときの読み出し値 (マクロによって異なる)
//  `define AXIL_MASTER_SRAM_POISON を付けてシミュレーションすると、これらの場合の rdata を
//  乱数にする (依存していないことの確認用)。
//=============================================================================
`timescale 1ns / 1ps

module axil_master_sram_2p #(
  parameter int unsigned DEPTH      = 16
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned ADDR_WIDTH = (DEPTH<2) ? 1 : $clog2(DEPTH)
) (
  input  logic                  clk
  // 書き込みポート
 ,input  logic                  we
 ,input  logic [ADDR_WIDTH-1:0] waddr
 ,input  logic [DATA_WIDTH-1:0] wdata
  // 読み出しポート
 ,input  logic                  re
 ,input  logic [ADDR_WIDTH-1:0] raddr
 ,output logic [DATA_WIDTH-1:0] rdata
);

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

`ifdef AXIL_MASTER_SRAM_POISON
  // 検証用: 有効な読み出しデータ以外 (読み出しの無いサイクル、同じアドレスの同時読み書き) は乱数
  always @(posedge clk) begin
    if( we ) begin
      mem[waddr] <= wdata;
    end
    if( re&&!(we&&(waddr==raddr)) ) begin
      rdata <= mem[raddr];
    end else begin
      for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
        rdata[i] <= 1'($urandom());
      end
    end
  end
`else
  always @(posedge clk) begin
    if( we ) begin
      mem[waddr] <= wdata;
    end
    if( re ) begin
      rdata <= mem[raddr];
    end
  end
`endif

  //---------------------------------------------------------------------------
  // シミュレーション用チェック (合成では `define SYNTHESIS で外れる)
  //   sim_oor_cnt  : DEPTH 以上のアドレスへアクセスした回数
  //   sim_same_cnt : 同じサイクルに同じアドレスを読み書きした回数
  //   テストベンチがどちらも 0 のままであることを確認する
  //---------------------------------------------------------------------------
`ifndef SYNTHESIS
  int unsigned sim_oor_cnt;
  int unsigned sim_same_cnt;

  initial begin
    sim_oor_cnt  = 0;
    sim_same_cnt = 0;
  end

  always @(posedge clk) begin
    int unsigned wa;
    int unsigned ra;
    wa = 32'(waddr);
    ra = 32'(raddr);
    if( (we&&(wa>=DEPTH))||(re&&(ra>=DEPTH)) ) begin
      sim_oor_cnt <= sim_oor_cnt + 1;
      $display("[%0t] axil_master_sram_2p : ERROR : access out of range (we=%0d waddr=%0d re=%0d raddr=%0d depth=%0d)", $time, we, wa, re, ra, DEPTH);
    end
    if( we&&re&&(wa==ra) ) begin
      sim_same_cnt <= sim_same_cnt + 1;
      $display("[%0t] axil_master_sram_2p : ERROR : read and write of the same address %0d in the same cycle", $time, wa);
    end
  end
`endif

endmodule
