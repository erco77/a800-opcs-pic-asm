; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Sync() - Synchronize the two A800 cpus
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CpuSync:
#if BUILD_CPU == 1
    ;
    ;  ####   #####   #    #    #
    ; #    #  #    #  #    #   ##
    ; #       #    #  #    #  # #
    ; #       #####   #    #    #
    ; #    #  #       #    #    #
    ;  ####   #        ####   #####
    ;
    bsf         SET_SYNC        ; tell cpu2 we're syncing: set sync (LATA,5)=1
cs_loop1:
    btfss       IS_ACK          ; Bit Test File, Skip If Set: (PORTA,6)==1?
    bra         cs_loop1        ; clr? wait until set
    bcf         SET_SYNC        ; un-sync (LATA,5)=0
cs_loop2:
    btfsc       IS_ACK          ; Bit Test File, Skip If Clr: (PORTA,6)==0?
    bra         cs_loop2        ; set? wait until clr
    return
#else
    ;
    ;  ####   #####   #    #   ####
    ; #    #  #    #  #    #  #    #
    ; #       #    #  #    #       #
    ; #       #####   #    #   ####
    ; #    #  #       #    #  #
    ;  ####   #        ####   ######
cs_loop1:
    btfss       IS_SYNC         ; Bit Test File, Skip If Set: (PORTA,6)==0?
    bra         cs_loop1        ; clr? wait until set
    bsf         SET_ACK         ; set? ack (LATA,5)=1
cs_loop2:
    btfsc       IS_SYNC         ; Bit Test File, Skip If Set: (PORTA,6)==0?
    bra         cs_loop2        ; clr? wait until set
    bcf         SET_ACK         ; un-ack (LATA,5)=0
    nop                         ; allow time for CPU1 to see ACK
    return
#endif
