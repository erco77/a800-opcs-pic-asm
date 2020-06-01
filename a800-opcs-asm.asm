; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

    list p=18F24Q10
#include "a800-config.h"

#define BUILD_CPU 2     ; *** SET MANUALLY: 1 for CPU1, 2 for CPU2 ***

; MAXFREQ   IRQ RATE
; -------   --------
; .512      62 Hz
; .300      106.7 Hz
; .256      122 Hz
;
MAXFREQ     equ .300    ; max frequency count for main iters (300)
MAXCHANS    equ .4      ; total channels (cpu1=ABCD, cpu2=EFGH)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;                         CPU1                                 #                    CPU2
;;  PIN#                  _    _                          PIN#  #   PIN#            _    _                        PIN#
;;   1    RES (VPP) MCLR | |__| | RB7 ->(ICSPDAT) D-Dir    28   #    1   " "  MCLR | |__| | RB7 (ICSPDAT) H-Dir    28
;;   2   STB_8255-> RA0  |      | RB6 ->(ICSPCLK) D-Step   27   #    2   " "  RA0  |      | RB6 (ICSPCLK) H-Step   27
;;   3   <-ACK_8255 RA1  |      | RB5 ->C-Dir              26   #    3   " "  RA1  |      | RB5 G-Dir              26
;;   4  SVEL_8255-> RA2  |      | RB4 ->C-Step             25   #    4   " "  RA2  |      | RB4 G-Step             25
;;   5 CPUID_8255-> RA3  |      | RB3 ->B-Dir              24   #    5   " "  RA3  |      | RB3 F-Dir              24
;;   6  <-IRQ_IBMPC RA4  |      | RB2 ->B-Step             23   #    6   " "  RA4  |      | RB2 F-Step             23
;;   7  <-CPU1 SYNC RA5  |      | RB1 ->A-Dir              22   #    7   " "  RA5  |      | RB1 E-Dir              22
;;   8        (VSS) GND  |      | RB0 ->A-Step             21   #    8   " "  GND  |      | RB0 E-Step             21
;;   9  16MHz Clk-> RA7  |      | +5  (VDD)                20   #    9   " "  RA7  |      | +5     "    "          20
;;   10  CPU1 Ack-> RA6  |      | GND (VSS)                19   #    10  " "  RA6  |      | GND    "    "          19
;;   11     Data0-> RC0  |      | RC7 <-Data7              18   #    11  " "  RC0  |      | RC7    "    "          18
;;   12     Data1-> RC1  |      | RC6 <-Data6              17   #    12  " "  RC1  |      | RC6    "    "          17
;;   13     Data2-> RC2  |      | RC5 <-Data5              16   #    13  " "  RC2  |      | RC5    "    "          16
;;   14     Data3-> RC3  |______| RC4 <-Data4              15   #    14  " "  RC3  |______| RC4    "    "          15
;;                                                              #
;;                      PIC18F24Q10                             #                PIC18F24Q10
;;
;; SIGNAL MAPPING BETWEEN PC <-> 8255 <-> PIC
;;
;;     IBMPC      --8255--    --PIC---
;;     PORT:MASK  PORT:BIT    PORT:BIT(CPU) SIGNAL NAME
;;     ---------  ---------   ------------- -------------
;;      0300:ff   PORTA:0-7   RC0-7(CPU1+2) DATA
;;      0301:01   PORTB:0     RA1  (CPU1)   ACK CPU1
;;      0301:02   PORTB:1     RA1  (CPU2)   ACK CPU2
;;      0301:fc   PORTB:2-7   unused
;;      0302:01   PORTC:0     RA0  (CPU2)   STROBE CPU2
;;      0302:02   PORTC:1     unused        -
;;      0302:04   PORTC:2     RA2  (CPU2)   SVEL CPU2
;;      0302:08   PORTC:3     unused        -
;;      0302:10   PORTC:4     RA0  (CPU1)   STROBE CPU1
;;      0302:20   PORTC:5     unused        -
;;      0302:40   PORTC:6     RA2  (CPU1)   SVEL CPU1
;;      0302:80   PORTC:7     unused        -
;;
;; 8255
;;     --8255--
;;     PORT:BIT   I/O  DESCRIPTION
;;     ========== ==== ===============================
;;     PORT A     OUT  8 bit data bus, 8255 -> CPU1+2
;;     -----------------------------------------------
;;     PORT B:0   IN   CPU0 ACK
;;     PORT B:1   IN   CPU1 ACK
;;     PORT B:2-7 IN   unused
;;     -----------------------------------------------
;;     PORT C:0   OUT  CPU2 STROBE
;;     PORT C:1   OUT  unused
;;     PORT C:2   OUT  CPU2 START VEL
;;     PORT C:3   OUT  unused
;;     PORT C:0   OUT  CPU1 STROBE
;;     PORT C:1   OUT  unused
;;     PORT C:2   OUT  CPU1 START VEL
;;     PORT C:3   OUT  unused
;;
;; PROGRAMMER (PICKIT 4)
;;     PICKIT PIC  PIC
;;     PIN#   PIN# SIGNAL
;;     ------ ---- ------
;;     1      1    MCLR
;;     2      20   +5 (VDD)
;;     3      19   GND
;;     4      28   ICSP_DAT
;;     5      27   ICSP_CLK
;;     Do not connect other pins past 5
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; PIC input "data bus" from IBMPC's 8255
; This port is used to read 8 bit values from the PC (motor vels)
;
#define IBMPC_DATA          G_portc

