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

    ;; XXX:  THESE BRANCH INSTRUCTIONS AFFECT EXECUTION TIME
    ;;       Should they be broken out for symmetry timing?
    ;;
    ;;       And hmm, why not just have the G_run_vix values
    ;;       alternate between zero and 4 so the value can simply
    ;;       be added to FSR0 without the conditional? Everything
    ;;       is in the same bank anyway, so FSR1L will always be
    ;;       constant, and not wrap bank boundaries.
    ;;
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
    clrf rm_chan

rm_chan_loop:           ; for loop
    ; Just save the state of FSR2.. it's the only one we use POSTINC with
    ; because it's a pointer to a 16bit value. The others, FSR0 and FSR1,
    ; are byte pointers, so we can use non-increment INDF0/1 for operations.
    ;
    movff FSR2L,rm_fsr2+0         ; 2 cycles (measured)
    movff FSR2H,rm_fsr2+1         ; 2 cycles (measured)

    ; if ( G_freq == 0 ) { pos[c]  = MAXFREQ/2; }               // full iter of chan loop?
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
                                 ;   |      |
rm_G_freq_zr:                    ;   |      |
    ; { pos[chan] = G_maxfreq2; }    |      |
    movff  G_maxfreq2+0,POSTINC2 ;   |      2  ; 2 cycles (measured)
    clrf                POSTINC2 ;   |      1  ; 1 cycle  (measured) <- Faster than movff, assume FSR2 won't wrap bank
;;;;movff  G_maxfreq2+1,POSTINC2 ;   |     xxx ; 2 cycles (measured)
    goto rm_G_freq_restore       ;   |      2
    ;                            ;   |    -----
    ;                            ;   |      10
    ;                            ;   |      |
