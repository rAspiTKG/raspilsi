// ============================================================================
// BAYER_EX_DATA_IF : data だけのインタフェース
//   data は bayer4x2_t(Bayer の水平4画素 × 垂直2ライン と sof / eol / eof)。
//   vld / busy はインタフェースに入れず、モジュールのポートにする。
//     vld=1 かつ busy=0 のクロックで1転送する。
//     busy=1 の間、送り側は vld と data を保持する。
//     vld は busy に組み合わせで依存してはならない(busy は vld に依存してよい)。
// ============================================================================
interface BAYER_EX_DATA_IF;
  import BAYER_EX_PKG::*;

  bayer4x2_t data;

  // 送り側
  modport src (
    output data
  );

  // 受け側
  modport dst (
    input  data
  );

  // 監視(検証環境用)
  modport mon (
    input  data
  );
endinterface
