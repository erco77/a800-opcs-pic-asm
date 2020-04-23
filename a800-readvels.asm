; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

; ReadVels()
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
    movlw       4               ; offset for FSR0/1 if G_new_vix == 1
    btfsc       G_new_vix,0
    addwf       FSR0L           ; FSR0 += 4 if G_new_vix set
    btfsc       G_new_vix,0
    addwf       FSR1L           ; FSR1 += 4 if G_new_vix set

    ; is_strobe = IS_STROBE;    // where IS_STROBE is ((G_porta & 0b0001) == 0b0001)
    ;
    clrf        rv_is_stb       ; assume unset
    btfsc       G_porta,0       ; G_porta bit 0 set? (PORTA bit 0 is IBMPC_STROBE)
    setf        rv_is_stb       ; yes, ff -> rv_is_stb

    ; is_svel_stb = IS_SVEL_AND_STROBE;         // e.g ((G_porta & 0b0101) == 0b0101)
    ;
    ;    NOTE: PIC doesn't have a simple literal compare, so to test if both
    ;          bits are set, we use xor to flip the bits and test for zero flag.
    ;
    clrf        rv_is_svel_stb  ; assume unset
    movf        G_porta,W       ; G_porta -> WREG
    andlw       b'00000101'     ; isolate bits 0+2: (STROBE_8255 and SVEL_8255)
    xorlw       b'00000101'     ; flip    bits 0+2: WREG=0 if both bits were set
    btfsc       STATUS,Z        ; test ZERO flag: skip if not zero
    setf        rv_is_svel_stb  ; zero? both bits set, so ff->rv_is_svel_stb

    ; // START strobe from PC?
    ; //     This can happen at any time. If so, re-start state machine.
    ; //
    ; if ( is_svel_and_strobe ) { // START + STROBE from PC?
    ;     IBMPC_ACK = 1;
    ;     //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ;     state     = 11;         // jump state machine into reading vels from PC
    ; } else {
    ;     //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ; }

    ; if ( is_svel_and_strobe ) { // START + STROBE from PC?
    ;                                ;    Cycles
    ;                                ; ------------
    ;                                ; SKIP  NOSKIP
    btfsc       rv_is_svel_stb,0     ;   3     1  ; (only need to check bit0)
    goto        rv_svel_stb_SET      ;   |     2  ; svel and stb are SET
    goto        rv_svel_stb_CLR      ;   2     |  ; svel and stb are NOT set
                                     ;   |     |
rv_svel_stb_SET:
    nop  ; compensate no-skip btfs*  ;   |     1
    nop  ; compensate no-skip btfs*  ;   |     1
    ; IBMPC_ACK = 1;
    bsf         IBMPC_ACK_BIT        ;   |     1
                                     ;   |     |
    ; state     = 11;                ;   |     |   // jump state machine into reading vels from PC
    movlw       .2    ; .11 now .2   ;   |     1
    movwf       rv_state             ;   |     1
    goto        rv_state_machine     ;   |     2
                                     ;   |   -----
                                     ;   |    10
    ;    } else {
    ;        //IBMPC_IRQ = 0;        // No! Leave IRQ management to state machine
    ;    }
    ;
rv_svel_stb_CLR:                     ;   |     |
    nop                              ;   1     |
    nop                              ;   1     |
    nop                              ;   1     |
    goto        rv_state_machine     ;   2     |
                                     ; ----- -----
                                     ;   10    10 <-- execution symmetry

rv_state_machine:
    ;
    ; This is the state machine for receiving data from the IBMPC.
    ;
    ; At any given moment the IBMPC is either in the middle of sending data,
    ; or is about to start, or has just finished. The 'rv_state' reflects
    ; where in the transmit/receive process we are.
    ;
    ; Regardless of the state, the execution time MUST BE THE SAME,
    ; or we'll get jitter in the running motors while data is being
    ; received from the PC. This means each state must take exactly
    ; as long as the LONGEST state's execution time (8 cycles).
    ; We use NOPs to pad.
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
    ;     ..the large switch/case block is implemented as a jump table instead:
    ;
    ;           movwf PCL               ; jump into a GOTO table:
    ;           goto  A         ; state=0
    ;           goto  B         ; state=1
    ;           goto  C         ; state=2
    ;           :
    ;           etc
    ;
    ;   Old  New
    ;  State State  Description
    ;  ----- -----  --------------------------------------------------------
    ;    0    0     Ack    \__ Receive data and toss it.
    ;    1    1     Unack  /   Handles data sent beyond 4 channels
    ;
    ;   11    2     Entry point for "SVEL+STROBE". Initial handshake
    ;               handled by if () above state machine since it can happen
    ;               at any time, then enters here to begin receiving data.
    ;
    ;   12    3     \__ lsb ack/unack     \
    ;   13    4     /                      \
    ;   14    5     \__ msb ack/unack       \___ RECEIVE A VELS
    ;   15    6     /                       /
    ;   16    7     \__ lsb+msb -> array   /
    ;   17    8     /                     /
    ;   18    9     \__ lsb ack/unack     \
    ;   19    10    /                      \
    ;   20    11    \__ msb ack/unack       \___ RECEIVE B VELS
    ;   21    12    /                       /
    ;   22    13    \__ lsb+msb -> array   /
    ;   23    14    /                     /
    ;   24    15    \__ lsb ack/unack     \
    ;   25    16    /                      \
    ;   26    17    \__ msb ack/unack       \___ RECEIVE C VELS
    ;   27    18    /                       /
    ;   28    19    \__ lsb+msb -> array   /
    ;   29    20    /                     /
    ;   30    21    \__ lsb ack/unack     \
    ;   31    22    /                      \
    ;   32    23    \__ msb ack/unack       \___ RECEIVE D VELS
    ;   33    24    /                       /
    ;   34    25    \__ lsb+msb -> array   /
    ;   35    26    /                     /
    ;   . . . . . . . . . . . . . . . . . . . . . . . . . . .
    ;   36    27    Final state: tell RunMotor() we have new data:
    ;               set 'G_got_vels', set state to back to '0'
    ;

    ;;;
    ;;; HANDLE JMP TABLE
    ;;;     jmp_index - index into table, where 0=GOTO aaa, 1=GOTO bbb, etc..
    ;;;     Note: the GOTO's in the table are /4 bytes each/ (4 bytes: EF ?? F? ??),
    ;;;     so we do some extra math (rlncf) on the fly to multiply the index by 4,
    ;;;     and save that result so we can use it for the ADDWF below..
    ;;;

    ; Multiply index by 4 and save result, to properly index the 4 byte GOTOs..
    movf    rv_state,W          ; state -> WREG
    rlncf   WREG,0,0            ; rotate left  \__ WREG *= 4
    rlncf   WREG,0,0            ; rotate left  /
    movwf   rv_state_x4,BANKED  ; save x4 result for actual PCL adjust below

    ; Now do the math for the jump table that handles page boundaries..
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
    goto rv_case_0      ;   0   Ack    \__ Receive data and toss it.
    goto rv_case_1      ;   1   Unack  /   Handles data sent beyond 4 channels
    goto rv_case_11     ;   2   Entry point for "SVEL+STROBE". Initial handshake
    ;                   ;       handled by if () above state machine since it can happen
    ;                   ;       at any time, then enters here to begin receiving data.

    goto rv_case_12     ;   3   A CHAN lsb ack
    goto rv_case_13     ;   4   A CHAN lsb unack
    goto rv_case_14     ;   5   A CHAN msb ack
    goto rv_case_15     ;   6   A CHAN msb unack
    goto rv_case_16     ;   7   A CHAN lsb/msb -> vels/dirs array

    goto rv_case_17     ;   8   B CHAN lsb ack
    goto rv_case_18     ;   9   B CHAN lsb unack
    goto rv_case_19     ;   10  B CHAN msb ack
    goto rv_case_20     ;   11  B CHAN msb unack
    goto rv_case_21     ;   12  B CHAN lsb/msb -> vels/dirs array

    goto rv_case_22     ;   13  C CHAN lsb ack
    goto rv_case_23     ;   14  C CHAN lsb unack
    goto rv_case_24     ;   15  C CHAN msb ack
    goto rv_case_25     ;   16  C CHAN msb unack
    goto rv_case_26     ;   17  C CHAN lsb/msb -> vels/dirs array

    goto rv_case_27     ;   18  D CHAN lsb ack
    goto rv_case_28     ;   19  D CHAN lsb unack
    goto rv_case_29     ;   20  D CHAN msb ack
    goto rv_case_30     ;   21  D CHAN msb unack
    goto rv_case_31     ;   22  D CHAN lsb/msb -> vels/dirs array

    goto rv_case_32     ;   23  Final state: 'got vels=1', 0 -> state

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
    ;      received, which jumps the state machine to case 11 to start
    ;      receiving actual data again.
    ;
rv_case_0:

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
    goto        rv0_is_stb              ;   2     |  ; is_strobe?
    goto        rv0_not_is_stb          ;   |     2  ; ! is_strobe?
                                        ;   |     |
rv0_not_is_stb:
    ; Strobe lo? Keep ack low and wait for it to go high, remain in state
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    nop                                 ;   |     1  ; DO NOT advance state
    return                              ;   |   -----
                                        ;   |     9
rv0_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    ; Strobe hi? Read data, ack, advance to 'case 1'
    movf        IBMPC_DATA,W            ;   1     |  ; read byte from IBMPC bus
    movwf       rv_lsb                  ;   1     |  ; save as LSB
    nop                                 ;   1     |
    incf        rv_state                ;   1     |  ; ADVANCE to next state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry
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

rv_case_1:
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
    nop  ; compensate no-skip btfs*     ;   |     1
    nop  ; compensate no-skip btfs*     ;   |     1
    ; Host lowered strobe?              ;   |     |
    ;    Un-ack, move back to case 0    ;   |     |
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    clrf        rv_state                ;   |     1  ; state = 0;
    return                              ; ----- -----
                                        ;   9     9
    ;
    ; CASE 11
    ;

    ;   START of receiving data.
    ;       If we're here, we JUST received a START and send an ACK
    ;       (handled by the if() preceding this switch() block).
    ;       So we should now wait for the host to ack before continuing on
    ;       to receive vels.
    ;
    ;   case 11: // ack Start
    ;       if ( ! is_svel_and_strobe ) { // check if host lowered STROBE and START
    ;           IBMPC_ACK = 0;            // un-ack
    ;           state    += 1;            // advance to next state
    ;       } else {
    ;           IBMPC_ACK = 1;            // keep ACK set until strobe/start clears
    ;       }
    ;

rv_case_11:
    ;                                   ;   Cycles
    ;                                   ; -----------
    ;                                   ; !SKIP  SKIP
    btfsc       rv_is_svel_stb,0        ;   1     3  ; svel+strobe? skip if clear..
    goto        rv11_is_stb             ;   2     |  ; is svel+stb?
    goto        rv11_not_is_stb         ;   |     2  ; not svel+stb?
                                        ;   |     |
rv11_not_is_stb:
    ; // check if host lowered STROBE and START
    nop                                 ;   |     1
    bcf         IBMPC_ACK_BIT           ;   |     1  ; IBM_PC_ACK = 0;
    nop                                 ;   |     1
    incf        rv_state                ;   |     1  ; advance state
    return                              ;   |   -----
                                        ;   |     9
rv11_is_stb:
    nop  ; compensate no-skip btfs*     ;   1     |
    nop  ; compensate no-skip btfs*     ;   1     |
    ; No strobe? keep sending ACK until strobe/start clears
    nop                                 ;   1     |
    bsf         IBMPC_ACK_BIT           ;   1     |  ; keep ACK set until strobe/start clears
    nop                                 ;   1     |
    nop                                 ;   1     |  ; DON'T advance state
    return                              ; ----- -----
                                        ;   9     9   <-- execution symmetry

; Handle receipt of channels ABCD
#include "a800-readvels-achan.asm"
#include "a800-readvels-bchan.asm"
#include "a800-readvels-cchan.asm"
#include "a800-readvels-dchan.asm"

; // Final state of the state machine: all data received, flag that
; // data was received (G_got_vels == 1) and move to state machine to
; // jump to 'case 0' to accept and toss any extra channels of data.
;
; case 32:
; default: // final state: tell RunMotor() we have new data
;     if ( always_true ) {          // NOP - always true
;         G_got_vels = 1;           // flag vels were loaded
;         state      = 0;           // jump state machine to 'case 0', ignoring all subsequent data until next SVEL
;     }

    ;
    ; CASE 32
    ;
rv_case_32:
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
    ;                             ;  9

