// ============================================================================
// BAYER2RGB_VBD_IF : vld/busy/data インタフェース
//   vld=1 かつ busy=0 のクロックで1転送する。
//   busy=1 の間、送り側は vld と data を保持する。
//   vld は busy に組み合わせで依存してはならない(busy は vld に依存してよい)。
// ============================================================================
interface BAYER2RGB_VBD_IF #(
  parameter int DW = 8
);
  logic          vld;
  logic          busy;
  logic [DW-1:0] data;

  // 送り側
  modport src (
    output vld
   ,output data
   ,input  busy
  );

  // 受け側
  modport dst (
    input  vld
   ,input  data
   ,output busy
  );

  // 監視(検証環境用)
  modport mon (
    input  vld
   ,input  data
   ,input  busy
  );
endinterface