; PIC output to generate IRQ interrupt on IBMPC
; Port bit tied directly to IBMPC's IRQ: when set, triggers e.g. IRQ5 on IBMPC.
; Used to tell PC when it should begin sending us new velocities.
;
#define IBMPC_IRQ_BIT       LATA,4      ; ",4" as in "bit #4" in bsf/bcf commands

; Use LATA when writing to avoid read-modify-write problems
; during bit twiddling. See: https://www.microchip.com/forums/m332771.aspx
;
#define IBMPC_ACK_BIT       LATA,1,C    ; PORTA bit 1

; Test IBMPC Strobe and SVEL (StartVel) bits
#define IBMPC_STB_BIT       0           ; e.g. btfsc G_porta,IBMPC_STB_BITNUM
#define IBMPC_STB_SVEL_MASK b'00000101' ; e.g. andlw IBMPC_STB_SVEL_BITS

; CPU1 Sync macro constants
#define SET_SYNC            LATA,5      ; LATA bit 5
#define IS_ACK              PORTA,6     ; PORTA bit 6

; CPU2 Sync macro constants
#define SET_ACK             LATA,5      ; LATA bit 5
#define IS_SYNC             PORTA,6     ; PORTA bit 6

; PIC outputs: stepper motor bits macro constants
#define A_STEP_BIT          G_portb,0   ; A step is bit 0 of G_portb buffer
#define A_DIR_BIT           G_portb,1   ; A dir  is bit 1 of G_portb buffer
#define B_STEP_BIT          G_portb,2   ; B step is bit 2 of G_portb buffer
#define B_DIR_BIT           G_portb,3   ; B dir  is bit 3 of G_portb buffer
#define C_STEP_BIT          G_portb,4   ; C step is bit 4 of G_portb buffer
#define C_DIR_BIT           G_portb,5   ; C dir  is bit 5 of G_portb buffer
#define D_STEP_BIT          G_portb,6   ; D step is bit 6 of G_portb buffer
#define D_DIR_BIT           G_portb,7   ; D dir  is bit 7 of G_portb buffer

; Motor channel indexing the arrays
#define A_CHAN              0
#define B_CHAN              1
#define C_CHAN              2
#define D_CHAN              3

;
; VARIABLES SECTION - Uninitialized data
;                     We initialize these either in main(), or when needed.
;                     Variables global to the application start with G_xxx.
;                     Variables specific to a function begin with <funcname>_xxx,
;                     where <funcname> is abbreviated; stp==Step, rm=RunMotors, etc.
;
my_vars         udata 0x80      ; unitialized data (we init in main)
G_maxfreq       res 2           ; MAXFREQ as a memory constant (for SUBWF)
G_maxfreq2      res 2           ; MAXFREQ divided by 2 (used to init pos[] each iter)
G_maxchans      res 1           ; MAXCHANS as a memory constant (for CPFwhatever)
G_freq          res 2           ; running 16bit main loop frequency counter

; Buffers for ports
;     These are all sampled at the proper time to avoid race conditions with the
;     realtime hardware. For outputs, buffering ensures several bits can be setup,
;     then all written at once, so e.g. step pulses for all channels have the same
;     pulse width.
;
G_porta         res 1           ; buffer for PORTA
G_portb         res 1           ; buffer for PORTB
G_portc         res 1           ; buffer for PORTC

