; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

; ReadVels()
;
;   State machine to handle reading velocities sent from IBM PC
;   and stores them in our vels[] and dirs[] array buffers for
;   sending to the motors on next IRQ.
;
;   This code does not block; it handles moving through the states of
;   reading vels from PC, handshaking with PC, saving data, etc.
;   one step at a time on each call to this function, a sort of
;   "unrolled loop" that has a fixed execution time.
;
;   This function also includes the combined code in the files:
;       a800-readvels-achan.asm     ; read vels for A channel
;       a800-readvels-bchan.asm     ; read vels for B channel
;       a800-readvels-cchan.asm     ; read vels for C channel
;       a800-readvels-dchan.asm     ; read vels for D channel
;
ReadVels:

    ; Prepare FSR0 = vels[G_new_vix][0]
    ;         FSR1 = dirs[G_new_vix][0]
    ;
    ; Load FSR0/FSR1 with ptr to head of vels/dirs array
    lfsr        FSR0,vels
    lfsr        FSR1,dirs

    ; Load WREG with offset to handle array[new_vels][chan] indexing.
    ; new_vels is either 0 or 1, so we translate this into a uchar offset
    ; of either 0 or 4 (MAXCHANS). Let's assume FSR0/FSR1 point
    ; *within bank* to avoid 16 bit indexing, so just adjust FSR0L/1L
    ;
    movf        G_new_vix,W     ; get current G_new_vix offset (0 or 4)
    addwf       FSR0L           ; add it to FSR0L vels[] index -- assume no carry; all indexing within bank
    addwf       FSR1L           ; add it to FSR1L dirs[] index -- assume no carry; all indexing within bank

    ; is_strobe = IS_STROBE;    // where IS_STROBE is ((G_porta & 0b0001) == 0b0001)
    ;
    movf        G_porta,W       ; G_porta -> WREG
    andlw       b'00000001'     ; G_porta bit 0 set? (PORTA bit 0 is IBMPC_STROBE)
    movwf       rv_is_stb       ; will be 1 if stb, 0 if not

    ; is_svel_stb = IS_SVEL_AND_STROBE;         // e.g ((G_porta & 0b0101) == 0b0101)
    ;
    ;    NOTE: To test if both SVEL and STB are are set, we use
    ;          xor to flip the bits and test for zero later with tstfsz.
    ;
    movf        G_porta,W       ; G_porta -> WREG
    andlw       b'00000101'     ; isolate bits 0+2: (STROBE_8255 and SVEL_8255)
    xorlw       b'00000101'     ; flip    bits 0+2: WREG=0 if both bits were set
    movwf       rv_is_svel_stb  ; will be 0 if both set

    ; // START strobe from PC?
    ; //     This can happen at any time. If so, re-start state machine.
    ; //
    ; if ( is_svel_and_strobe ) { // START + STROBE from PC?
    ;     IBMPC_ACK = 1;
    ;     //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ;     state     = 2;          // jump state machine into reading vels from PC
    ; } else {
    ;     //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ; }

    ; if ( is_svel_and_strobe ) { // START + STROBE from PC?
    ;
    ;                                ;    Cycles
    ;                                ; ------------
    ;                                ; SKIP  NOSKIP
    tstfsz      rv_is_svel_stb       ;   3     1  ; TeST F, Skip if Zero     ; value is 0 when both SVEL+STB are /set/
    goto        rv_svel_stb_CLR      ;   |     2  ; svel and stb are NOT set ; remember: value is the result of an xor,
    goto        rv_svel_stb_SET      ;   2     |  ; svel and stb are SET     ;           so it's the opposite of SVEL/STB bits. 
                                     ;   |     |
rv_svel_stb_SET:                     ;   |     |
    ; IBMPC_ACK = 1;                 ;   |     |
    bsf         IBMPC_ACK_BIT        ;   1     |
                                     ;   |     |
    ; state     = 2;                 ;   |     |   // jump state machine into reading vels from PC
    movlw       .2                   ;   1     |
    movwf       rv_state             ;   1     |
    goto        rv_state_machine     ;   2     |
                                     ; -----   |
                                     ;   10    |
    ;    } else {
    ;        //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ;    }
    ;
rv_svel_stb_CLR:                     ;   |     |
    nop                              ;   |     1
    nop                              ;   |     1
    nop                              ;   |     1
    nop                              ;   |     1
    nop                              ;   |     1
    goto        rv_state_machine     ;   |     2
                                     ; ----- -----
                                     ;   10   10  <-- Execution symmetry -- CHECKED: 04/18/2024

rv_state_machine:
    ;
    ; This is the state machine for receiving data from the IBMPC.
    ;
    ; At any given moment the IBMPC is either in the middle of sending data,
    ; or is about to start, or has just finished. 'rv_state' reflects where
    ; in the transmit/receive process we are.
    ;
    ; Regardless of the state, the execution time MUST BE THE SAME,
    ; or we'll get jitter in the motors while data is being received.
    ; So each state must take exactly as long as the LONGEST state's
    ; execution time. NOPs are used to pad out the faster states.
    ;
    ; IMPLEMENTATION:
    ;     Since the state machine has a lot of states to avoid loops,
    ;     in order to prevent a long list of condition tests like this:
    ;
    ;                if (state == 0) ..do A..
    ;           else if (state == 1) ..do B..
    ;           else if (state == 2) ..do C..
    ;           :
    ;           else if (state == n) ..do N..
    ;
    ;     ..the large switch/case block is actually implemented as a jump table:
    ;
    ;           movwf PCL       ; jump into a GOTO table:
    ;           goto  case_0    ; state=0
    ;           goto  case_1    ; state=1
    ;           goto  case_2    ; state=2
    ;           :
    ;           etc
    ;
    ;  State  Description
    ;  -----  --------------------------------------------------------
    ;   0     Ack    \__ Receive data and toss it.
    ;   1     Unack  /   Handles data sent beyond 4 channels
    ;
    ;   2  <- Entry point for "SVEL+STROBE". Initial handshake
    ;         handled by if () above state machine since it can happen
    ;         at any time, then enters here to begin receiving data.
    ;
    ;   3     \__ lsb ack/unack     --.
    ;   4     /                       |
    ;   5     \__ msb ack/unack       |___ RECEIVE A VELS/DIRS
    ;   6     /                       |
    ;   7     --- lsb+msb -> array  --`
    ;   8     \__ lsb ack/unack     --.
    ;   9     /                       |
    ;   10    \__ msb ack/unack       |___ RECEIVE B VELS/DIRS
    ;   11    /                       |
    ;   12    --- lsb+msb -> array  --`
    ;   13    \__ lsb ack/unack     --.
    ;   14    /                       |
    ;   15    \__ msb ack/unack       |___ RECEIVE C VELS/DIRS
    ;   16    /                       |
    ;   17    --- lsb+msb -> array  --`
    ;   18    \__ lsb ack/unack     --.
    ;   19    /                       |
    ;   20    \__ msb ack/unack       |___ RECEIVE D VELS/DIRS
    ;   21    /                       |
    ;   22    --- lsb+msb -> array  --`
    ;   . . . . . . . . . . . . . . . . . . . . . . . .
    ;   23    Final state: tell RunMotor() we have new data:
    ;         set 'G_got_vels', set state to back to '0' to
    ;         throw away any extra vels until SVEL received,
    ;         moving us back to case 2 (SVEL/STB).

    ;;;
    ;;; HANDLE JMP TABLE
    ;;;     rv_state - we multiply this by 4 to index into the jmp table.
    ;;;     (goto's are 4 bytes each, e.g. EF ?? F? ??), so we do the multiply
    ;;;     on the fly to calculate the byte offset into the goto's table.
    ;;;

    ; rv_state_x4 = rv_state * 4
    movf    rv_state,W          ; state -> WREG
    rlncf   WREG,0,0            ; rotate left  \__ WREG *= 4
    rlncf   WREG,0,0            ; rotate left  /
    movwf   rv_state_x4,BANKED  ; save x4 result for actual PCL adjust below

    ; Now apply the x4 value to the rv_jmp_table address (handles page boundaries)
    movlw   high (rv_jmp_table)
    movwf   PCLATH
    movlw   low  (rv_jmp_table)
    addwf   rv_state_x4,W,BANKED ; WREG + (index*4) -> WREG, carry on overflow
    btfsc   STATUS,C
    incf    PCLATH,F
    movwf   PCL         ; <-- THIS causes jmp into jmp_table

rv_jmp_table:
    ;    CASE_NAME      ; STATE#
    ;    ----------     ; ------
    goto rv_state_00    ;   00  Ack    \__ Receive data and toss it.
    goto rv_state_01    ;   01  Unack  /   Handles data sent beyond 4 channels

                        
    goto rv_state_02    ;   02  Entry point for "SVEL+STROBE". Initial handshake
    ;                   ;       handled by if () above state machine since it can happen
    ;                   ;       at any time, then enters here to begin receiving data.

    goto rv_state_03    ;   03  A CHAN lsb ack
    goto rv_state_04    ;   04  A CHAN lsb unack
    goto rv_state_05    ;   05  A CHAN msb ack
    goto rv_state_06    ;   06  A CHAN msb unack
    goto rv_state_07    ;   07  A CHAN lsb/msb -> vels/dirs array

    goto rv_state_08    ;   08  B CHAN lsb ack
    goto rv_state_09    ;   09  B CHAN lsb unack
    goto rv_state_10    ;   10  B CHAN msb ack
    goto rv_state_11    ;   11  B CHAN msb unack
    goto rv_state_12    ;   12  B CHAN lsb/msb -> vels/dirs array
                       
    goto rv_state_13    ;   13  C CHAN lsb ack
    goto rv_state_14    ;   14  C CHAN lsb unack
    goto rv_state_15    ;   15  C CHAN msb ack
    goto rv_state_16    ;   16  C CHAN msb unack
    goto rv_state_17    ;   17  C CHAN lsb/msb -> vels/dirs array
                       
    goto rv_state_18    ;   18  D CHAN lsb ack
    goto rv_state_19    ;   19  D CHAN lsb unack
    goto rv_state_20    ;   20  D CHAN msb ack
    goto rv_state_21    ;   21  D CHAN msb unack
    goto rv_state_22    ;   22  D CHAN lsb/msb -> vels/dirs array
                       
    goto rv_state_23    ;   23  Final state: 'got vels=1', 0 -> state

    ; switch (rv_state) {
    ;
    ;  CASE 0
    ;
    ;  NOTE: CASE 0 AND 1 ARE SPECIAL:
    ;
    ;      These 2 states receive data but just throw it away.
    ;      This allows host to send more channels than we support
    ;      without breaking anything.
    ;
    ;      These states alternate handling strobe/ack until a START is
    ;      received, which jumps the state machine to case 02 to start
    ;      receiving actual data again.
    ;
rv_state_00:

    ; if ( ! is_strobe ) {  // THROW AWAY EXTRA DATA: STROBE?
    ;     // Strobe lo? Keep ack low and wait for it to go high
    ;     // - do nothing -
    ; } else {
    ;     // Strobe hi? Read data, ACK, advance state to 'case 1'
    ;     lsb       = IBMPC_DATA;   // read lsb (ignore value read)
    ;     IBMPC_ACK = 1;            // ack
    ;     state    += 1;            // advance to next state
    ; }
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_stb,0             ;   1     3  ; strobe? skip if clear..
    goto        rv00_is_stb             ;   2     |  ; is_strobe?
    goto        rv00_not_is_stb         ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv00_not_is_stb:
    ; Strobe lo? Keep ack low and wait for it to go high, remain in state
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DO NOT advance state
    return                              ;   |   -----
                                        ;   |     9
rv00_is_stb:
    nop                                 ;   1     |
    nop                                 ;   1     |
    ; Strobe hi? Read data, ack, advance to 'case 1'
    movf        IBMPC_DATA,W            ;   1     |  ; read byte from IBMPC bus
    movwf       rv_lsb                  ;   1     |  ; save as LSB
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; ADVANCE to next state
    return                              ; ----- -----
                                        ;   9     9   <-- Execution symmetry -- CHECKED: 04/18/2024
    ;
    ;  CASE 1
    ;

    ; case 1: // THROW AWAY EXTRA DATA: await ack
    ;     if ( is_strobe ) {
    ;         // Strobe still hi? Keep ACK hi and wait for it to go low, remain in state
    ;         IBMPC_ACK = 1;            // keep ACK set until strobe clears
    ;     } else {
    ;         // Host lowered strobe? Un-ack, move back to case 0
    ;         IBMPC_ACK = 0;            // un-ack
    ;         state     = 0;            // go back to 'case 0'/keep tossing new data received
    ;     }
    ;     break;

rv_state_01:
    ; if ( is_strobe )
    ;                                   ;   Cycles
    ;                                   ; SKIP  NOSKIP
    ;                                   ; ----- -----
    btfss       rv_is_stb,0             ;   3     1  ; (only need to check bit0)
    goto        rv1_not_is_stb          ;   |     2  ; ! is_strobe?
    goto        rv1_is_stb              ;   2     |  ; is_strobe?
    ;                                   ;   |     |
rv1_is_stb:
    ; Strobe still hi? Keep ACK hi and wait for STB to go low
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; IBM_PC_ACK = 1;
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DON'T advance state
    return                              ; -----   |
    ;                                   ;   9     |

rv1_not_is_stb:
    nop                                 ;   |     1
    nop                                 ;   |     1
    ; Host lowered strobe?              ;   |     |
    ;    Un-ack, move back to case 0    ;   |     |
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    clrf        rv_state                ;   |     1  ; state = 0;
    return                              ; ----- -----
                                        ;   9     9   <-- Execution symmetry -- CHECKED: 04/18/2024
    ;
    ; CASE 2
    ;

    ;   START of receiving data.
    ;       If we're here, we JUST received a START and send an ACK
    ;       (handled by the if() preceding this switch() block).
    ;       So we should now wait for the host to ack before continuing on
    ;       to receive vels.
    ;
    ;   case 1: // ack Start
    ;       if ( ! is_svel_and_strobe ) { // check if host lowered STROBE and START
    ;           IBMPC_ACK = 0;            // un-ack
    ;           state    += 1;            // advance to next state
    ;       } else {
    ;           IBMPC_ACK = 1;            // keep ACK set until strobe/start clears
    ;       }
    ;

rv_state_02:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    tstfsz      rv_is_svel_stb          ;   3     1  ; TeST F, Skip if Zero  ; value is 0 when both SVEL+STB are /set/
    goto        rv02_not_is_stb         ;   |     2  ; not svel+stb?         ; remember: value is the result of an xor,
    goto        rv02_is_stb             ;   2     |  ; is svel+stb?          ;           so it's the opposite of SVEL/STB bits.
                                        ;   |     |
rv02_not_is_stb:                        ;   |     |
    ; // Host lowered STB+SVEL?         ;   |     |
    nop                                 ;   |     1
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv02_is_stb:                            ;   |     |
    ; until strobe/start clears         ;   |     |
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until strobe/start clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DON'T advance state
    return                              ; ----- -----
                                        ;   9     9   <-- Execution symmetry -- CHECKED: 04/18/2024

; Handle receipt of channels ABCD
#include "a800-readvels-achan.asm"
#include "a800-readvels-bchan.asm"
#include "a800-readvels-cchan.asm"
#include "a800-readvels-dchan.asm"

; // Final state of the state machine: all data received, flag that
; // data was received (G_got_vels == 1) and move to state machine to
; // jump to 'case 0' to accept and toss any extra channels of data.
;
; case 23:
; default: // final state: tell RunMotor() we have new data
;     if ( always_true ) {          // NOP - always true
;         G_got_vels = 1;           // flag vels were loaded
;         state      = 0;           // jump state machine to 'case 0', ignoring all subsequent data until next SVEL
;     }

    ;
    ; CASE 23
    ;
rv_state_23:
    ;                             ; Cycles
    ;                             ; ------
    nop                           ;  1
    nop                           ;  1
    nop                           ;  1
    nop                           ;  1
    nop                           ;  1
    setf        G_got_vels        ;  1  ; flag that ABCD vels/dirs were loaded
    movlw       0                 ;  1  ; set state to zero to ignore any other
    movwf       rv_state          ;  1  ; chans received until SVEL|STB.
    nop                           ;  1  ; disable auto-advance of state
    return                        ; ----
    ;                             ;  9   <-- Execution symmetry -- CHECKED: 04/18/2024
