// ============================================================================
// bex_ref_model : リファレンスモデル(仕様書 6章の式をそのまま書いたもの)
//   RTL とは別に、整数で計算する
//     色の位置 s = 2×(y xor phase[1]) + (x の偶奇 xor phase[0])   0:R 1:Gr 2:Gb 3:B
//     bypass=1 : q = p
//     bypass=0 : d = max(p − blc[s], 0)
//                q = min(16383, floor((d × gain[s] + 2048) / 4096))
// ============================================================================
class bex_ref_model;

  // 画素の結果の分類(カバレッジ用)
  typedef enum int {
    RES_BYPASS = 0,   // 補正しない
    RES_CLAMP  = 1,   // 黒レベル以下(0 になった)
    RES_SAT    = 2,   // 16383 で飽和した
    RES_NORMAL = 3    // それ以外
  } res_e;

  static function int site( bit [1:0] phase, int y, int x );
    return (((y%2)^phase[1])*2)+((x%2)^phase[0]);
  endfunction

  // 1画素。res に分類を返す
  static function int pix( cfg_t c, int y, int x, int p, output int res );
    int     s;
    longint d;
    longint t;
    if( c.bypass ) begin
      res = RES_BYPASS;
      return p;
    end
    s = site(c.phase, y, x);
    d = longint'(p)-longint'(c.blc[s]);
    if( d<=0 ) begin
      res = RES_CLAMP;
      return 0;
    end
    t = ((d*longint'(c.gain[s]))+2048)/4096;
    if( t>16383 ) begin
      res = RES_SAT;
      return 16383;
    end
    res = RES_NORMAL;
    return int'(t);
  endfunction

  // 1転送
  static function bayer4x2_t xfer( cfg_t c, bayer4x2_t d );
    bayer4x2_t q;
    int        r;
    q = d;
    for( int y=0; y<2; y++ ) begin
      for( int x=0; x<4; x++ ) begin
        q.pix[y][x] = 14'(pix(c, y, x, int'(d.pix[y][x]), r));
      end
    end
    return q;
  endfunction
endclass