; Variables passed to Step() function (would be "function arguments")
stp_arg_chan    res 1
stp_arg_dir     res 1
stp_arg_step    res 1

; Variables used internally by SleepSec()
slp_ctr0        res 1
slp_ctr1        res 1

; Variables used internally by CpuSync()
cs_ctr          res 1           ; call counter

; Variables used internally by RunMotors()
rm_chan         res 2           ; chan loop variable
;rm_fsr0        res 2           ; temp save for FSR0
;rm_fsr1        res 2           ; temp save for FSR1
rm_fsr2         res 2           ; temp save for FSR2

; Variables used internally by ReadVels()
rv_state        res 1           ; state of recving data from IBMPC
rv_state_x4     res 1           ; state * 4 for GOTO jump table indexing
rv_newdir       res 1           ; last received dir byte from IBMPC
rv_lsb          res 1           ; lsb of data from IBMPC
rv_msb          res 1           ; msb of data from IBMPC
rv_is_stb       res 1           ; byte snapshot of IS_STROBE
rv_is_svel_stb  res 1           ; byte snapshot of IS_VEL_AND_STROBE
rv_velptr       res 1           ; ptr to vels[G_new_vix]
rv_dirptr       res 1           ; ptr to dirs[G_new_vix]
rv_msb_dir      res 1           ; =1 if hi bit of msb set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Motor related vars
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; uchar vels[2][MAXCHANS];       // 2x4 array of 8bit velocities sent from IBM PC
; uchar dirs[2][MAXCHANS];       // 2x4 array of 8bit velocities sent from IBM PC
vels            res (2*MAXCHANS)
dirs            res (2*MAXCHANS)

