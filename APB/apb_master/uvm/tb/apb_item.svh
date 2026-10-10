//=============================================================================
// apb_item.svh
//-----------------------------------------------------------------------------
//  monitor が出す APB 転送 1 回分。
//  PREADY を待たずに打ち切られた転送も aborted=1 で出す。
//=============================================================================

class apb_item extends uvm_sequence_item;

  int unsigned     slv;         // スレーブ番号 (立っていた PSEL)
  bit [63:0]       addr;
  bit              write;
  bit [DATA_W-1:0] wdata;
  bit [STRB_W-1:0] strb;
  bit [2:0]        prot;
  bit [DATA_W-1:0] rdata;       // 完了サイクルの PRDATA
  bit              slverr;      // 完了サイクルの PSLVERR
  bit              aborted;     // PREADY を待たずに打ち切られた
  int unsigned     n_wait;      // ウェイト数 (PREADY=0 だった ACCESS のサイクル数)
  bit              b2b;         // 直前の転送の最後の ACCESS の次のサイクルに始まった (IDLE を挟んでいない)

  `uvm_object_utils(apb_item)

  function new(string name = "apb_item");
    super.new(name);
  endfunction

  function string convert2string();
    string s;
    // 長さの違う文字列リテラルを ?: で選ぶと短いほうに詰め物が付くので、if で分ける
    if( write ) begin
      s = $sformatf("WRITE slave=%0d addr=%0h prot=%b wait=%0d wdata=%0h strb=%b", slv, addr, prot, n_wait, wdata, strb);
    end else begin
      s = $sformatf("READ slave=%0d addr=%0h prot=%b wait=%0d rdata=%0h", slv, addr, prot, n_wait, rdata);
    end
    if( aborted ) begin
      s = {s, " ABORTED"};
    end else if( slverr ) begin
      s = {s, " PSLVERR"};
    end
    return s;
  endfunction

endclass
