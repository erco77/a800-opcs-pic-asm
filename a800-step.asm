;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; FUNCTION:
;     Step(uchar chan, uchar dir, uchar val)
;
;     Step the motor one pulse. Inputs are on the stack.
;     Values are on the stack
;
;     Assumes banksel set for fstep_arg_xxx
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Step:
    ; TODO: Redo this as a jump table?
    ;       May or may not be worth it.. each case condition takes 4 cycles,
    ;       so 16 total for ABCD cases. Setup for a jump table might take longer.
    ;
;
; A channel
;
    ; case 0:
    ;      G_portb.bits.b0 = val;
    ;      G_portb.bits.b1 = dir;
    ;      return;
    ;
    ; case 0:			; --- Cycles ----
    ;                           ; IsChan  NotChan
    ;                           ; ------  -------
    movlw  0x00			;    1       1
    cpfseq fstep_arg_chan	;    3       1   ; Compare File Skip if EQual (CPFSEQ)
    goto   st_b_chk		;    |       2   ; !=0: check next chan
                                ; ------  -------
				;    4       4   <-- symmetry
    
    ; G_portb.bits.b0 = val;    ; a_set   a_clr
    ;                           ; -----   -------
    btfsc  fstep_arg_val,0	;   1        3   ; Bit Test Skip if Clear
    goto   st_a_set             ;   2        |
    goto   st_a_clr             ;   |        2
                                ; -----   -------
				;   3        5
                                ;   |        |
st_a_set:                       ;   |        |
    nop   ; btfsc compensate    ;   1        |
    nop   ; btfsc compensate    ;   1        |
    bsf    A_STEP_BIT		;   1        |   ; Bit Set File
    goto   st_a_dir             ;   2        |
                                ; ------     |
				;   8        |
st_a_clr:                       ;   |
    bcf    A_STEP_BIT		;   |        1   ; Bit Clear File
    goto   st_a_dir		;   |        2
                                ; ------  -------
				;   8        8   <-- symmetry
st_a_dir:
    ; G_portb.bits.b1 = dir ^ 1; // INVERT: Geckos are active LOW
    ;                           ; a_rev    a_fwd    
    ;                           ; -----    ------    
    btfsc  fstep_arg_dir,0	;   1        3   ; Bit Test Skip if Clear
    goto   st_a_rev             ;   2        |      
    goto   st_a_fwd             ;   |        2      
                                ; -----    ------    
				;   3        5
st_a_rev:                       ;   |        |
    nop   ; btfsc compensate    ;   1        |
    nop   ; btfsc compensate    ;   1        |
    bcf    A_DIR_BIT		;   1        |   ; CLEAR bit for reverse (active low)
    goto   st_b_chk	        ;   2        |
                                ; -----      |
				;   8        |
st_a_fwd:                       ;   |        |
    bsf    A_DIR_BIT		;   |        1   ; SET bit for forward (active low)
    goto   st_b_chk	        ;   |        2
                                ; -----    ------
				;   8        8
;
; B channel
;
st_b_chk:
    movlw  0x01
    cpfseq fstep_arg_chan
    goto   st_c_chk
    btfsc  fstep_arg_val,0
    goto   st_b_set
    goto   st_b_clr
st_b_set:
    nop
    nop
    bsf    B_STEP_BIT
    goto   st_b_dir
st_b_clr:
    bcf    B_STEP_BIT
    goto   st_b_dir
st_b_dir:
    btfsc  fstep_arg_dir,0
    goto   st_b_rev
    goto   st_b_fwd
st_b_rev:
    nop
    nop
    bcf    B_DIR_BIT
    goto   st_c_chk
st_b_fwd:
    bsf    B_DIR_BIT
    goto   st_c_chk
;
; C channel
;
st_c_chk:
    movlw  0x02
    cpfseq fstep_arg_chan
    goto   st_d_chk
    btfsc  fstep_arg_val,0
    goto   st_c_set
    goto   st_c_clr
st_c_set:
    nop
    nop
    bsf    C_STEP_BIT
    goto   st_c_dir
st_c_clr:
    bcf    C_STEP_BIT
    goto   st_c_dir
st_c_dir:
    btfsc  fstep_arg_dir,0
    goto   st_c_rev
    goto   st_c_fwd
st_c_rev:
    nop
    nop
    bcf    C_DIR_BIT
    goto   st_d_chk
st_c_fwd:
    bsf    C_DIR_BIT
    goto   st_d_chk
;
; D channel
;
st_d_chk:
    movlw  0x03
    cpfseq fstep_arg_chan
    goto   st_done
    btfsc  fstep_arg_val,0
    goto   st_d_set
    goto   st_d_clr
st_d_set:
    nop
    nop
    bsf    D_STEP_BIT
    goto   st_d_dir
st_d_clr:
    bcf    D_STEP_BIT
    goto   st_d_dir
st_d_dir:
    btfsc  fstep_arg_dir,0
    goto   st_d_rev
    goto   st_d_fwd
st_d_rev:
    nop
    nop
    bcf    D_DIR_BIT
    goto   st_done
st_d_fwd:
    bsf    D_DIR_BIT
    goto   st_done
st_done:
    return


