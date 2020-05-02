; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;
; Run Motors by changing the step/dir bits
;
RunMotors:
    ; // Initialize pointer variables
    ; uchar *vp = &vels[G_run_vix][0];
    ; uchar *dp = &dirs[G_run_vix][0];
    ; uchar *p  = &pos[0];
    banksel vels
    lfsr        FSR0,vels
    lfsr        FSR1,dirs
    lfsr        FSR2,pos
    movlw       4               ; offset for FSR0/1 if G_run_vix == 1
    btfsc       G_run_vix,0
    addwf       FSR0L           ; FSR0 += 4 if G_run_vix set
    btfsc       G_run_vix,0
    addwf       FSR1L           ; FSR1 += 4 if G_run_vix set
    ; FSR2 is not indexed by G_run_vix, so no need to adjust it

    ; At this point:
    ;     FSR0 points to vels[G_run_vix] 8bit
    ;     FSR1 points to dirs[G_run_vix] 8bit
    ;     FSR2 points to pos[c]         16bit
    ;


    ;
    ; Now loop through channels ABCD (0 - 3) doing the following:
    ;
    ; for ( chan=0; chan<MAXCHANS; chan++ ) {
    ;

    ; chan=0;
    clrf rm_chan+0
    clrf rm_chan+1

rm_chan_loop:           ; for loop
    ; Just save the state of FSR2.. it's the only one we use POSTINC with
    ; because it's a pointer to a 16bit value. The others, FSR0 and FSR1,
    ; are byte pointers, so we can use non-increment INDF0/1 for operations.
    ;
    movff FSR2L,rm_fsr2+0
    movff FSR2H,rm_fsr2+1

    ; if ( G_freq == 0 ) { pos[c]  = MAXFREQ/2; }		// full iter of chan loop?
    ; else               { pos[c] += vels[G_run_vix][c]; }
    ;

    ; See if 16bit G_freq is zero.
    ;    Check if both bytes are 0 by OR'ing them together.
    ;
    movlw  0                     ; 0 -> W
    iorwf  G_freq+0,0,1          ; logical OR bits from G_freq
    iorwf  G_freq+1,0,1          ; ..and G_freq+1

    ;                            ; NOSKIP SKIP?
    ;                            ; -----  -----
    tstfsz WREG                  ;   1      3  ; Test + Skip If Zero. if W==0: both bytes of G_freq are 0
    goto   rm_G_freq_nz          ;   2      |  ; W != 0? G_freq is non-zero
    goto   rm_G_freq_zr          ;   |      2  ; W == 0? G_freq is zero

rm_G_freq_zr:
    ; { pos[chan] = G_maxfreq2; }
    ;                                          ; _
    movff  G_maxfreq2+0,POSTINC2 ;   |      3  ;  |_ pos[chan] = (MAXFREQ/2);
    movff  G_maxfreq2+1,POSTINC2 ;   |      3  ; _|
    goto rm_G_freq_restore       ;   |      2
    ;                            ;   |    -----
    ;                            ;   |      13

rm_G_freq_nz:
    nop                          ;   1      |
    nop                          ;   1      |
    ; { pos[chan] += vels[G_run_vix][chan]; }
    movf   INDF0,0               ;   1      |  ; vel[lsb] -> W  (NOTE: INDF0 doesn't increment)
    addwf  POSTINC2,1            ;   1      |  ; w + pos[chan] -> pos[chan]
    clrf   WREG                  ;   1      |
    addwfc POSTINC2,1            ;   1      |  ; carry -> pos[chan] (",1": result->pos, ",1": use BSR)
    nop                          ;   1      |
    nop                          ;   1      |
    goto rm_G_freq_restore       ;   2      |
    ;                            ; -----  -----
    ;                            ;   13     13   <-- symmetry

rm_G_freq_restore:
    ; restore FSR2
    movff  rm_fsr2+0,FSR2L
    movff  rm_fsr2+1,FSR2H

; if ( pos[chan] >= MAXFREQ ) { Step(chan, dir, 1); pos[chan] -= MAXFREQ; } // step
; else                        { Step(chan, dir, 0);                      }  // unstep
;
    ; if (pos[chan] >= MAXFREQ)
    ; 16bit compare GTE
    ;                         ;   Cycles
                              ;  NOCAR CAR
                              ;  ----- -----
    movf   G_maxfreq+0,w      ;   1     1
    subwf  POSTINC2,w         ;   1     1
    btfss  STATUS,C           ;   1     3  <-- btfss takes 3 cycles for skip over goto
    goto   rm_maxfreq_nocar   ;   2     |
    goto   rm_maxfreq_car     ;   |     2
                              ; ----- -----
                              ;   5     7
                              ;   |     |
                              ;   |     |
rm_maxfreq_car:               ;   |    \|/
    movf   G_maxfreq+1,w      ;   |     1
    subwf  POSTINC2,w         ;   |     1
    goto   rm_maxfreq_cardone ;   |     1
                              ;   |   ------
                              ;   |     10
                              ;   |     |
rm_maxfreq_nocar:             ;  \|/    |
    nop  ; comp for abv btfss ;   1     |
    nop  ; comp for abv btfss ;   1     |
    nop                       ;   1     |
    nop                       ;   1     |
    goto   rm_maxfreq_cardone ;   1    \|/
                              ; ----- ------
                              ;   10    10

rm_maxfreq_cardone:
    ; (restore FSR2, carry unaffected)
    movff  rm_fsr2+0,FSR2L
    movff  rm_fsr2+1,FSR2H

    ;                             ; -- Cycles --
    ; carry set if 1st >= 2nd     ;  CAR  NOCAR
    ;                             ; (GTE) (LT)
    ;                             ; ----- -----
    btfsc  STATUS,C               ;  1      3
    goto   rm_maxfreq_gte         ;  2      |
    goto   rm_maxfreq_lt          ;  |      2
                                  ;  |      |
rm_maxfreq_gte:                   ;  |      |
    ; Step(0,dir,1);              ;  |      |
    movff  rm_chan,stp_arg_chan   ;  2      |   ; rm_chan -> stp_arg_chan
    movff  INDF1,stp_arg_dir      ;  2      |   ; dir[G_run_vix][0] -> stp_arg_dir  (NOTE: INDF1 doesn't increment)
    movlw  1                      ;  1      |   ; STEP
    movwf  stp_arg_step           ;  1      |
    call   Step                   ;  2      |   ; <-- Step()'s execution time is longer than 2 cycles,
    ; pos[chan] -= MAXFREQ;       ;  |      |   ;     but should be consistent at least.
    movlw  low MAXFREQ            ;  1      |
    subwf  POSTINC2,1             ;  1      |   ; (low pos[chan] - low MAXFREQ) -> low pos[chan]
    movlw  high MAXFREQ           ;  1      |
    btfss  STATUS,C               ;  2  1   |   ; carry
    addlw  1                      ;  0  1   |
    subwf  POSTINC2,1             ;  1      |   ; (high pos[chan] - high MAXFREQ) -> high pos[chan]
    goto   rm_maxfreq_done        ;  2      |
                                  ; -----   |
                                  ;  19     |
rm_maxfreq_lt:                    ;  |      |
    ; Step(0,dir,0);              ;  |      |
    movff rm_chan,stp_arg_chan    ;  |      2   ; rm_chan -> stp_arg_chan
    movff INDF1,stp_arg_dir       ;  |      2   ; dir[G_run_vix][0] -> stp_arg_dir  (NOTE: INDF1 doesn't increment)
    movlw 0                       ;  |      1   ; UN-STEP
    movwf stp_arg_step            ;  |      1
    call Step                     ;  |      2   ; <-- Step()'s execution time is longer than 2 cycles,
    ;                             ;  |      |   ;     but should be consistent at least.
    ; The rest of this section    ;  |      |
    ; NOPs for timing symmetry.   ;  |      |
    ;                             ;  |      |
    nop                           ;  |      1
    nop                           ;  |      1
    nop                           ;  |      1
    nop                           ;  |      1
    goto rm_maxfreq_done          ; \|/     2
                                  ; ----- ------
                                  ;  19    19

rm_maxfreq_done:
    ; Restore FSR2 which we mess with above..
    movff  rm_fsr2+0,FSR2L
    movff  rm_fsr2+1,FSR2H

    ; Advance FSR0 vel[]  ptr (8 bit/1 byte)
    ; Advance FSR1 dirs[] ptr (8 bit/1 byte)
    ; Advance FSR2 pos[]  ptr (16bit/2 bytes)

    ; +1 byte for FSR0 vel[] uchar (8 bit) ptr
    incf FSR0L                  ; assume FSR won't wrap bank

    ; +1 byte for FSR1 dirs[] uchar (8 bit) ptr
    incf FSR1L                  ; assume FSR won't wrap bank

    ; +2 bytes for FSR2 pos[] ushort (16bit) ptr
    incf FSR2L                  ; assume FSR won't wrap bank
    incf FSR2L

    ; chan++;
    incf   rm_chan              ; chan++

    ; if ( chan != MAXCHANS ) continue chan loop
    movf   rm_chan,0,1          ; rm_chan -> WREG
    cpfseq G_maxchans           ; see if rm_chan == MAXCHANS, skip if so
    goto   rm_chan_loop         ; != MAXCHANS? continue loop
                                ; == MAXCHANS? done with loop

    ; [1] if ( ++G_freq > MAXFREQ ) {   // More ass'y efficient than: if ( G_freq++ >= MAXFREQ ) {
    ; [2]   if ( G_got_vels ) {         // new vels successfully received from IBMPC?
    ;         // Swap new/run arrays
    ;         G_freq     = 0;
    ;         G_run_vix ^= 1;           // start using IBMPC data for running motors
    ;         G_new_vix ^= 1;           // old run vels become new buffer for IBMPC
    ;         G_got_vels = 0;           // reset G_got_vels flag
    ;         IBMPC_IRQ  = 1;           // trigger IBMPC IRQ just this iter
    ; [3]   } else {
    ;         // Don't swap -- continue using same vels for running motors
    ;         G_freq    = 0;
    ;         IBMPC_IRQ = 1;            // trigger IBMPC IRQ just this iter
    ;       }
    ; [4] } else {
    ;       IBMPC_IRQ = 0;              // keep IRQ off rest of time
    ;     }

    ; [1] if ( ++G_freq > MAXFREQ ) ..
    infsnz  G_freq+0            ; inc low byte, skip if non-zero (didn't wrap)
    incf    G_freq+1            ; wrapped? inc high byte
    ; 16bit gt compare
    movf    (G_freq+0),w
    subwf   (G_maxfreq+0),w
    movf    (G_freq+1),w
    subwfb  (G_maxfreq+1),w   ;  SKIP NOSKIP
    btfsc   STATUS,0,C        ;   3     1
    goto    rm_G_freq_lte     ;   |     2
    goto    rm_G_freq_gt      ;   2     |
                              ;  ---- -----
                              ;   5     3
rm_G_freq_gt:                 ;   |     |_________
    ; [2] if ( G_got_vels ) {     |_______        |
    ;    // new vels from IBMPC?  |       |       |
    ;                         ; GVSKIP GVNOSKIP   |
    ;                         ; ------ --------   |
    btfsc G_got_vels,0        ;   3       1       |  ; bit test skip if clr
    goto  rm_got_vels_if      ;   |       2       |
    goto  rm_got_vels_else    ;   2       |       |
                              ; -----  -------- ------
                              ;   10      8       3
rm_got_vels_if:               ;   |       |       |
    nop                       ;   1       |       |
    nop                       ;   1       |       |

    ; // Swap new/run arrays
    ; G_freq    = 0;
    ; G_run_vix ^= 1; // start using IBMPC data for running motors
    ; G_new_vix ^= 1; // old run vels become new buffer for IBMPC
    ; G_got_vels = 0; // reset G_got_vels flag
    ; IBMPC_IRQ  = 1; // trigger IBMPC IRQ just this iter

    ; G_freq = 0;
    clrf    G_freq+0            ;   1     |  \__ 16bit
    clrf    G_freq+1            ;   1     |  /   ushort
    ; G_run_vix ^= 1;           ;   |     |       |
    ; G_new_vix ^= 1;           ;   |     |       |
    movlw   0x01                ;   1     |       |
    xorwf   G_run_vix,F         ;   1     |       |
    xorwf   G_new_vix,F         ;   1     |       |
                                ;   |     |       |
    ; G_got_vels = 0;           ;   |     |       |
    clrf    G_got_vels          ;   1     |       |
                                ;   |     |       |
    ; IBMPC_IRQ = 1;            ;   |     |       |
    bsf     IBMPC_IRQ_BIT       ;   1     |       |
                                ; ----- -----   -----
                                ;   19    8       3
    return

rm_got_vels_else:
    ; [3] } else {
    ;        // Don't swap -- continue using same vels for running motors
    ;        G_freq    = 0;
    ;        IBMPC_IRQ = 1;         // trigger IBMPC IRQ just this iter
    ;    }

    ; G_freq = 0;
    clrf    G_freq+0            ;   |      1  \_ ushort
    clrf    G_freq+1            ;   |      1  /
                                ;   |      |      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
    nop                         ;   |      1      |
                                ;   |      |      |
    ; IBMPC_IRQ = 1;            ;   |      |      |
    bsf     IBMPC_IRQ_BIT       ;   |      1      |
                                ; -----  -----  -----
                                ;   19     19     3
    return

rm_G_freq_lte:
    ; [4] } else {
    ;       IBMPC_IRQ = 0; // keep IRQ off rest of time
    ;     }

    ; So basically just clear IBMPC_IRQ
    ; and then do a lot of nothing for
    ; timing symmetry..
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1
    nop                         ;   |      |      1

    ; IBMPC_IRQ = 0;            ;   |      |      |
    bcf IBMPC_IRQ_BIT           ;   |      |      1
                                ; -----  -----  -----
                                ;   19     19    19    <-- symmetry!
    return
