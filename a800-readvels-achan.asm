; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

    ;
    ;     ##
    ;    #  #
    ;   #    #
    ;   ######
    ;   #    #
    ;   #    #
    ;
    ;   case 12: // await lsb chan 'A'
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
    ; CASE 12
    ;

rv_case_12:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv12_is_stb             ;   2     |  ; is_strobe?
    goto        rv12_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv12_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     9
rv12_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_lsb       ;   2     |  ; bus data -> LSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack lsb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 13
    ;

rv_case_13:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv13_is_stb             ;   2     |  ; is_strobe?
    goto        rv13_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv13_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv13_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until stb clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DONT advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry

    ;
    ; CASE 14
    ;

rv_case_14:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv14_is_stb             ;   2     |  ; is_strobe?
    goto        rv14_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv14_not_is_stb:
    ; No strobe yet? wait for it
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DONT advance state
    return                              ;   |   -----
                                        ;   |     9
rv14_is_stb:
    nop                                 ;   1     |
    ; // check if host lowered STROBE and START
    movff       IBMPC_DATA,rv_msb       ;   2     |  ; bus data -> MSB
    bsf         IBMPC_ACK_BIT           ;   1     |  ; ack msb
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
    ;
    ; CASE 15
    ;

rv_case_15:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv15_is_stb             ;   2     |  ; is_strobe?
    goto        rv15_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv15_not_is_stb:
    ; PC lowered STROBE (ack recvd)
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; un-ack
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv15_is_stb:
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
    ; CASE 16
    ;
rv_case_16:
    ;                                   ; Cycles
    ;                                   ; ------
    nop                                 ;   1
    movlw       A_CHAN                  ;   1

    addwf       FSR0L,1                 ;   1   ; FSR0 -> vels[G_new_vix][A]
    movff       rv_lsb,INDF0            ;   2   ; lsb  -> vels[G_new_vix][A]

    addwf       FSR1L,1                 ;   1   ; FSR1 -> dirs[G_new_vix][A]
    movff       rv_msb,INDF1            ;   2   ; msb  -> dirs[G_new_vix][A]

    incf        rv_state                ;   1   ; Advance to next state
    return                              ; -----
                                        ;   9
