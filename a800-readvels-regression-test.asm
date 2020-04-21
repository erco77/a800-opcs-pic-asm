ReadVelsRegression:
    ;
    ; Simulate data transmissions from IBMPC
    ; To debug, use "run to cursor" to each of the NOP points below..
    ;
    ; TODO: Make this run automatically by checking all values
    ;       we expect, and on error, jump to an ERROR forever loop
    ;       with the WREG set to the error number.
    ;       Otherwise, jump to an OK forever loop.
    ;       Then the user can simply hit PAUSE and see where it stopped,
    ;       and if an error, what the error is in WREG.
    ;
    banksel rv_state
    movlw   0x00
    movwf   rv_state	; start in state 0
    movlw   0x55	; IBMPC_DATA - this will be vel for A_CHAN
    movwf   G_portc
    movlw   b'00000000'	; no strobe/no start
    movwf   G_porta
    call    ReadVels
    NOP    ; rv_state should be 0, waiting for SVEL+STB

    movlw   b'00000101'	; SVEL+STB
    movwf   G_porta
    call    ReadVels
    NOP    ; rv_state should be 11/0B

    call    ReadVels
    NOP    ; same

    movlw   b'00000000'	; UN-SVEL/UN-STB
    movwf   G_porta
    call    ReadVels
    NOP	    ; rv_state should be 12/0C
    
    movlw   b'00000001'	; STROBE PC DATA
    movwf   G_porta
    call    ReadVels
    NOP	    ; lsb should be 55
	    ; rv_state should be 13/0D
	    
    movlw   b'00000000'	; UN-STB
    movwf   G_porta
    call    ReadVels
    NOP	    ; rv_state should be 13/0d
    
    movlw   0x80	; IBMPC_DATA - this will be DIR for A_CHAN
    movwf   G_portc
    movlw   b'00000000'	; UN-STB
    movwf   G_porta
    call    ReadVels
    NOP	    ; rv_state should be 14/0e
    
    movlw   b'00000001'	; STROBE PC DATA
    movwf   G_porta
    call    ReadVels
    NOP	    ; msb should now be 80
	    ; rv_state should be 15/0f
	    
    call    ReadVels
    NOP	    ; same
    
    movlw   b'00000000'	; UN-STB
    movwf   G_porta
    call    ReadVels
    NOP	    ; rv_state should be 16/10
    
    call    ReadVels
    NOP	    ; rv_state now 17
	    ; vels[new_vix][0] should now be 55
	    ; dirs[new_vix][0] should now be 80

    goto    $

