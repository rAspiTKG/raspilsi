//=============================================================================
// axi_item.svh
//-----------------------------------------------------------------------------
//  monitor が出す AXI トランザクション 1 つ (応答を受け取った時点で出す)。
//    書き込み : AW と W を受け、B を返した
//    読み出し : AR を受け、R を返した
//  サイクル番号は monitor が数えたもの (握手したエッジの番号)。
//=============================================================================

class axi_item extends uvm_sequence_item;

  bit              write;
  bit [63:0]       addr;
  bit [2:0]        prot;
  bit [DATA_W-1:0] data;          // WDATA / RDATA
  bit [STRB_W-1:0] strb;          // WSTRB (読み出しは 0)
  bit [1:0]        resp;          // BRESP / RRESP
  int unsigned     a_cyc;         // AW / AR の握手
  int unsigned     w_cyc;         // W の握手 (書き込み)
  int unsigned     resp_cyc;      // B / R の握手
  int unsigned     depth;         // AW / AR を受けた時点の、この方向の未完了数 (このトランザクションを含む)
  bit              other_out;     // AW / AR を受けた時点で、反対方向にも未完了があった

  `uvm_object_utils(axi_item)

  function new(string name = "axi_item");
    super.new(name);
  endfunction

  // 応答の遅延 : アドレスとデータが揃ったエッジから、B / R の握手までのサイクル数 - 1
  //   (スレーブモデルの遅延 0 で 0。READY による待ちも含む)
  function int unsigned latency();
    int unsigned t;
    t = a_cyc;
    if( write&&(w_cyc>t) ) begin
      t = w_cyc;
    end
    return resp_cyc - t - 1;
  endfunction

  function string resp_str();
    string s;
    case( resp )
      2'b00 : begin
        s = "OKAY";
      end
      2'b01 : begin
        s = "EXOKAY";
      end
      2'b10 : begin
        s = "SLVERR";
      end
      default : begin
        s = "DECERR";
      end
    endcase
    return s;
  endfunction

  function string convert2string();
    string s;
    // 長さの違う文字列リテラルを ?: で選ぶと短いほうに詰め物が付くので、if で分ける
    if( write ) begin
      s = $sformatf("WRITE addr=%0h prot=%b data=%0h strb=%b %s (AW@%0d W@%0d B@%0d depth=%0d)", addr, prot, data, strb, resp_str(), a_cyc, w_cyc, resp_cyc, depth);
    end else begin
      s = $sformatf("READ addr=%0h prot=%b data=%0h %s (AR@%0d R@%0d depth=%0d)", addr, prot, data, resp_str(), a_cyc, resp_cyc, depth);
    end
    return s;
  endfunction

endclass
