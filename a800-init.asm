; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; FUNCTION
;     Initialize the PIC hardware for our needs.
;     The BSR is left modified.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Init:
    MOVLB  0x0F ; Bank for SFRs (Special Function Regs)

    ; NOTE: in the following TRISA/B/C data direction registers,
    ;       '1' configures an input, '0' configures an output.
    ;       'X' indicates a don't care/not implemented on this chip hardware.
    ;
    ; PORTA  = 0;
    ; TRISA  = 0b11001101; //* data direction for port A (0=output, 1=input)
    ; WPUA   = 0b11001101; //* weak pullup resistors: enable for inputs needing it
    ; ODCONA = 0b00000000; //* open drain control (0=push/pull, 1=open drain)

    ;
    ;          ________ A7 16MHZ CLK  (in)  This is driven by the 16MHz external xtal, and must be an input
    ;         | _______ A6 CPU1_ACK   (in)  This is an input, regardless of which CPU# we're built for
    ;         || ______ A5 CPU1_SYNC  (out) This is an output, regardess of which CPU# we're built for
    ;         ||| _____ A4 IRQ_IBMPC  (out)
    ;         |||| ____ A3 CPU_ID     (in)
    ;         ||||| ___ A2 SVEL_8255  (in)
    ;         |||||| __ A1 ACK_8255   (out)
    ;         ||||||| _ A0 STB_8255   (in)
    ;         ||||||||
    movlw   b'00000000'
    movwf   PORTA, BANKED
    movlw   b'11001101'
    movwf   TRISA,  BANKED
    movwf   WPUA,   BANKED
    movlw   b'00000000'
    movwf   ODCONA, BANKED
    movlw   0
    movwf   PORTA,  BANKED      ; zero all PORTA outputs

    ; PORTB  = 0b00000000;
    ; TRISB  = 0b00000000; // data direction for port A (0=output, 1=input)
    ; WPUB   = 0b00000000; // weak pullup resistors: enable for inputs needing it
    ; ODCONB = 0b00000000; // open drain control (0=push/pull, 1=open drain)
    ; PORTB  = 0b11111111; // inverted outputs (steps go low to turn on gecko leds)
    ;
    ;          ________ B7 D-Direction (out)
    ;         | _______ B6 D-Step      (out)
    ;         || ______ B5 C-Direction (out)
    ;         ||| _____ B4 C-Step      (out)
    ;         |||| ____ B3 B-Direction (out)
    ;         ||||| ___ B2 B-Step      (out)
    ;         |||||| __ B1 A-Direction (out)
    ;         ||||||| _ B0 A-Step      (out)
    ;         ||||||||
    movlw   b'00000000'
    MOVWF   PORTB,  BANKED
    MOVWF   TRISB,  BANKED
    MOVWF   WPUB,   BANKED
    movwf   ODCONB, BANKED
    movlw   b'11111111'
    movwf   PORTB,  BANKED

    ; // PORT C: 8 BIT DATA BUS BETWEEN PIC AND 8255
    ; PORTC  = 0;
    ; TRISC  = 0b11111111; //* data direction for port A (0=output, 1=input)
    ; WPUC   = 0b11111111; //* weak pullup resistors: enable for inputs needing it
    ;
    ;          ________ C7 --
    ;         | _______ C6   |
    ;         || ______ C5   |
    ;         ||| _____ C4   |__ PC Data (in)
    ;         |||| ____ C3   |
    ;         ||||| ___ C2   |
    ;         |||||| __ C1   |
    ;         ||||||| _ C0 --
    ;         ||||||||
    MOVLW   b'00000000'
    MOVWF   PORTC,  BANKED
    movlw   b'11111111'
    movwf   TRISC,  BANKED
    movwf   WPUC,   BANKED
    movlw   b'00000000'
    movwf   ODCONC, BANKED

    ; ANSELA = 0x0; // Disable analog stuff
    ; ANSELB = 0x0; // Disable analog stuff
    ; ANSELC = 0x0; // Disable analog stuff
    movlw 0x0
    movwf ANSELA, BANKED
    movwf ANSELB, BANKED
    movwf ANSELC, BANKED

    ; ADCON0 = 0x0;   // disables ADC
    movlw 0x0
    movwf ADCON0, BANKED

    ; SLRCONA = 0x0;    // Disable slew rate controls
    ; SLRCONB = 0x0;
    ; SLRCONC = 0x0;
    movlw 0x0
    movwf SLRCONA, BANKED
    movwf SLRCONB, BANKED
    movwf SLRCONC, BANKED

    RETURN
