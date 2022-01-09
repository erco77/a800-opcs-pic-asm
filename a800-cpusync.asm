; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Sync() - Synchronize the two A800 cpus
;;
;          In REV-A, syncing is only done once on boot.
;          Previously this was called each iteration.
;
;          In REV-A, RA3 is used to auto-detect if we're CPU1 or CPU2.
;          RA3: 1=cpu1, 0=cpu2.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CpuSync:
    btfss       CPU_ID          ; Bit Test File, Skip If Set: (PORTA,3)==?
    bra         cpu2_sync       ; clr? cpu2 sync
cpu1_sync:                      ; set? cpu1 sync
    ;
    ;  ####   #####   #    #    #
    ; #    #  #    #  #    #   ##
    ; #       #    #  #    #  # #
    ; #       #####   #    #    #
    ; #    #  #       #    #    #
    ;  ####   #        ####   #####
    ;
    bsf         SET_SYNC        ; tell cpu2 we're syncing: set sync (LATA,5)=1
cpu1_cs_loop1:
    btfss       IS_ACK          ; Bit Test File, Skip If Set: (PORTA,6)==?
    bra         cpu1_cs_loop1   ; clr? wait until set
    bcf         SET_SYNC        ; set? un-sync (LATA,5)=0
cpu1_cs_loop2:
    btfsc       IS_ACK          ; Bit Test File, Skip If Clr: (PORTA,6)==?
    bra         cpu1_cs_loop2   ; set? wait until clr
    return                      ; clr? done

cpu2_sync:
    ;
    ;  ####   #####   #    #   ####
    ; #    #  #    #  #    #  #    #
    ; #       #    #  #    #       #
    ; #       #####   #    #   ####
    ; #    #  #       #    #  #
    ;  ####   #        ####   ######
cpu2_cs_loop1:
    btfss       IS_SYNC         ; Bit Test File, Skip If Set: (PORTA,6)==?
    bra         cpu2_cs_loop1   ; clr? wait until set
    bsf         SET_ACK         ; set? ack (LATA,5)=1
cpu2_cs_loop2:
    btfsc       IS_SYNC         ; Bit Test File, Skip If Set: (PORTA,6)==?
    bra         cpu2_cs_loop2   ; clr? wait until set
    bcf         SET_ACK         ; set? un-ack (LATA,5)=0
    nop                         ; allow time for CPU1 to see ACK
    return
