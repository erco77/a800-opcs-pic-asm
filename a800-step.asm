; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; FUNCTION:
;     Step(uchar chan, uchar dir, uchar val)
;     Step the motor one pulse. We handle inverting the dir and step bits
;     because the Geckos are active low (negative logic), where 1=hi=led off, 0=lo=led-on.
;
;     Expects these values to be set on input:
;         > stp_arg_chan - channel to manage (0=A, 1=B.. 3=D)
;         > stp_arg_dir  - direction to run  (0x00=fwd, 0x80=reverse)
;         > stp_arg_step - step value        (0x00=no step, 0x01=step)
;         > BSR pointing to bank for all A800 variables (e.g. 'banksel stp_arg_step)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Step:
;
; A channel
;
    ; case 0:
    ;      G_portb.bits.b0 = val;
    ;      G_portb.bits.b1 = dir ^ 1;
    ;      return;
    ;                           ; --- Cycles ----
    ;                           ; IsChan  NotChan
    ;                           ; ------  -------
    movlw  0x00                 ;    1       1
    cpfseq stp_arg_chan         ;    3       1   ; Compare File Skip if EQual (CPFSEQ)
    goto   st_b_chk             ;    |       2   ; !=0: check next chan
                                ; ------  -------
                                ;    4       4   <-- symmetry

    ; G_portb.bits.b0 = val;    ; step?   nostep?
    ;                           ; -----   -------
    bsf    A_STEP_BIT           ;   1        1   ; assume no step (set=1=hi=gecko led off)
    btfsc  stp_arg_step,0       ;   1        2   ; Bit Test Skip if Clear: Check bit zero
    bcf    A_STEP_BIT           ;   1        0   ; Bit Clear File: step=low (Gecko's are ACTIVE LOW)
                                ; ------  -------
                                ;   3        3   <-- symmetry

    ; G_portb.bits.b1 = dir ^ 1; // INVERT: Geckos are *ACTIVE LOW*
    ;                           ; a_rev    a_fwd
    ;                           ; -----    -----
    bsf    A_DIR_BIT            ;   1        1   ; assume dirs[] bit off, make bit hi (hi=fwd)
    btfsc  stp_arg_dir,7        ;   1        2   ; test bit 7 (0x8000): Is dir bit on (REV)?
    bcf    A_DIR_BIT            ;   1        0   ; yes, make bit lo (lo=rev)
    goto   st_b_chk             ;   2        2
                                ; -----    -----
                                ;   5        5
;
; B channel
;
st_b_chk:
    movlw  0x01
    cpfseq stp_arg_chan
    goto   st_c_chk
    bsf    B_STEP_BIT
    btfsc  stp_arg_step,0
    bcf    B_STEP_BIT
    bsf    B_DIR_BIT
    btfsc  stp_arg_dir,7
    bcf    B_DIR_BIT
    goto   st_c_chk
;
; C channel
;
st_c_chk:
    movlw  0x02
    cpfseq stp_arg_chan
    goto   st_d_chk
    bsf    C_STEP_BIT
    btfsc  stp_arg_step,0
    bcf    C_STEP_BIT
    bsf    C_DIR_BIT
    btfsc  stp_arg_dir,7
    bcf    C_DIR_BIT
    goto   st_d_chk
;
; D channel
;
st_d_chk:
    movlw  0x03
    cpfseq stp_arg_chan
    goto   st_done
    bsf    D_STEP_BIT
    btfsc  stp_arg_step,0
    bcf    D_STEP_BIT
    bsf    D_DIR_BIT
    btfsc  stp_arg_dir,7
    bcf    D_DIR_BIT
    goto   st_done

st_done:
    return
