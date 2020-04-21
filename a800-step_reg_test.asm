    ; --------------------------------------------------
    ; Step() function Regression testing
    ;
    ;     To use this as intended, set a breakpoint
    ;     for the "return" at the bottom of Step(), and single step,
    ;     watching G_portb and the 3 fstep_arg_xxx vars.
    ;
    ;     For each hit of "Continue" you should see:
    ;           1) G_portb = 01	<-- A step set
    ;           2) G_portb = 03 <-- A step+dir set
    ;           3) G_portb = 02 <-- A dir set
    ;           4) G_portb = 00 <-- A step+dir clr
    ;
    ;           5) G_portb = 04	<-- B step set
    ;           6) G_portb = 0c	<-- B step+dir set
    ;           7) G_portb = 08	<-- B dir set
    ;           8) G_portb = 00 <-- B step+dir clr
    ;
    ;           x) G_portb = 10	<-- C step set
    ;           x) G_portb = 30	<-- C step+dir set
    ;           x) G_portb = 20	<-- C dir set
    ;           x) G_portb = 00 <-- C step+dir clr
    ;
    ;           x) G_portb = 40	<-- D step set
    ;           x) G_portb = c0	<-- D step+dir set
    ;           x) G_portb = 80	<-- D dir set
    ;           x) G_portb = 00 <-- D step+dir clr
    ; --------------------------------------------------

StepRegTest:
    
    banksel fstep_arg_chan
    
    ; AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    ; Prepare to call Step
    movlw   0x00	; channel A
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    
    ; Prepare to call Step
    movlw   0x00	; channel A
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x00	; channel A
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x00	; channel A
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
    ; Prepare to call Step
    movlw   0x01	; channel B
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    
    ; Prepare to call Step
    movlw   0x01	; channel B
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x01	; channel B
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x01	; channel B
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step
    
    
    ; CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
    ; Prepare to call Step
    movlw   0x02	; channel C
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    
    ; Prepare to call Step
    movlw   0x02	; channel C
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x02	; channel C
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x02	; channel C
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step
    
    
    ; DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
    ; Prepare to call Step
    movlw   0x03	; channel D
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    
    ; Prepare to call Step
    movlw   0x03	; channel D
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x01	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x03	; channel D
    movwf   fstep_arg_chan
    movlw   0x01	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    ; Prepare to call Step
    movlw   0x03	; channel D
    movwf   fstep_arg_chan
    movlw   0x00	; direction (0=fwd, 1=rev)
    movwf   fstep_arg_dir
    movlw   0x00	; step value (1=step, 0=no step)
    movwf   fstep_arg_val
    call    Step

    return
    

