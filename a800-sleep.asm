; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;
; SleepSec()
;     With a 64Mhz clock, this sleeps around 1 second. (979.701 ms according to simulator)
;
SleepSec:
    movlw   0xff
    movwf   slp_ctr0
    movwf   slp_ctr1
slp_loop:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    decfsz  slp_ctr0
    bra     slp_loop
    decfsz  slp_ctr1
    bra     slp_loop
    return
