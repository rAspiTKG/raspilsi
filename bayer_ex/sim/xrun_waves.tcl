# ============================================================================
# Xcelium の波形(SHM): make xrun XWAVES=shm で使う → waves.shm を SimVision で開く
#   GTKWave で見るときは XWAVES=vcd(tb_top が $dumpfile/$dumpvars で waves.vcd を書く)
# ============================================================================
database -open waves -into waves.shm -default
probe -create tb_top -depth all -all -database waves
run
exit
