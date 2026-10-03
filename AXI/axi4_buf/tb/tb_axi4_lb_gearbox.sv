//=============================================================================
// tb_axi4_lb_gearbox.sv
//-----------------------------------------------------------------------------
//  axi4_lb_gearbox の単体テスト (自己チェック)。
//
//  1 回のテスト単位 (ライン) ごとに、ランダムな個数の入力チャンクを流し、
//  出力チャンクをビット列の参照モデルと照合する。
//    phase 0 : ストール無し (スループットも確認: 余分なサイクルが 3 以下)
//    phase 1 : 入力ギャップ / 出力ストールをランダムに入れる
//    phase 2 : 排出中の途中で clear を入れる (残りビットが捨てられること)
//
//  テストベンチは全て posedge の同期ロジックで書いている
//  (駆動はノンブロッキング代入、観測はエッジ直前の値)。
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_lb_gearbox #(
  parameter int unsigned IN_BITS  = 64
 ,parameter int unsigned OUT_BITS = 8
 ,parameter int unsigned N_LINES  = 300
);

  //---------------------------------------------------------------------------
  // クロック / リセット
  //---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever begin
      #5 clk = ~clk;
    end
  end

  initial begin
    rst_n = 1'b0;
    repeat( 5 ) begin
      @(negedge clk);
    end
    rst_n = 1'b1;
  end

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  logic                clear;
  logic [IN_BITS-1:0]  in_data;
  logic                in_last;
  logic                in_valid;
  logic                in_ready;
  logic [OUT_BITS-1:0] out_data;
  logic                out_last;
  logic                out_valid;
  logic                out_ready;

  axi4_lb_gearbox #(
    .IN_BITS(IN_BITS)
   ,.OUT_BITS(OUT_BITS)
  ) u_dut (
    .clk(clk)
   ,.rst_n(rst_n)
   ,.clear(clear)
   ,.in_data(in_data)
   ,.in_last(in_last)
   ,.in_valid(in_valid)
   ,.in_ready(in_ready)
   ,.out_data(out_data)
   ,.out_last(out_last)
   ,.out_valid(out_valid)
   ,.out_ready(out_ready)
  );

  //---------------------------------------------------------------------------
  // テスト状態
  //---------------------------------------------------------------------------
  int unsigned line_no;       // 実行中のライン番号
  int unsigned phase;         // 0: ストール無し / 1: ランダムストール / 2: clear 付き
  int unsigned n_in;          // このラインの入力チャンク数
  int unsigned n_in_sent;     // 受け付けられた入力チャンク数
  int unsigned n_out;         // 出力されたチャンク数
  int unsigned cut_idx;       // phase 2: この番号の出力で clear する
  bit          use_cut;
  bit          last_acc;      // 最終入力を受け付け済み
  bit          line_act;      // ライン実行中
  int unsigned cyc;           // ライン開始からのサイクル数
  int unsigned err_cnt;
  int unsigned n_chunk_total;
  int unsigned n_clear;
  bit          bitq[$];       // 参照モデル: 未出力のビット列 (下位が先)
  bit          finished;

  // clear は「指定番号の出力が成立するサイクル」に組合せで出す (DUT の使われ方と同じ)
  assign clear = line_act&&use_cut&&last_acc&&out_valid&&out_ready&&(n_out==cut_idx);

  function automatic logic [IN_BITS-1:0] f_rand_in();
    logic [IN_BITS-1:0] d;
    for( int unsigned i=0; i<IN_BITS; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  //---------------------------------------------------------------------------
  // 駆動 / 照合
  //---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    logic [OUT_BITS-1:0] exp_data;
    bit                  exp_last;
    bit                  out_fire;
    bit                  in_fire;
    int unsigned         total_out;
    int unsigned         back;
    int unsigned         ideal;
    int unsigned         n_out_v;
    int unsigned         n_sent_v;
    if( !rst_n ) begin
      line_no       <= 0;
      phase         <= 0;
      n_in          <= 0;
      n_in_sent     <= 0;
      n_out         <= 0;
      cut_idx       <= 0;
      use_cut       <= 1'b0;
      last_acc      <= 1'b0;
      line_act      <= 1'b0;
      cyc           <= 0;
      err_cnt       <= 0;
      n_chunk_total <= 0;
      n_clear       <= 0;
      finished      <= 1'b0;
      in_valid      <= 1'b0;
      in_last       <= 1'b0;
      in_data       <= '0;
      out_ready     <= 1'b0;
    end else if( !finished ) begin
      if( !line_act ) begin
        //---------------------------------------------------------------------
        // 次のラインを準備
        //---------------------------------------------------------------------
        if( line_no==N_LINES ) begin
          finished <= 1'b1;
        end else begin
          phase     <= (line_no*3)/N_LINES;
          // phase 0 は長めにして、スループットの低下が積み上がるようにする
          n_in      <= (((line_no*3)/N_LINES)==0) ? $urandom_range(96,1) : $urandom_range(24,1);
          n_in_sent <= 0;
          n_out     <= 0;
          last_acc  <= 1'b0;
          line_act  <= 1'b1;
          cyc       <= 0;
          use_cut   <= 1'b0;
          in_valid  <= 1'b0;
          out_ready <= 1'b0;
          bitq.delete();
        end
      end else begin
        out_fire  = out_valid&&out_ready;
        in_fire   = in_valid&&in_ready;
        n_out_v   = n_out + (out_fire ? 1 : 0);
        n_sent_v  = n_in_sent + (in_fire ? 1 : 0);
        total_out = ((n_in*IN_BITS)+OUT_BITS-1)/OUT_BITS;
        cyc       <= cyc + 1;
        n_out     <= n_out_v;
        n_in_sent <= n_sent_v;
        // phase 2 の clear 位置は最初のサイクルに決める (末尾から 0..3 個手前の出力)
        if( (cyc==0)&&(phase==2) ) begin
          back = $urandom_range(3,0);
          if( back>(total_out-1) ) begin
            back = total_out - 1;
          end
          use_cut <= 1'b1;
          cut_idx <= total_out - 1 - back;
        end
        //---------------------------------------------------------------------
        // 出力の照合 (同じサイクルの入力より先に処理する)
        //---------------------------------------------------------------------
        if( out_fire ) begin
          exp_data = '0;
          exp_last = last_acc&&(bitq.size()<=OUT_BITS);
          for( int unsigned i=0; i<OUT_BITS; i++ ) begin
            if( bitq.size()!=0 ) begin
              exp_data[i] = bitq.pop_front();
            end
          end
          if( out_data!==exp_data ) begin
            $display("[FAIL] line %0d out #%0d data=%h exp=%h", line_no, n_out, out_data, exp_data);
            err_cnt <= err_cnt + 1;
          end
          if( out_last!==exp_last ) begin
            $display("[FAIL] line %0d out #%0d out_last=%b exp=%b", line_no, n_out, out_last, exp_last);
            err_cnt <= err_cnt + 1;
          end
          n_chunk_total <= n_chunk_total + 1;
        end
        //---------------------------------------------------------------------
        // 入力の受付
        //---------------------------------------------------------------------
        if( in_fire ) begin
          for( int unsigned i=0; i<IN_BITS; i++ ) begin
            bitq.push_back(in_data[i]);
          end
          if( in_last ) begin
            last_acc <= 1'b1;
          end
        end
        //---------------------------------------------------------------------
        // ライン終了判定
        //   clear したサイクル、または最終入力後に出し切ったサイクル
        //---------------------------------------------------------------------
        if( clear ) begin
          n_clear   <= n_clear + 1;
          line_act  <= 1'b0;
          line_no   <= line_no + 1;
          in_valid  <= 1'b0;
          out_ready <= 1'b0;
          bitq.delete();
        end else if( last_acc&&(bitq.size()==0) ) begin
          // スループット確認 (phase 0): 理想は max(入力数, 出力数) サイクル
          if( phase==0 ) begin
            ideal = (n_in>n_out_v) ? n_in : n_out_v;
            if( cyc>(ideal+3) ) begin
              $display("[FAIL] line %0d throughput : %0d cycles for in=%0d out=%0d", line_no, cyc, n_in, n_out_v);
              err_cnt <= err_cnt + 1;
            end
          end
          if( n_out_v!=total_out ) begin
            $display("[FAIL] line %0d output count %0d (exp %0d)", line_no, n_out_v, total_out);
            err_cnt <= err_cnt + 1;
          end
          line_act  <= 1'b0;
          line_no   <= line_no + 1;
          in_valid  <= 1'b0;
          out_ready <= 1'b0;
        end else begin
          //-------------------------------------------------------------------
          // 次サイクルの駆動
          //-------------------------------------------------------------------
          // 入力: 握手が成立した (または出していない) ら次のチャンク、未成立なら保持
          if( !in_valid||in_ready ) begin
            if( (n_sent_v<n_in)&&((phase==0)||($urandom_range(99,0)<70)) ) begin
              in_valid <= 1'b1;
              in_data  <= f_rand_in();
              in_last  <= (n_sent_v==(n_in-1));
            end else begin
              in_valid <= 1'b0;
            end
          end
          // 出力: phase 0 は常に受ける
          out_ready <= (phase==0)||($urandom_range(99,0)<60);
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 終了
  //---------------------------------------------------------------------------
  initial begin
    wait( finished===1'b1 );
    @(negedge clk);
    $display("[INFO] IN_BITS=%0d OUT_BITS=%0d : lines=%0d out chunks=%0d clears=%0d", IN_BITS, OUT_BITS, line_no, n_chunk_total, n_clear);
    if( (err_cnt==0)&&(n_chunk_total!=0)&&(n_clear!=0) ) begin
      $display("=== tb_axi4_lb_gearbox : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_lb_gearbox : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  initial begin
    #50ms;
    $display("=== tb_axi4_lb_gearbox : TEST FAILED (timeout) ===");
    $finish;
  end

endmodule