rm_G_freq_nz:                    ;   |      |
    ; { pos[chan] += vels[G_run_vix][chan]; }
    movf   INDF0,0               ;   1      |  ; vel[lsb] -> W  (NOTE: INDF0 doesn't increment)
    addwf  POSTINC2,1            ;   1      |  ; w + pos[chan] -> pos[chan]
    clrf   WREG                  ;   1      |
    addwfc POSTINC2,1            ;   1      |  ; carry -> pos[chan] (",1": result->pos, ",1": use BSR)
    nop                          ;   1      |
    goto rm_G_freq_restore       ;   2      |
    ;                            ; -----  -----
    ;                            ;   10     10   <-- symmetry

rm_G_freq_restore:
    ; restore FSR2
    movff  rm_fsr2+0,FSR2L       ; 2 cycles (measured)
    clrf   FSR2H                 ; 1 cycle  (measured) <- Faster than movff, assume FSR2 won't wrap bank
;;;;movff  rm_fsr2+1,FSR2H       ; xxxxxxxxxxxxxxxxxxx    ; 2 cycles (measured)

; if ( pos[chan] >= MAXFREQ ) { Step(chan, dir, 1); pos[chan] -= MAXFREQ; } // step
; else                        { Step(chan, dir, 0);                      }  // unstep
;

;;;   *** NEW CODE: REV B ***   ;;;
;;;               |             ;;;
;;;              \|/            ;;;
;;;               v             ;;;

    ; if (pos[chan] >= MAXFREQ)
    ; 16bit compare GTE
    ;                             ; *** REV B: NEW CODE/BUG FIX ***
    ;                             ;    Cycles   (NEEDS CHECK WITH STOPWATCH)
                                  ;  LT     GTE
                                  ;  -----  -----
    movf    (G_maxfreq+0),W       ;  1      1      ; G_maxfreq[0] -> W  (always 2c)
    subwf   POSTINC2,W            ;  1      1      ; W = pos[chan+0] - W(G_maxfreq[0])  -- sets "borrow" or not
    movf    (G_maxfreq+1),W       ;  1      1      ; G_maxfreq[1] -> W  (always 01)
    subwfb  POSTINC2,W            ;  1      1      ; W = pos[chan+1] - W(G_maxfreq[1])  -- includes prev "borrow"
; Restore FSR2/POSTINC2           ;  |      |
    movff  rm_fsr2+0,FSR2L        ;  2      2      ; 2 cycles (measured)
    clrf             FSR2H        ;  1      1      ; 1 cycle  (measured) <- Faster than movff bt 1 cycle, assume FSR2 won't wrap bank
;;;;movff  rm_fsr2+1,FSR2H        ;  xxxxxxxxxx    ; 2 cycles (measured)
; Branch on carry/borrow of above subwfb
    btfss   STATUS,0,C            ;  1      3      ; <-- btfss takes 3 cycles to skip over goto
    goto    rm_maxfreq_lt         ;  2      |
    goto    rm_maxfreq_gte        ;  |      2
                                  ;  -----  -----
                                  ;  10     12
rm_maxfreq_gte:                   ;  |      |
    ; Step(0,dir,1);              ;  |      |
    movff  rm_chan,stp_arg_chan   ;  |      2      ; rm_chan -> stp_arg_chan
    movff  INDF1,stp_arg_dir      ;  |      2      ; dir[G_run_vix][0] -> stp_arg_dir  (NOTE: INDF1 doesn't increment)
    movlw  1                      ;  |      1      ; STEP
    movwf  stp_arg_step           ;  |      1
    call   Step                   ;  |      2      ; <-- Step()'s execution time is longer than 2 cycles,
                                  ;  -----  -----
                                  ;  10     20
    ; pos[chan] -= MAXFREQ;       ;  |      |
    movlw  low MAXFREQ            ;  |      1      ; THIS IS *EXACTLY* WHAT THE C COMPILER GENERATES
    subwf  POSTINC2,1             ;  |      1      ; POSTINC2 (FSR2) is address of pos[] current channel
    movlw  high MAXFREQ           ;  |      1
    subwfb POSTINC2,1             ;  |      1
    goto   rm_maxfreq_done        ;  |      2
                                  ; -----   -----
                                  ;  10     26
rm_maxfreq_lt:                    ;  |      |
    ; Step(0,dir,0);              ;  |      |
    movff rm_chan,stp_arg_chan    ;  2      |      ; rm_chan -> stp_arg_chan
    movff INDF1,stp_arg_dir       ;  2      |      ; dir[G_run_vix][0] -> stp_arg_dir  (NOTE: INDF1 doesn't increment)
    movlw 0                       ;  1      |      ; UN-STEP
    movwf stp_arg_step            ;  1      |
    call Step                     ;  2      |      ; <-- Step()'s execution time is longer than 2 cycles,
    ;                             ;  |      |      ;     but should be consistent at least.
    ; The rest of this section    ;  |      |
    ; NOPs for timing symmetry.   ;  |      |
    ;                             ;  |      |
    nop                           ;  1      |
    nop                           ;  1      |
    nop                           ;  1      |
    nop                           ;  1      |
    nop                           ;  1      |
    nop                           ;  1      |
    goto rm_maxfreq_done          ;  2      |
                                  ; \|/     |
                                  ; ----- ------
                                  ;  26    26    <-- SYMMETRY!

;;;               ^             ;;;
;;;              /|\            ;;;
;;;               |             ;;;
;;;   *** NEW CODE: REV B ***   ;;;

rm_maxfreq_done:
    ; Restore FSR2 which we mess with above..
    movff  rm_fsr2+0,FSR2L         ; 2 cycles (measured)
    clrf             FSR2H         ; 1 cycle  (measured) <- Faster than movff, assume FSR2 won't wrap bank
;;;;movff  rm_fsr2+1,FSR2H         ; xxxxxxxxxxxxxxxxxxx   ; 2 cycles (measured)

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

#ifdef STANDALONE

;;
;; STANDALONE DEBUGGING
;;     Only build this in standalone mode, this doesn't ever need
;;     to appear in production firmware.
;;

     ; if ( pos     >= MAXFREQ ) Step(1) else Step(0)
     ; if ( testpos >= .300    ) Step(1) else Step(0)
test:
     ; pos = <testpos>
TESTPOS  equ  .299             ; decimal value for pos to compare
     movlw   low TESTPOS        ; TESTPOS[low] -> WREG
     movwf   (pos+0)            ; WREG -> p[0]
     movlw   high TESTPOS       ; TESTPOS[hi] -> WREG
     movwf   (pos+1)            ; WREG -> p[1]

     ; if (pos >= G_maxfreq) <gte> else <lt>
     movf    (G_maxfreq+0),W    ; G_maxfreq[0] -> W  (always 2c)
     subwf   (pos+0),W          ; W = pos[0] - W(G_maxfreq[0])  -- sets "borrow" or not
     movf    (G_maxfreq+1),W    ; G_maxfreq[1] -> W  (always 01)
     subwfb  (pos+1),W          ; W = pos[1] - W(G_maxfreq[1])  -- includes prev "borrow"
     btfss   STATUS,0,C         ; test carry; skip if gte
     goto    lt
     goto    gte
lt:  nop
     nop
gte: nop    ; SHOULD GO HERE!
     nop

#endif
