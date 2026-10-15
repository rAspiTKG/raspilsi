//==============================================================================
// pll_fracn_bm.sv
//------------------------------------------------------------------------------
// Fractional-N PLL behavioral model for logic simulation
//
//
//   FOUTVCO     = FREF / REFDIV * (FBDIV + FRAC/2^FRAC_W)   : DSMPD=0 (fractional)
//               = FREF / REFDIV * FBDIV                     : DSMPD=1 (integer)
//   FOUTPOSTDIV = FOUTVCO / (POSTDIV1 * POSTDIV2)            : BYPASS=0
//               = FREF                                       : BYPASS=1
//
// - This is NOT the vendor model. Align pin names, widths, limits and the
//   lock time with the datasheet of the licensed IP, and replace this model
//   with the vendor model when it is delivered.
// - The FREF period is measured continuously and the output phase is
//   re-anchored at every PFD edge with a 64bit fixed-point accumulator.
//   The output never drifts from FREF (a ppm offset of FREF appears on the
//   output as it does in hardware).
//==============================================================================
module pll_fracn_bm #(
  parameter int  REFDIV_W        = 6       // REFDIV width
 ,parameter int  FBDIV_W         = 12      // FBDIV (integer part) width
 ,parameter int  FRAC_W          = 24      // FRAC width (delta-sigma resolution)
 ,parameter int  POSTDIV_W       = 3       // POSTDIV1/POSTDIV2 width
 ,parameter int  LOCK_PFD_CYCLES = 500     // lock time [PFD cycles] (use datasheet value)
 ,parameter real LOCK_DLY_NS     = 0.1     // LOCK output delay (avoids same-time race)
 ,parameter int  PRELOCK_MODE    = 0       // output before LOCK 0:Low 1:X 2:frequency ramp
 ,parameter real RAMP_START      = 0.5     // PRELOCK_MODE=2 : start frequency / target
 ,parameter int  FRAC_RELOCK     = 0       // 1: FRAC change also causes relock
 ,parameter real FREF_TOL_PCT    = 1.0     // FREF period jump that causes relock [%]
 ,parameter int  REF_LOSS_CYCLES = 4       // missing FREF cycles that cause unlock (0:off)
 ,parameter real SSC_SPREAD_PPM  = 0.0     // spread spectrum amount (0.0:off)
 ,parameter real SSC_MOD_KHZ     = 31.5    // spread spectrum modulation frequency
 ,parameter int  SSC_DOWN        = 1       // 1:down-spread 0:center-spread
 ,parameter real JITTER_PS_PP    = 0.0     // output TIE jitter peak-to-peak (0.0:off)
 ,parameter int  FOUTVCO_EN      = 1       // 0: FOUTVCO is not generated (faster simulation)
 ,parameter real FREF_MIN_MHZ    = 0.0     // range checks (MAX=0.0 : check disabled)
 ,parameter real FREF_MAX_MHZ    = 0.0
 ,parameter real FPFD_MIN_MHZ    = 0.0
 ,parameter real FPFD_MAX_MHZ    = 0.0
 ,parameter real FVCO_MIN_MHZ    = 0.0
 ,parameter real FVCO_MAX_MHZ    = 0.0
 ,parameter real FOUT_MIN_MHZ    = 0.0
 ,parameter real FOUT_MAX_MHZ    = 0.0
 ,parameter int  FBDIV_MIN       = 0       // FBDIV range, integer mode (MAX=0 : disabled)
 ,parameter int  FBDIV_MAX       = 0
 ,parameter int  FBDIV_FRAC_MIN  = 0       // FBDIV range, fractional mode (MAX=0 : disabled)
 ,parameter int  FBDIV_FRAC_MAX  = 0
 ,parameter int  CHECK_EN        = 1       // 1: setting / sequence checks
 ,parameter int  VERBOSE         = 0       // 1: print frequencies and LOCK
) (
  input  logic                 FREF        // reference clock
 ,input  logic                 PD          // 1: PLL power down
 ,input  logic                 VCOPD       // 1: VCO power down
 ,input  logic                 POSTDIVPD   // 1: post divider power down
 ,input  logic                 DSMPD       // 1: integer mode (DSM off) / 0: fractional mode
 ,input  logic                 BYPASS      // 1: FOUTPOSTDIV = FREF
 ,input  logic [REFDIV_W-1:0]  REFDIV      // reference divider (1-)
 ,input  logic [FBDIV_W-1:0]   FBDIV       // feedback divider, integer part
 ,input  logic [FRAC_W-1:0]    FRAC        // feedback divider, fraction (/2^FRAC_W)
 ,input  logic [POSTDIV_W-1:0] POSTDIV1    // post divider 1 (1-)
 ,input  logic [POSTDIV_W-1:0] POSTDIV2    // post divider 2 (1-)
 ,output logic                 FOUTPOSTDIV // primary output
 ,output logic                 FOUTVCO     // VCO output
 ,output logic                 LOCK        // lock detect
);

  timeunit      1ns;
  timeprecision 1ps;

  //----------------------------------------------------------------------------
  // constants
  //----------------------------------------------------------------------------
  localparam int  ST_OFF = 0;              // powered down
  localparam int  ST_ACQ = 1;              // acquiring lock
  localparam int  ST_TRK = 2;              // locked (phase tracking)
  localparam real QONE_R = 2.0**FRAC_W;    // 1.0 in Q(FRAC_W)

  //----------------------------------------------------------------------------
  // internal state
  //----------------------------------------------------------------------------
  int     st       = ST_OFF;
  int     run_ep   = 0;      // epoch of output generation
  int     lock_cnt = 0;      // PFD cycles counted in ST_ACQ
  logic   lock_q   = 1'b0;
  logic   cfg_err  = 1'b0;   // invalid setting already reported
  logic   th_ok    = 1'b0;   // th_tgt is valid
  // FREF measurement
  logic   ref_seen = 1'b0;
  logic   ref_ok   = 1'b0;
  real    ref_t    = 0.0;
  real    ref_per  = 0.0;
  int     ref_cnt  = 0;      // REFDIV prescaler
  // PFD
  logic   pfd_seen = 1'b0;
  logic   pfd_ok   = 1'b0;
  real    pfd_t    = 0.0;
  real    pfd_t1st = 0.0;    // first PFD edge of the lock sequence
  real    pfd_per  = 0.0;
  // phase anchor (ST_TRK)
  real    anc_t    = 0.0;    // time of the latest PFD edge
  longint anc_hq   = 0;      // VCO phase at anc_t [half cycle, Q(FRAC_W)]
  longint inc_q    = 0;      // VCO phase advance in this PFD cycle
  real    th       = 1.0;    // VCO half period in this PFD cycle [ns]
  real    th_tgt   = 1.0;    // VCO half period without SSC [ns]
  real    ssc_p    = 0.0;    // SSC modulation phase (0.0-1.0)
  // generated clocks
  logic   vco_clk  = 1'b0;
  logic   post_clk = 1'b0;
  real    vco_tl   = 0.0;    // time of the last vco_clk edge
  real    post_tl  = 0.0;    // time of the last post_clk edge
  wire    vco_run;
  wire    post_run;
  // outputs (initialized to 0 at time 0)
  logic   fvco_o   = 1'b0;
  logic   fpost_o  = 1'b0;
  logic   lock_o   = 1'b0;

  //----------------------------------------------------------------------------
  // functions
  //----------------------------------------------------------------------------
  // total post division (0: invalid)
  function automatic int div_total(
    input logic [POSTDIV_W-1:0] p1
   ,input logic [POSTDIV_W-1:0] p2
  );
    int a;
    int b;
    begin
      if( (^{p1,p2})===1'bx ) begin
        return 0;
      end
      a = p1;
      b = p2;
      return a * b;
    end
  endfunction

  // multiplication factor (FBDIV + FRAC/2^FRAC_W) in Q(FRAC_W)
  function automatic longint mult_q();
    longint q;
    longint f;
    begin
      q = FBDIV;
      q = q << FRAC_W;
      if( DSMPD===1'b0 ) begin
        f = FRAC;
        q = q + f;
      end
      return q;
    end
  endfunction

  // time of VCO half-cycle index h
  function automatic real idx_time( input longint h );
    longint dq;
    real    rdq;
    begin
      dq  = (h << FRAC_W) - anc_hq;
      rdq = dq;
      return anc_t + ((rdq / QONE_R) * th);
    end
  endfunction

  // first index (multiple of step) after the current phase
  function automatic longint next_idx( input longint step );
    real    ph;
    real    rs;
    longint n;
    begin
      ph = anc_hq;
      rs = step;
      ph = (ph / QONE_R) + (($realtime - anc_t) / th);
      n  = $floor(ph / rs);
      return (n + 1) * step;
    end
  endfunction

  // VCO phase advance of one PFD cycle (SSC applied)
  function automatic longint calc_inc( input longint mq );
    real    tv;
    real    dev;
    real    r;
    longint q;
    begin
      if( (SSC_SPREAD_PPM<=0.0)||(DSMPD!==1'b0) ) begin
        return mq << 1;
      end
      if( ssc_p<0.5 ) begin
        tv = 2.0 * ssc_p;
      end else begin
        tv = 2.0 - (2.0 * ssc_p);
      end
      if( SSC_DOWN!=0 ) begin
        dev = SSC_SPREAD_PPM * 1.0e-6 * tv;
      end else begin
        dev = SSC_SPREAD_PPM * 1.0e-6 * (tv - 0.5);
      end
      r = mq;
      r = 2.0 * r * (1.0 - dev);
      q = r;
      return q;
    end
  endfunction

  // half period during the frequency ramp (PRELOCK_MODE=2)
  function automatic real ramp_th();
    real prog;
    begin
      prog = 1.0;
      if( LOCK_PFD_CYCLES>0 ) begin
        prog = lock_cnt;
        prog = prog / LOCK_PFD_CYCLES;
        if( prog>1.0 ) begin
          prog = 1.0;
        end
      end
      return th_tgt / (RAMP_START + ((1.0 - RAMP_START) * prog));
    end
  endfunction

  // output TIE jitter [ns]
  function automatic real jit();
    real r;
    begin
      if( JITTER_PS_PP<=0.0 ) begin
        return 0.0;
      end
      r = $urandom_range(1000000, 0);
      r = (r / 1000000.0) - 0.5;
      return r * JITTER_PS_PP * 1.0e-3;
    end
  endfunction

  //----------------------------------------------------------------------------
  // tasks
  //----------------------------------------------------------------------------
  task automatic chk_range(
    input string name
   ,input real   v
   ,input real   vmin
   ,input real   vmax
  );
    begin
      if( (vmax>0.0)&&((v<vmin)||(v>vmax)) ) begin
        $error("%m: %s = %0.6f MHz is out of range (%0.3f - %0.3f MHz)", name, v, vmin, vmax);
      end
    end
  endtask

  // frequency / setting check (once per lock sequence, per = average PFD period)
  task automatic check_cfg( input real per );
    real f_ref;
    real f_pfd;
    real f_vco;
    real f_out;
    real m;
    int  d;
    begin
      m     = mult_q();
      m     = m / QONE_R;
      d     = div_total(POSTDIV1, POSTDIV2);
      f_pfd = 1.0e3 / per;
      f_ref = f_pfd * REFDIV;
      f_vco = f_pfd * m;
      f_out = 0.0;
      if( d>0 ) begin
        f_out = f_vco / d;
      end
      if( VERBOSE!=0 ) begin
        $display("%m: @%0.3fns FREF=%0.6f FPFD=%0.6f FVCO=%0.6f FOUTPOSTDIV=%0.6f [MHz] DSMPD=%0b", $realtime, f_ref, f_pfd, f_vco, f_out, DSMPD);
      end
      if( CHECK_EN!=0 ) begin
        chk_range("FREF", f_ref, FREF_MIN_MHZ, FREF_MAX_MHZ);
        chk_range("FPFD(FREF/REFDIV)", f_pfd, FPFD_MIN_MHZ, FPFD_MAX_MHZ);
        chk_range("FVCO", f_vco, FVCO_MIN_MHZ, FVCO_MAX_MHZ);
        if( d>0 ) begin
          chk_range("FOUTPOSTDIV", f_out, FOUT_MIN_MHZ, FOUT_MAX_MHZ);
        end
        if( DSMPD===1'b1 ) begin
          if( (FBDIV_MAX>0)&&((FBDIV<FBDIV_MIN)||(FBDIV>FBDIV_MAX)) ) begin
            $error("%m: FBDIV=%0d is out of range for integer mode (%0d - %0d)", FBDIV, FBDIV_MIN, FBDIV_MAX);
          end
        end else begin
          if( (FBDIV_FRAC_MAX>0)&&((FBDIV<FBDIV_FRAC_MIN)||(FBDIV>FBDIV_FRAC_MAX)) ) begin
            $error("%m: FBDIV=%0d is out of range for fractional mode (%0d - %0d)", FBDIV, FBDIV_FRAC_MIN, FBDIV_FRAC_MAX);
          end
        end
        if( (d>0)&&(POSTDIV1<POSTDIV2) ) begin
          $warning("%m: POSTDIV1(%0d) < POSTDIV2(%0d). POSTDIV1 >= POSTDIV2 is recommended", POSTDIV1, POSTDIV2);
        end
        if( (SSC_SPREAD_PPM>0.0)&&(DSMPD!==1'b0) ) begin
          $warning("%m: spread spectrum needs fractional mode (DSMPD=0). SSC is not applied");
        end
      end
    end
  endtask

  // -> ST_OFF
  task automatic go_off();
    begin
      st       = ST_OFF;
      lock_q   = 1'b0;
      lock_cnt = 0;
      th_ok    = 1'b0;
      vco_clk  = 1'b0;
      post_clk = 1'b0;
      run_ep   = run_ep + 1;
    end
  endtask

  // -> ST_ACQ (restart lock sequence)
  task automatic go_acq();
    begin
      st       = ST_ACQ;
      lock_q   = 1'b0;
      lock_cnt = 0;
      th_ok    = 1'b0;
      cfg_err  = 1'b0;
      pfd_seen = 1'b0;
      pfd_ok   = 1'b0;
      ref_cnt  = 0;
      run_ep   = run_ep + 1;
    end
  endtask

  // PFD edge (every REFDIV FREF cycles)
  task automatic pfd_edge( input real tnow );
    longint mq;
    real    rmq;
    real    rinc;
    begin
      if( pfd_seen==1'b1 ) begin
        pfd_per = tnow - pfd_t;
        pfd_ok  = 1'b1;
      end else begin
        pfd_t1st = tnow;
      end
      pfd_t    = tnow;
      pfd_seen = 1'b1;
      if( pfd_ok==1'b1 ) begin
        if( ((^{FBDIV,DSMPD})===1'bx)||(FBDIV==0)||((DSMPD===1'b0)&&((^FRAC)===1'bx)) ) begin
          if( cfg_err==1'b0 ) begin
            $error("%m: invalid FBDIV/FRAC/DSMPD setting. PLL does not lock");
            cfg_err = 1'b1;
          end
        end else begin
          mq     = mult_q();
          rmq    = mq;
          th_tgt = (pfd_per * QONE_R) / (2.0 * rmq);
          th_ok  = 1'b1;
          if( st==ST_ACQ ) begin
            lock_cnt = lock_cnt + 1;
            if( lock_cnt>=LOCK_PFD_CYCLES ) begin
              check_cfg((tnow - pfd_t1st) / lock_cnt);
              // start phase-locked output : index 0 = rising edge at this PFD edge
              st      = ST_TRK;
              run_ep  = run_ep + 1;
              anc_t   = tnow;
              anc_hq  = 0;
              ssc_p   = 0.0;
              inc_q   = calc_inc(mq);
              rinc    = inc_q;
              th      = (pfd_per * QONE_R) / rinc;
              vco_clk = 1'b1;
              vco_tl  = tnow;
              if( POSTDIVPD===1'b0 ) begin
                post_clk = 1'b1;
                post_tl  = tnow;
              end
            end
          end else if( st==ST_TRK ) begin
            // re-anchor the phase on this PFD edge
            anc_hq = anc_hq + inc_q;
            anc_t  = tnow;
            if( SSC_SPREAD_PPM>0.0 ) begin
              ssc_p = ssc_p + (pfd_per * SSC_MOD_KHZ * 1.0e-6);
              if( ssc_p>=1.0 ) begin
                ssc_p = ssc_p - 1.0;
              end
            end
            inc_q = calc_inc(mq);
            rinc  = inc_q;
            th    = (pfd_per * QONE_R) / rinc;
            // LOCK is asserted one PFD cycle after the output starts
            if( lock_q==1'b0 ) begin
              lock_q = 1'b1;
              if( VERBOSE!=0 ) begin
                $display("%m: LOCK=1 @%0.3fns", $realtime);
              end
            end
          end
        end
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // power control
  //----------------------------------------------------------------------------
  always @(PD or VCOPD) begin : p_pwr
    if( (PD===1'b0)&&(VCOPD===1'b0) ) begin
      if( st==ST_OFF ) begin
        go_acq();
      end
    end else begin
      if( st!=ST_OFF ) begin
        go_off();
      end
    end
  end

  //----------------------------------------------------------------------------
  // setting changes
  //----------------------------------------------------------------------------
  always @(REFDIV or FBDIV or DSMPD) begin : p_cfg
    if( st!=ST_OFF ) begin
      if( (CHECK_EN!=0)&&($realtime>0.0) ) begin
        $warning("%m: REFDIV/FBDIV/DSMPD changed while running. PLL relocks (output is unpredictable until LOCK=1)");
      end
      go_acq();
    end
  end

  always @(FRAC) begin : p_frac
    if( (st!=ST_OFF)&&(DSMPD===1'b0)&&(FRAC_RELOCK!=0) ) begin
      go_acq();
    end
  end

  always @(POSTDIV1 or POSTDIV2) begin : p_postdiv
    if( (CHECK_EN!=0)&&($realtime>0.0)&&(st==ST_TRK)&&(POSTDIVPD===1'b0)&&(BYPASS===1'b0) ) begin
      $warning("%m: POSTDIV1/POSTDIV2 changed while FOUTPOSTDIV is running. Set POSTDIVPD=1 before changing");
    end
  end

  always @(BYPASS) begin : p_bypass
    if( (CHECK_EN!=0)&&($realtime>0.0)&&(st==ST_TRK)&&(POSTDIVPD===1'b0)&&(ref_ok==1'b1) ) begin
      $warning("%m: BYPASS changed while running. FOUTPOSTDIV may glitch");
    end
  end

  always @(posedge POSTDIVPD) begin : p_postdivpd
    post_clk = 1'b0;
  end

  //----------------------------------------------------------------------------
  // FREF measurement / REFDIV prescaler / lock control
  //----------------------------------------------------------------------------
  always @(posedge FREF) begin : p_ref
    real tnow;
    real per;
    real tol;
    int  rdiv;
    tnow = $realtime;
    // power state (also recovers an event missed at time 0)
    if( (PD===1'b0)&&(VCOPD===1'b0) ) begin
      if( st==ST_OFF ) begin
        go_acq();
      end
    end else begin
      if( st!=ST_OFF ) begin
        go_off();
      end
    end
    // FREF period
    if( ref_seen==1'b1 ) begin
      per = tnow - ref_t;
      tol = ref_per * FREF_TOL_PCT * 0.01;
      if( (ref_ok==1'b1)&&(FREF_TOL_PCT>0.0)&&((per>(ref_per+tol))||(per<(ref_per-tol))) ) begin
        if( st!=ST_OFF ) begin
          if( CHECK_EN!=0 ) begin
            $warning("%m: FREF period changed (%0.4fns -> %0.4fns). PLL relocks", ref_per, per);
          end
          go_acq();
        end
      end
      ref_per = per;
      ref_ok  = 1'b1;
    end
    ref_t    = tnow;
    ref_seen = 1'b1;
    // REFDIV prescaler -> PFD edge
    if( st!=ST_OFF ) begin
      if( ((^REFDIV)===1'bx)||(REFDIV==0) ) begin
        if( cfg_err==1'b0 ) begin
          $error("%m: invalid REFDIV (%0d). PLL does not lock", REFDIV);
          cfg_err = 1'b1;
        end
      end else begin
        rdiv    = REFDIV;
        ref_cnt = ref_cnt + 1;
        if( ref_cnt>=rdiv ) begin
          ref_cnt = 0;
          pfd_edge(tnow);
        end
      end
    end
  end

  // FREF loss detection
  initial begin : p_ref_wdt
    real tw;
    forever begin
      if( (ref_ok==1'b1)&&(REF_LOSS_CYCLES>0) ) begin
        tw = ref_per * REF_LOSS_CYCLES;
        #(tw);
        if( (ref_ok==1'b1)&&(($realtime-ref_t)>tw) ) begin
          if( st!=ST_OFF ) begin
            if( CHECK_EN!=0 ) begin
              $warning("%m: FREF stopped. LOCK is deasserted");
            end
            go_acq();
          end
          ref_ok   = 1'b0;
          ref_seen = 1'b0;
        end
      end else begin
        @(posedge FREF);
      end
    end
  end

  //----------------------------------------------------------------------------
  // FOUTVCO generator
  //----------------------------------------------------------------------------
  assign vco_run = ((st==ST_TRK)||((st==ST_ACQ)&&(PRELOCK_MODE==2)&&(th_ok==1'b1))) ? 1'b1 : 1'b0;

  initial begin : g_vco
    int     ep;
    longint h;
    real    tev;
    real    tmin;
    logic   lv;
    forever begin
      wait( (vco_run==1'b1)&&(FOUTVCO_EN!=0) );
      ep = run_ep;
      if( st==ST_TRK ) begin
        // phase-locked : edge of half-cycle index h (even index = rising)
        h = next_idx(1);
        while( (st==ST_TRK)&&(ep==run_ep) ) begin
          tev  = idx_time(h) + jit();
          tmin = vco_tl + (0.5 * th);
          if( tev<tmin ) begin
            tev = tmin;
          end
          if( tev<=$realtime ) begin
            tev = $realtime + (0.5 * th);
          end
          #(tev - $realtime);
          if( (st==ST_TRK)&&(ep==run_ep) ) begin
            lv = ((h % 2)==0) ? 1'b1 : 1'b0;
            if( vco_clk!==lv ) begin
              vco_clk = lv;
              vco_tl  = $realtime;
            end
          end
          h = h + 1;
        end
      end else begin
        // acquisition : free-running frequency ramp (PRELOCK_MODE=2)
        while( (st==ST_ACQ)&&(ep==run_ep)&&(vco_run==1'b1) ) begin
          #(ramp_th());
          if( (st==ST_ACQ)&&(ep==run_ep) ) begin
            vco_clk = ~vco_clk;
            vco_tl  = $realtime;
          end
        end
      end
    end
  end

  //----------------------------------------------------------------------------
  // FOUTPOSTDIV generator (POSTDIV1*POSTDIV2, 50% duty for odd ratios too)
  //----------------------------------------------------------------------------
  assign post_run = ((vco_run==1'b1)&&(POSTDIVPD===1'b0)&&(div_total(POSTDIV1,POSTDIV2)>0)) ? 1'b1 : 1'b0;

  initial begin : g_post
    int     ep;
    int     d;
    int     dn;
    longint h;
    real    tev;
    real    tmin;
    logic   lv;
    forever begin
      wait( post_run==1'b1 );
      ep = run_ep;
      d  = div_total(POSTDIV1, POSTDIV2);
      if( st==ST_TRK ) begin
        // phase-locked : edge every d VCO half cycles
        h = next_idx(d);
        while( (st==ST_TRK)&&(ep==run_ep)&&(post_run==1'b1) ) begin
          tev  = idx_time(h) + jit();
          tmin = post_tl + (0.5 * th * d);
          if( tev<tmin ) begin
            tev = tmin;
          end
          if( tev<=$realtime ) begin
            tev = $realtime + (0.5 * th * d);
          end
          #(tev - $realtime);
          if( (st==ST_TRK)&&(ep==run_ep)&&(post_run==1'b1) ) begin
            lv = (((h / d) % 2)==0) ? 1'b1 : 1'b0;
            if( post_clk!==lv ) begin
              post_clk = lv;
              post_tl  = $realtime;
            end
          end
          dn = div_total(POSTDIV1, POSTDIV2);
          if( (dn>0)&&(dn!=d) ) begin
            d = dn;
            h = ((h / d) + 1) * d;
          end else begin
            h = h + d;
          end
        end
      end else begin
        // acquisition : free-running frequency ramp (PRELOCK_MODE=2)
        while( (st==ST_ACQ)&&(ep==run_ep)&&(post_run==1'b1) ) begin
          #(ramp_th() * d);
          if( (st==ST_ACQ)&&(ep==run_ep)&&(post_run==1'b1) ) begin
            post_clk = ~post_clk;
            post_tl  = $realtime;
          end
          dn = div_total(POSTDIV1, POSTDIV2);
          if( dn>0 ) begin
            d = dn;
          end
        end
      end
    end
  end

  //----------------------------------------------------------------------------
  // outputs
  //----------------------------------------------------------------------------
  always @(*) begin : p_out
    // FOUTVCO
    if( FOUTVCO_EN==0 ) begin
      fvco_o = 1'b0;
    end else if( st==ST_TRK ) begin
      fvco_o = vco_clk;
    end else if( (st==ST_ACQ)&&(PRELOCK_MODE==1) ) begin
      fvco_o = 1'bx;
    end else if( (st==ST_ACQ)&&(PRELOCK_MODE==2)&&(th_ok==1'b1) ) begin
      fvco_o = vco_clk;
    end else begin
      fvco_o = 1'b0;
    end
    // FOUTPOSTDIV
    if( BYPASS===1'b1 ) begin
      fpost_o = FREF;
    end else if( BYPASS!==1'b0 ) begin
      fpost_o = 1'bx;
    end else if( (st==ST_OFF)||(POSTDIVPD===1'b1) ) begin
      fpost_o = 1'b0;
    end else if( (POSTDIVPD!==1'b0)||(div_total(POSTDIV1,POSTDIV2)==0) ) begin
      fpost_o = 1'bx;
    end else if( st==ST_TRK ) begin
      fpost_o = post_clk;
    end else if( PRELOCK_MODE==1 ) begin
      fpost_o = 1'bx;
    end else if( (PRELOCK_MODE==2)&&(th_ok==1'b1) ) begin
      fpost_o = post_clk;
    end else begin
      fpost_o = 1'b0;
    end
  end

  // LOCK : small delay avoids a same-time race with the output clock edge
  always @(lock_q) begin : p_lock
    lock_o <= #(LOCK_DLY_NS) lock_q;
  end

  assign FOUTVCO     = fvco_o;
  assign FOUTPOSTDIV = fpost_o;
  assign LOCK        = lock_o;

endmodule