; Run index (either 0 or 1) for vels[] and dirs[] above:
;   vels[G_run_vix][chan], dirs[G_run_vix][chan]
;
G_run_vix       res 1       ; 0|1 index for vels[ix][chan] and dirs[ix][chan]
G_new_vix       res 1       ; index for new vels from IBMPC (opposite of G_run_vix's value)

; Flag to indicate when PC has finished sending us new vels
; so next IRQ can swap G_run_vix/G_new_vix and start using new vels.
G_got_vels      res 1       ; flag indicating if IBMPC finished sending us vels

; 16 bit position array, one 16bit value per channel.
;
;     ushort pos[MAXCHANS];
;
;     This is not actual motor positions, but a velocity accumulator used to
;     determine when a step pulse should be sent to a motor.
;     Each high frequency main loop iter, pos[c] is increased by vels[c], and
;     when it exceeds MAXFREQ, it's wrapped and triggers a step for that motor.
;
pos             res (2*MAXCHANS)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; USEFUL MACROS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; No macros because we need careful per-instruction timing
;

RES_VECT  CODE    0x0000                ; processor reset vector
    GOTO    START                       ; go to beginning of program

; ADD INTERRUPTS HERE IF USED

MAIN_PROG CODE                          ; let linker place main program

    ; Functions
    ;    Each function in separate .asm file to prevent having one
    ;    very long code to scroll up + down through during development.
    ;
    #include "a800-init.asm"            ; defines Init(): Initializes the PIC hardware
    #include "a800-sleep.asm"           ; defines SleepSec(): sleeps ~1 sec
    #include "a800-cpusync.asm"         ; defines CpuSync(): handshakes with the "other" PIC
    #include "a800-step.asm"            ; defines Step(chan,dir,val): sends a step pulse to a motor
    #include "a800-runmotors.asm"       ; defines RunMotors(): handles integer math to generate steps
    #include "a800-readvels.asm"        ; defines ReadVels(): handles reading values from the IBMPC

    ; Regression testing
    ; #include "a800-step_reg_test.asm" ; defines StepRegTest()

; main()
START:
    ; Init(); -- Initialize PIC hardware
    call    Init

    ;;
    ;; Variables init
    ;;

    ; G_portb = 0;
    banksel G_portb
    clrf    G_portb

    ; G_maxfreq = MAXFREQ;
    movlw   low MAXFREQ
    movwf   G_maxfreq+0
    movlw   high MAXFREQ
    movwf   G_maxfreq+1

    ; G_maxfreq2 = (MAXFREQ/2);
    movlw   low (MAXFREQ/2)
    movwf   G_maxfreq2+0
    movlw   high (MAXFREQ/2)
    movwf   G_maxfreq2+1

    ; G_maxchans = MAXCHANS;
    movlw   MAXCHANS
    movwf   G_maxchans

    ; G_freq = 0;
    clrf    G_freq+0
    clrf    G_freq+1

    ; G_run_vix = 0;  \_ must always be
    ; G_new_vix = 1;  /  opposite values
    movlw   0x00
    movwf   G_run_vix
    movlw   0x01
    movwf   G_new_vix

    ; G_got_vels = 0;
    clrf    G_got_vels

    ; for ( c=0; c<MAXCHANS; c++ ) { vels[0] = 0; dirs[0] = 0; pos[c] = (MAXFREQ/2); }
    lfsr  FSR0,vels
    lfsr  FSR1,dirs
    lfsr  FSR2,pos
    movlw 0

    ;;
    ;; Variables needing a chan loop for initialization
    ;;
main_initpos_loop:
    ; zero out uchar vels[2][MAXCHANS]
    clrf    POSTINC0                 ; vels[0][chan] = 0;
    clrf    POSTINC0                 ; (do it again since vels is a 2D array)
    ; zero out uchar dirs[2][MAXCHANS]
    clrf    POSTINC1                 ; dirs[0][chan] = 0;
    clrf    POSTINC1                 ; (do it again since dirs is a 2D array)
    ; Init ushort pos[*][chan]       ; _
    movff   G_maxfreq2+0, POSTINC2   ;  |_ pos[chan] = (MAXFREQ/2);
    movff   G_maxfreq2+1, POSTINC2   ; _|

    incf    WREG                     ; chan++
    cpfseq  G_maxchans               ; chan == MAXCHANS? skip if so
    goto    main_initpos_loop        ; loop if not

    ; cs_ctr = 0;
    clrf    cs_ctr

    ; Zero out Step() function arguments
    movlw   0
    movwf   stp_arg_chan
    movwf   stp_arg_dir
    movwf   stp_arg_step

;;  ; Some useful initial vels[] during early r&d testing
;;  ;
;;  ; vels[0] = 0x10
;;  lfsr    FSR0,vels
;;  movlw   0x10
;;  movwf   POSTINC0
;;  ;
;;  ; vels[1] = 0x50
;;  movlw   0x50
;;  movwf   POSTINC0
;;  ;
;;  ; vels[2] = 0x85
;;  movlw   0x85
;;  movwf   POSTINC0
;;  ;
;;  ; vels[3] = 0xf0
;;  movlw   0xf0
;;  movwf   POSTINC0
;;
;;  call    RunMotors
;;
;;#include "a800-readvels-regression-test.asm"  ; starts running right here
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; blink:       ; blink at ~1sec rate
;;    CLRWDT
;;    BCF PORTB,0
;;    call SleepSec
;;    BSF PORTB,0
;;    call SleepSec
;;    goto blink
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; Wait a second so both processors are fully initialized before doing sync.
    ; We don't want initialization noise to cause a false sync handshake.
    call    SleepSec
    call    CpuSync             ; sync both cpus /once/ before starting main loop

main_loop:
    CLRWDT

    ; call    CpuSync           ; [OLD] sync both cpus every iteration

    ; // Buffer ports with inputs
    ; G_porta = PORTA;     // port A is mix of in and out
    movff   PORTA,G_porta

    ; G_portc = PORTC;     // port C is all inputs
    movff   PORTC,G_portc


    ; ReadVels();
    call    ReadVels

    ; // Clear the step bits here, so they had time to stay high
    ; PORTB |= 0b01010101; // force step bits only, leave dir bits unchanged

    movf    LATB,W
    iorlw   b'01010101'
    movwf   PORTB

    ; // Keep motors running with current vels
    ; RunMotors();
    call    RunMotors

    ; PORTB = G_portb.all; // apply accumulated step/dir bits all at once
    movff   G_portb, PORTB
    goto    main_loop        ; FOREVEVER MAIN LOOP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;    ;; TESTING ONLY -- ADD +1 TO A CHAN VEL EVERY IRQ
;;    movf    LATA,W
;;    andlw   b'00010000'
;;    bz            main_loop
;;    incf    (vels+0),1
;;    goto    main_loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    END
