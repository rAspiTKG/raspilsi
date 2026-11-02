// ============================================================================
// bex_item : 1転送(bayer4x2_t)
//   ドライバ: gap クロックだけ vld=0 にしてから送る
//   モニタ  : 転送したクロックの番号(cyc)と、そのときの設定(cfg。入力側だけ)を付ける
// ============================================================================
class bex_item extends uvm_sequence_item;
  `uvm_object_utils(bex_item)

  bayer4x2_t data;
  int        gap;
  longint    cyc;
  cfg_t      cfg;

  function new( string name="bex_item" );
    super.new(name);
    gap = 0;
    cyc = 0;
  endfunction

  function string convert2string();
    return $sformatf("sof=%0d eol=%0d eof=%0d pix={%0d %0d %0d %0d / %0d %0d %0d %0d}", data.sof, data.eol, data.eof,
                      data.pix[0][0], data.pix[0][1], data.pix[0][2], data.pix[0][3],
                      data.pix[1][0], data.pix[1][1], data.pix[1][2], data.pix[1][3]);
  endfunction
endclass

// ============================================================================
// bex_frame_seq : 1フレーム分の転送を送る
//   gap_mode 0: 間をあけない 1: 乱数(gap_pct [%] の転送の前に 1〜3 クロック)
//            2: ときどき長くあける(5〜20 クロック)  3: gaps[] の値をそのまま使う
// ============================================================================
class bex_frame_seq extends uvm_sequence #(bex_item);
  `uvm_object_utils(bex_frame_seq)

  bex_image img;
  int       gap_mode = 1;
  int       gap_pct  = 20;
  int       gaps[$];

  function new( string name="bex_frame_seq" );
    super.new(name);
  endfunction

  function int pick_gap( int k );
    case( gap_mode )
      0 : begin
        return 0;
      end
      2 : begin
        if( $urandom_range(99,0)<5 ) begin
          return $urandom_range(20, 5);
        end
        return 0;
      end
      3 : begin
        if( k<gaps.size() ) begin
          return gaps[k];
        end
        return 0;
      end
      default : begin
        if( $urandom_range(99,0)<gap_pct ) begin
          return $urandom_range(3, 1);
        end
        return 0;
      end
    endcase
  endfunction

  task body();
    bex_item it;
    for( int k=0; k<img.n_xfer(); k++ ) begin
      it = bex_item::type_id::create("it");
      start_item(it);
      it.data = img.xfer(k);
      it.gap  = pick_gap(k);
      finish_item(it);
    end
  endtask
endclass
