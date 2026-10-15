//==============================================================================
// tb_pll_fracn_bm.sv : self-checking testbench for pll_fracn_bm
//   u0 : PRELOCK_MODE=0 (Low until LOCK), checks enabled
//   u1 : PRELOCK_MODE=1 (X until LOCK)
//   u2 : PRELOCK_MODE=2 (frequency ramp until LOCK)
//   u3 : SSC down-spread 5000ppm / 31.5kHz
//   u4 : TIE jitter 20ps p-p
//==============================================================================

//------------------------------------------------------------------------------
// clock monitor
//------------------------------------------------------------------------------
module clk_mon (
  input  logic CLK
 ,input  logic ARM
);

  timeunit      1ns;
  timeprecision 1ps;

  int   cnt   = 0;       // rising edges while ARM=1
  int   xcnt  = 0;       // X/Z events while ARM=1
  real  t0    = 0.0;     // first rising edge
  real  t1    = 0.0;     // last rising edge
  real  tf    = 0.0;     // last falling edge
  logic fseen = 1'b0;
  real  pmin  = 1.0e9;   // min period
  real  pmax  = 0.0;     // max period
  real  hmin  = 1.0e9;   // min high width
  real  lmin  = 1.0e9;   // min low width

  always @(posedge ARM) begin : p_clr
    cnt   = 0;
    xcnt  = 0;
    fseen = 1'b0;
    pmin  = 1.0e9;
    pmax  = 0.0;
    hmin  = 1.0e9;
    lmin  = 1.0e9;
  end

  always @(CLK) begin : p_mon
    real tn;
    tn = $realtime;
    if( ARM===1'b1 ) begin
      if( (CLK!==1'b0)&&(CLK!==1'b1) ) begin
        xcnt = xcnt + 1;
      end else if( CLK==1'b1 ) begin
        if( cnt>0 ) begin
          if( (tn-t1)<pmin ) begin
            pmin = tn - t1;
          end
          if( (tn-t1)>pmax ) begin
            pmax = tn - t1;
          end
        end else begin
          t0 = tn;
        end
        if( fseen==1'b1 ) begin
          if( (tn-tf)<lmin ) begin
            lmin = tn - tf;
          end
        end
        t1  = tn;
        cnt = cnt + 1;
      end else begin
        if( cnt>0 ) begin
          if( (tn-t1)<hmin ) begin
            hmin = tn - t1;
          end
          tf    = tn;
          fseen = 1'b1;
        end
      end
    end
  end

endmodule

//------------------------------------------------------------------------------
// testbench
//------------------------------------------------------------------------------
module tb_pll_fracn_bm;

  timeunit      1ns;
  timeprecision 1ps;

  localparam int NPLL = 5;

  //----------------------------------------------------------------------------
  // stimulus
  //----------------------------------------------------------------------------
  logic             fref      = 1'b0;
  logic             fref_en   = 1'b0;
  real              fref_mhz  = 25.0;
  logic             pd        = 1'b1;
  logic             vcopd     = 1'b1;
  logic             postdivpd = 1'b1;
  logic             dsmpd     = 1'b1;
  logic             bypass    = 1'b0;
  logic [5:0]       refdiv    = 6'd1;
  logic [11:0]      fbdiv     = 12'd48;
  logic [23:0]      frac      = 24'd0;
  logic [2:0]       postdiv1  = 3'd3;
  logic [2:0]       postdiv2  = 3'd2;
  logic             arm       = 1'b0;
  wire  [NPLL-1:0]  fout;
  wire  [NPLL-1:0]  fvco;
  wire  [NPLL-1:0]  lock;
  int               err_cnt   = 0;
  int               lock_fall = 0;

  //----------------------------------------------------------------------------
  // reference clock (absolute time scheduling, no accumulated error)
  //----------------------------------------------------------------------------
  initial begin : g_fref
    real    hp;
    real    t0;
    longint k;
    forever begin
      wait( fref_en==1'b1 );
      hp = 500.0 / fref_mhz;
      t0 = $realtime;
      k  = 0;
      // stop / frequency change takes effect after a falling edge (no glitch)
      while( ((fref_en==1'b1)&&(hp==(500.0/fref_mhz)))||(fref==1'b1) ) begin
        k = k + 1;
        #((t0 + (k * hp)) - $realtime);
        fref = ~fref;
      end
    end
  end

  //----------------------------------------------------------------------------
  // DUT (limits : example values = RP2040 PLL constraints)
  //----------------------------------------------------------------------------
  genvar gi;
  generate
    for( gi=0; gi<NPLL; gi=gi+1 ) begin : g_pll
      pll_fracn_bm #(
         .LOCK_PFD_CYCLES (100)
        ,.PRELOCK_MODE    ((gi==1) ? 1 : ((gi==2) ? 2 : 0))
        ,.SSC_SPREAD_PPM  ((gi==3) ? 5000.0 : 0.0)
        ,.JITTER_PS_PP    ((gi==4) ? 20.0 : 0.0)
        ,.FOUTVCO_EN      ((gi>=3) ? 0 : 1)
        ,.FREF_MIN_MHZ    (5.0)
        ,.FREF_MAX_MHZ    (800.0)
        ,.FVCO_MIN_MHZ    (750.0)
        ,.FVCO_MAX_MHZ    (1600.0)
        ,.FBDIV_MIN       (16)
        ,.FBDIV_MAX       (320)
        ,.CHECK_EN        ((gi==0) ? 1 : 0)
        ,.VERBOSE         ((gi==0) ? 1 : 0)
      ) u_pll (
         .FREF        (fref)
        ,.PD          (pd)
        ,.VCOPD       (vcopd)
        ,.POSTDIVPD   (postdivpd)
        ,.DSMPD       (dsmpd)
        ,.BYPASS      (bypass)
        ,.REFDIV      (refdiv)
        ,.FBDIV       (fbdiv)
        ,.FRAC        (frac)
        ,.POSTDIV1    (postdiv1)
        ,.POSTDIV2    (postdiv2)
        ,.FOUTPOSTDIV (fout[gi])
        ,.FOUTVCO     (fvco[gi])
        ,.LOCK        (lock[gi])
      );
      clk_mon u_mp (
         .CLK (fout[gi])
        ,.ARM (arm)
      );
      clk_mon u_mv (
         .CLK (fvco[gi])
        ,.ARM (arm)
      );
    end
  endgenerate

  always @(negedge lock[0]) begin : p_lock_fall
    lock_fall = lock_fall + 1;
  end

  real t_vrise = 0.0;    // last rising edge of u0 FOUTVCO
  always @(posedge fvco[0]) begin : p_vrise
    t_vrise = $realtime;
  end

  //----------------------------------------------------------------------------
  // check utilities
  //----------------------------------------------------------------------------
  task automatic chk_val(
    input string name
   ,input real   val
   ,input real   exp
   ,input real   tol
  );
    begin
      if( (val<(exp-tol))||(val>(exp+tol)) ) begin
        $display("[FAIL] %s : %0.6f (exp %0.6f +/- %0.6f)", name, val, exp, tol);
        err_cnt = err_cnt + 1;
      end else begin
        $display("[PASS] %s : %0.6f (exp %0.6f)", name, val, exp);
      end
    end
  endtask

  task automatic chk_freq(
    input string name
   ,input int    cnt
   ,input real   t0
   ,input real   t1
   ,input real   exp_mhz
   ,input real   tol_ppm
  );
    real f;
    real e;
    begin
      f = 0.0;
      if( cnt>1 ) begin
        f = (cnt - 1) * 1.0e3 / (t1 - t0);
      end
      e = (f - exp_mhz) / exp_mhz * 1.0e6;
      if( (e>tol_ppm)||(e<(-tol_ppm)) ) begin
        $display("[FAIL] %s : %0.9f MHz (exp %0.9f, err %0.4f ppm)", name, f, exp_mhz, e);
        err_cnt = err_cnt + 1;
      end else begin
        $display("[PASS] %s : %0.9f MHz (exp %0.9f, err %0.4f ppm)", name, f, exp_mhz, e);
      end
    end
  endtask

  task automatic meas( input real tw );
    begin
      arm = 1'b1;
      #(tw);
      arm = 1'b0;
    end
  endtask

  task automatic wait_lock(
    input  real tmo
   ,output real tl
  );
    real ts;
    begin
      ts = $realtime;
      while( (lock[0]!==1'b1)&&(($realtime-ts)<tmo) ) begin
        #1;
      end
      tl = $realtime - ts;
    end
  endtask

  //----------------------------------------------------------------------------
  // test sequence
  //----------------------------------------------------------------------------
  initial begin : p_main
    real tpu;
    real tl;
    real tr;
    real fv;
    int  lf;

    fref_en = 1'b1;
    #1000;

    //--------------------------------------------------------------------------
    $display("---- T1 : integer mode 25MHz x48 /(3*2) , pre-lock behavior");
    tpu   = $realtime;
    pd    = 1'b0;
    vcopd = 1'b0;
    meas(2000.0);
    chk_val("T1 pre-lock u0 FOUTVCO rising edges (mode0)", g_pll[0].u_mv.cnt, 0.0, 0.0);
    chk_val("T1 pre-lock u1 FOUTVCO is X (mode1)", (g_pll[1].u_mv.xcnt>0) ? 1.0 : 0.0, 1.0, 0.0);
    chk_val("T1 pre-lock u2 FOUTVCO toggles (mode2)", (g_pll[2].u_mv.cnt>10) ? 1.0 : 0.0, 1.0, 0.0);
    chk_val("T1 pre-lock u2 FOUTVCO slower than target", (g_pll[2].u_mv.hmin>0.416) ? 1.0 : 0.0, 1.0, 0.0);
    wait_lock(20000.0, tl);
    chk_val("T1 lock time from PD=0 [ns]", $realtime - tpu, 4060.0, 80.0);
    postdivpd = 1'b0;
    #100;
    meas(5000.0);
    chk_freq("T1 u0 FOUTVCO", g_pll[0].u_mv.cnt, g_pll[0].u_mv.t0, g_pll[0].u_mv.t1, 1200.0, 0.5);
    chk_freq("T1 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 200.0, 0.5);
    chk_val("T1 u0 FOUTPOSTDIV min high [ns]", g_pll[0].u_mp.hmin, 2.5, 0.002);
    chk_val("T1 u0 FOUTPOSTDIV min low [ns]", g_pll[0].u_mp.lmin, 2.5, 0.002);
    chk_freq("T1 u1 FOUTPOSTDIV (after lock)", g_pll[1].u_mp.cnt, g_pll[1].u_mp.t0, g_pll[1].u_mp.t1, 200.0, 0.5);
    chk_freq("T1 u2 FOUTPOSTDIV (after lock)", g_pll[2].u_mp.cnt, g_pll[2].u_mp.t0, g_pll[2].u_mp.t1, 200.0, 0.5);
    chk_freq("T1 u4 FOUTPOSTDIV (jitter on)", g_pll[4].u_mp.cnt, g_pll[4].u_mp.t0, g_pll[4].u_mp.t1, 200.0, 5.0);
    chk_val("T1 u4 FOUTPOSTDIV min period [ns]", g_pll[4].u_mp.pmin, 4.985, 0.016);
    chk_val("T1 u4 FOUTPOSTDIV max period [ns]", g_pll[4].u_mp.pmax, 5.015, 0.016);
    chk_val("T1 u4 FOUTVCO not generated (FOUTVCO_EN=0)", g_pll[4].u_mv.cnt, 0.0, 0.0);

    //--------------------------------------------------------------------------
    $display("---- T2 : fractional mode 25MHz x(49 + 2550137/2^24) /(4*2)");
    pd        = 1'b1;
    postdivpd = 1'b1;
    dsmpd     = 1'b0;
    fbdiv     = 12'd49;
    frac      = 24'd2550137;
    postdiv1  = 3'd4;
    postdiv2  = 3'd2;
    #100;
    pd = 1'b0;
    wait_lock(20000.0, tl);
    postdivpd = 1'b0;
    #100;
    fv = 25.0 * (49.0 + (2550137.0 / 16777216.0));
    meas(50000.0);
    chk_freq("T2 u0 FOUTVCO", g_pll[0].u_mv.cnt, g_pll[0].u_mv.t0, g_pll[0].u_mv.t1, fv, 0.05);
    chk_freq("T2 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, fv / 8.0, 0.05);

    //--------------------------------------------------------------------------
    $display("---- T3 : FRAC change on the fly (FRAC_RELOCK=0 : no relock)");
    lf   = lock_fall;
    frac = 24'd0;
    #1000;
    meas(20000.0);
    chk_val("T3 LOCK kept", lock_fall - lf, 0.0, 0.0);
    chk_freq("T3 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 25.0 * 49.0 / 8.0, 0.05);

    //--------------------------------------------------------------------------
    $display("---- T4 : POSTDIV then FBDIV changed while running (warnings expected)");
    lf       = lock_fall;
    postdiv1 = 3'd2;
    postdiv2 = 3'd4;
    #10;
    fbdiv    = 12'd40;
    #10;
    chk_val("T4 LOCK dropped", lock_fall - lf, 1.0, 0.0);
    wait_lock(20000.0, tl);
    #100;
    meas(20000.0);
    chk_freq("T4 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 125.0, 0.05);

    //--------------------------------------------------------------------------
    $display("---- T5 : FREF 25MHz -> 19.2MHz while running (period not on 1ps grid)");
    pd        = 1'b1;
    postdivpd = 1'b1;
    dsmpd     = 1'b1;
    fbdiv     = 12'd64;
    postdiv1  = 3'd4;
    postdiv2  = 3'd2;
    #100;
    pd = 1'b0;
    wait_lock(20000.0, tl);
    postdivpd = 1'b0;
    #100;
    fref_mhz = 19.2;
    #100;
    chk_val("T5 LOCK dropped by FREF change", lock[0], 0.0, 0.0);
    wait_lock(20000.0, tl);
    #100;
    meas(50000.0);
    chk_freq("T5 u0 FOUTVCO", g_pll[0].u_mv.cnt, g_pll[0].u_mv.t0, g_pll[0].u_mv.t1, 1228.8, 0.05);
    chk_freq("T5 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 153.6, 0.05);
    @(posedge fref);
    tr = $realtime;
    #0.002;
    chk_val("T5 FOUTVCO rise - FREF rise after 50us [ns]", t_vrise - tr, 0.0, 0.0015);

    //--------------------------------------------------------------------------
    $display("---- T6 : SSC (u3) 19.2MHz x62.5 /(3*2) , down-spread 5000ppm");
    pd        = 1'b1;
    postdivpd = 1'b1;
    dsmpd     = 1'b0;
    fbdiv     = 12'd62;
    frac      = 24'd8388608;
    postdiv1  = 3'd3;
    postdiv2  = 3'd2;
    #100;
    pd = 1'b0;
    wait_lock(20000.0, tl);
    postdivpd = 1'b0;
    #1000;
    meas(2.0e6 / 31.5);
    chk_freq("T6 u0 FOUTPOSTDIV (no SSC)", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 200.0, 0.05);
    chk_freq("T6 u3 FOUTPOSTDIV average", g_pll[3].u_mp.cnt, g_pll[3].u_mp.t0, g_pll[3].u_mp.t1, 200.0 * (1.0 - 0.0025), 5.0);
    chk_val("T6 u3 FOUTPOSTDIV min period [ns]", g_pll[3].u_mp.pmin, 5.0, 0.003);
    chk_val("T6 u3 FOUTPOSTDIV max period [ns]", g_pll[3].u_mp.pmax, 5.0 / (1.0 - 0.005), 0.003);

    //--------------------------------------------------------------------------
    $display("---- T7 : BYPASS (FOUTPOSTDIV = FREF, warnings expected)");
    bypass = 1'b1;
    #100;
    meas(10000.0);
    chk_freq("T7 u0 FOUTPOSTDIV = FREF", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 19.2, 0.05);
    bypass = 1'b0;
    #100;

    //--------------------------------------------------------------------------
    $display("---- T8 : POSTDIVPD on/off while locked");
    postdivpd = 1'b1;
    #10;
    meas(2000.0);
    chk_val("T8 FOUTPOSTDIV stopped", g_pll[0].u_mp.cnt, 0.0, 0.0);
    chk_val("T8 LOCK kept", lock[0], 1.0, 0.0);
    arm = 1'b1;
    #3;
    postdivpd = 1'b0;
    #2000;
    arm = 1'b0;
    chk_val("T8 restart min high [ns] (no runt)", g_pll[0].u_mp.hmin, 2.5, 0.002);
    chk_val("T8 restart min low [ns] (no runt)", g_pll[0].u_mp.lmin, 2.5, 0.002);

    //--------------------------------------------------------------------------
    $display("---- T9 : FREF stop / restart");
    fref_en = 1'b0;
    #1000;
    chk_val("T9 LOCK after FREF stop", lock[0], 0.0, 0.0);
    meas(1000.0);
    chk_val("T9 FOUTVCO stopped (mode0)", g_pll[0].u_mv.cnt, 0.0, 0.0);
    fref_en = 1'b1;
    wait_lock(20000.0, tl);
    chk_val("T9 LOCK after FREF restart", lock[0], 1.0, 0.0);

    //--------------------------------------------------------------------------
    $display("---- T10 : PD=1");
    pd = 1'b1;
    #1;
    chk_val("T10 LOCK after PD=1", lock[0], 0.0, 0.0);
    meas(1000.0);
    chk_val("T10 FOUTVCO stopped", g_pll[0].u_mv.cnt, 0.0, 0.0);

    //--------------------------------------------------------------------------
    $display("---- T11 : REFDIV=5 : 25MHz/5 x240 /(3*2)");
    fref_mhz = 25.0;
    refdiv   = 6'd5;
    fbdiv    = 12'd240;
    dsmpd    = 1'b1;
    postdiv1 = 3'd3;
    postdiv2 = 3'd2;
    #200;
    pd = 1'b0;
    wait_lock(50000.0, tl);
    #100;
    meas(20000.0);
    chk_freq("T11 u0 FOUTPOSTDIV", g_pll[0].u_mp.cnt, g_pll[0].u_mp.t0, g_pll[0].u_mp.t1, 200.0, 0.05);
    @(posedge fref);
    tr = $realtime;
    #0.002;
    chk_val("T11 FOUTVCO rise - FREF rise [ns]", t_vrise - tr, 0.0, 0.0015);
    pd = 1'b1;
    #100;

    //--------------------------------------------------------------------------
    $display("---- T12 : REFDIV=0 (ERROR messages are expected)");
    refdiv = 6'd0;
    #100;
    pd = 1'b0;
    #10000;
    chk_val("T12 no LOCK with REFDIV=0", lock[0], 0.0, 0.0);
    pd     = 1'b1;
    refdiv = 6'd1;

    //--------------------------------------------------------------------------
    $display("============================================================");
    if( err_cnt==0 ) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED : %0d error(s)", err_cnt);
    end
    $finish;
  end

endmodule
