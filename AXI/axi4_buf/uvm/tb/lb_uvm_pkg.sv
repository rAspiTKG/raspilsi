//=============================================================================
// lb_uvm_pkg.sv
//-----------------------------------------------------------------------------
//  axi4_master_linebuf 検証用 UVM パッケージ。
//  DUT がマスタなので、テストベンチ側は
//    - コマンド agent           : フレームのコマンドを発行し、done を待つ
//    - 入力側 AXI スレーブ agent : AR / R に応答する (入力画像のメモリ)
//    - 出力側 AXI スレーブ agent : AW / W / B に応答する (出力先のメモリ)
//  の 3 つで構成する。
//
//  コンパイル順 : uvm_pkg.sv -> lb_params_pkg.sv -> axi_rd_if.sv -> axi_wr_if.sv
//                 -> cmd_if.sv -> lb_uvm_pkg.sv -> tb_top.sv
//=============================================================================
`timescale 1ns / 1ps

package lb_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import lb_params_pkg::*;

  //---------------------------------------------------------------------------
  // 型 / 定数
  //---------------------------------------------------------------------------
  typedef enum bit {
    AXI_WRITE = 1'b0
   ,AXI_READ  = 1'b1
  } axi_dir_e;

  typedef enum bit [1:0] {
    AXI_FIXED = 2'b00
   ,AXI_INCR  = 2'b01
   ,AXI_WRAP  = 2'b10
  } axi_burst_e;

  // virtual interface の型 (uvm_config_db の set / get で同じ名前を使う)
  typedef virtual axi_rd_if axi_rd_vif_t;
  typedef virtual axi_wr_if axi_wr_vif_t;
  typedef virtual cmd_if    cmd_vif_t;

  parameter bit [1:0] AXI_OKAY   = 2'b00;
  parameter bit [1:0] AXI_SLVERR = 2'b10;

  // ライン外を壊していないことを見るためのガード領域 [バイト]
  parameter int unsigned GUARD = 64;

  //---------------------------------------------------------------------------
  // 画像フォーマットの計算 (DUT と同じ定義)
  //---------------------------------------------------------------------------
  // 1 ラインのバイト数
  function automatic int unsigned lb_line_bytes(input int unsigned w);
    return ((w*PIX_MEM_BITS)+7)/8;
  endfunction

  // nbytes を運ぶのに必要なビート数
  function automatic int unsigned lb_beats(input int unsigned nbytes, input int unsigned bus_bytes);
    return (nbytes+bus_bytes-1)/bus_bytes;
  endfunction

  function automatic int unsigned lb_align_up(input int unsigned x, input int unsigned a);
    return ((x+a-1)/a)*a;
  endfunction

  // 出力先に事前に書いておくパターン
  function automatic bit [7:0] lb_pattern(input bit [63:0] a);
    return 8'((a*64'd37) ^ (a >> 7) ^ 64'h5A);
  endfunction

  // ライン内 i バイト目の期待値。src_byte は入力側の同じ位置のバイト。
  //   画素フィールド (コンテナ内の PIX_OFS から PIXEL_BITS ビット) だけ残し、
  //   コンテナの余りビットとライン幅より後ろのビットは 0
  function automatic bit [7:0] lb_exp_byte(input bit [7:0] src_byte, input int unsigned i, input int unsigned w);
    bit [7:0] e;
    int       k;
    int       c;
    e = 8'h00;
    for( int b=0; b<8; b++ ) begin
      k = (8*int'(i)) + b;
      c = k % int'(PIX_MEM_BITS);
      if( (k<int'(w*PIX_MEM_BITS))&&(c>=int'(PIX_OFS))&&(c<int'(PIX_OFS+PIXEL_BITS)) ) begin
        e[b] = src_byte[b];
      end
    end
    return e;
  endfunction

  //---------------------------------------------------------------------------
  // バースト内 beat 番目の転送アドレス
  //---------------------------------------------------------------------------
  function automatic bit [63:0] axi_beat_addr
  (
    input bit [63:0]   start
   ,input bit [7:0]    len
   ,input bit [2:0]    size
   ,input axi_burst_e  burst
   ,input int unsigned beat
  );
    bit [63:0] nbytes;
    bit [63:0] total;
    bit [63:0] lo;
    bit [63:0] a;
    nbytes = 64'd1 << size;
    case( burst )
      AXI_FIXED : begin
        a = start;
      end
      AXI_WRAP : begin
        total = nbytes * (64'(len) + 64'd1);
        lo    = start & ~(total - 64'd1);
        a     = lo + ((start - lo + (nbytes * 64'(beat))) % total);
      end
      default : begin
        if( beat==0 ) begin
          a = start;
        end else begin
          a = (start & ~(nbytes - 64'd1)) + (nbytes * 64'(beat));
        end
      end
    endcase
    return a;
  endfunction

  //---------------------------------------------------------------------------
  // クラス
  //---------------------------------------------------------------------------
  `include "axi_burst_item.svh"
  `include "axi_mem.svh"
  `include "axi_rd_slv_agent.svh"
  `include "axi_wr_slv_agent.svh"
  `include "cmd_agent.svh"
  `include "lb_scoreboard.svh"
  `include "lb_coverage.svh"
  `include "lb_env.svh"
  `include "lb_seq_lib.svh"
  `include "lb_test_lib.svh"

endpackage
