; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

    ;
    ;    #####
    ;    #    #
    ;    #####
    ;    #    #
    ;    #    #
    ;    #####
    ;
    ;   case 17: // await lsb chan 'B'
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
    ; CASE 17
    ;

rv_case_17:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv17_is_stb             ;   2     |  ; is_strobe?
    goto        rv17_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv17_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     9
rv17_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_lsb       ;   2     |  ; bus data -> LSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack lsb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 18
    ;

rv_case_18:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv18_is_stb             ;   2     |  ; is_strobe?
    goto        rv18_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv18_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv18_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until stb clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DONT advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry

    ;
    ; CASE 19
    ;

rv_case_19:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv19_is_stb             ;   2     |  ; is_strobe?
    goto        rv19_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv19_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     9
rv19_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_msb       ;   2     |  ; bus data -> MSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack msb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 20
    ;

rv_case_20:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv20_is_stb             ;   2     |  ; is_strobe?
    goto        rv20_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv20_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv20_is_stb:
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
    ; CASE 21
    ;
rv_case_21:
    ;                                   ; Cycles
    ;                                   ; ------
    nop                                 ;   1
    movlw       B_CHAN                  ;   1

    addwf       FSR0L,1                 ;   1   ; FSR0 -> vels[G_new_vix][A]
    movff       rv_lsb,INDF0            ;   2   ; lsb  -> vels[G_new_vix][A]

    addwf       FSR1L,1                 ;   1   ; FSR1 -> dirs[G_new_vix][A]
    movff       rv_msb,INDF1            ;   2   ; msb  -> dirs[G_new_vix][A]

    incf        rv_state                ;   1   ; Advance to next state
    return                              ; -----
                                        ;   9
