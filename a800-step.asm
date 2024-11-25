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
; NOTE: Step/Direction logic is double-negative logic (postive logic!)
; because the PIC bit is inverted by the 74HCT04, then inverted *again*
; because the Gecko/Centent drive optocouplers are active LOW.
; Which means:
;       > BCF - turns step drive optocoupler OFF (PIC out=0 -> 7404 out=1 -> opto=off)
;       > BSF - turns step drive optocoupler ON  (PIC out=1 -> 7404 out=0 -> opto=on)
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
    movlw  0x00                 ;    1       1   ; Is stp_arg_chan == A channel(0)?
    cpfseq stp_arg_chan         ;    3       1   ; Compare File Skip if EQual (CPFSEQ)
    goto   st_b_chk             ;    |       2   ; !=0: check next chan for symmetry
                                ; ------  -------
                                ;    4       4   <-- symmetry

    ; G_portb.bits.b0 = val;    ; step?   nostep?
    ;                           ; -----   -------
    bcf    A_STEP_BIT           ;   1        1   ; Bit Clr File: assume A STEP=off
    btfsc  stp_arg_step,0       ;   1        2   ; Bit Test Skip if Clear: skip if step not set
    bsf    A_STEP_BIT           ;   1        0   ; Bit Set File: A STEP=on
                                ; ------  -------
                                ;   3        3   <-- symmetry

    ; G_portb.bits.b1 = dir;    ; a_rev?   a_fwd?
    ;                           ; ------   ------
    bcf    A_DIR_BIT            ;   1        1   ; Bit Clr File: assume A DIR=fwd
    btfsc  stp_arg_dir,7        ;   1        2   ; test bit 7 of hi vel (0x8000): Is dir bit on (REV)?
    bsf    A_DIR_BIT            ;   1        0   ; A DIR=rev
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

    bcf    B_STEP_BIT
    btfsc  stp_arg_step,0
    bsf    B_STEP_BIT

    bcf    B_DIR_BIT
    btfsc  stp_arg_dir,7
    bsf    B_DIR_BIT
    goto   st_c_chk
;
; C channel
;
st_c_chk:
    movlw  0x02
    cpfseq stp_arg_chan
    goto   st_d_chk

    bcf    C_STEP_BIT
    btfsc  stp_arg_step,0
    bsf    C_STEP_BIT

    bcf    C_DIR_BIT
    btfsc  stp_arg_dir,7
    bsf    C_DIR_BIT
    goto   st_d_chk
;
; D channel
;
st_d_chk:
    movlw  0x03
    cpfseq stp_arg_chan
    goto   st_done

    bcf    D_STEP_BIT
    btfsc  stp_arg_step,0
    bsf    D_STEP_BIT

    bcf    D_DIR_BIT
    btfsc  stp_arg_dir,7
    bsf    D_DIR_BIT
    goto   st_done

st_done:
    return
