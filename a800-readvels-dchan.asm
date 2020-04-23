; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

    ;
    ;    #####
    ;    #    #
    ;    #    #
    ;    #    #
    ;    #    #
    ;    #####
    ;
    ;   case 27: // await lsb chan 'B'
    ;       if ( is_strobe ) {            // STROBE from PC?
    ;           lsb       = IBMPC_DATA;
    ;           IBMPC_ACK = 1;            // ack lsb
    ;           state    += 1;            // advance to next state
    ;       } else {
    ;           lsb       = 0;            // NOP
    ;           IBMPC_ACK = 0;            // NOP
    ;           state    += 0;            // NOP
    ;       }
    ;

    ;
    ; CASE 27
    ;

rv_case_27:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv27_is_stb             ;   2     |  ; is_strobe?
    goto        rv27_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv27_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     9
rv27_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_lsb       ;   2     |  ; bus data -> LSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack lsb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 28
    ;

rv_case_28:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv28_is_stb             ;   2     |  ; is_strobe?
    goto        rv28_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv28_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv28_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until stb clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DONT advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry

    ;
    ; CASE 29
    ;

rv_case_29:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv29_is_stb             ;   2     |  ; is_strobe?
    goto        rv29_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv29_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     8
rv29_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_msb       ;   2     |  ; bus data -> MSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack msb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 30
    ;

rv_case_30:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv30_is_stb             ;   2     |  ; is_strobe?
    goto        rv30_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv30_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv30_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until stb clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DONT advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry

    ;
    ; --- The following case simply moves the received data from lsb/msb
    ; --- to the arrays. We do this separately to distribute the execution
    ; --- time of array updates to prevent jitter in motor steps.
    ; --- This code assumes on entry:
    ;         FSR0 -> vels[G_new_vix], where lsb -> FSR0 (vels)
    ;         FSR1 -> dirs[G_new_vix], where msb -> FSR1 (dirs)

    ;
    ; CASE 31
    ;
rv_case_31:
    ;                                   ; Cycles
    ;                                   ; ------
    nop                                 ;   1
    movlw       D_CHAN                  ;   1

    addwf       FSR0L,1                 ;   1   ; FSR0 -> vels[G_new_vix][A]
    movff       rv_lsb,INDF0            ;   2   ; lsb  -> vels[G_new_vix][A]

    addwf       FSR1L,1                 ;   1   ; FSR1 -> dirs[G_new_vix][A]
    movff       rv_msb,INDF1            ;   2   ; msb  -> dirs[G_new_vix][A]

    incf        rv_state                ;   1   ; Advance to next state
    return                              ; -----
                                        ;   9
