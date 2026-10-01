//=============================================================================
// axi_burst_item.svh
//-----------------------------------------------------------------------------
//  monitor が観測した AXI バースト 1 本 (Write / Read 共通)。
//    Write : AW + W (全ビート) + B
//    Read  : AR + R (全ビート)
//=============================================================================

class axi_burst_item extends uvm_sequence_item;

  axi_dir_e        dir;
  bit [ID_W-1:0]   id;
  bit [ADDR_W-1:0] addr;
  bit [7:0]        len;       // ビート数 - 1
  bit [2:0]        size;
  axi_burst_e      burst;
  bit [DATA_W-1:0] data[];
  bit [STRB_W-1:0] strb[];
  bit [1:0]        resp[];    // Write : resp[0] = BRESP / Read : ビートごとの RRESP
  bit [ID_W-1:0]   resp_id;

  `uvm_object_utils(axi_burst_item)

  function new(string name = "axi_burst_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s id=%0h addr=%08h len=%0d size=%0d burst=%s"
                    , dir.name(), id, addr, len, size, burst.name());
  endfunction

endclass
