    ; PIC18F PROGRAM COUNTER MODIFICATION
    ;
    ;   When you write to the PCL (lower 8bits of the 21bit PC)
    ;   with e.g. "addwf PCL", the value in latches PCLATU/PCLATH
    ;   are brought down into the upper bits of the PC (PCU + PCH)
    ;   as part of the write operation, so that all 21bits are
    ;   adjusted atomically:
    ; 
    ;    __________________ _________________ _________________
    ;   |                  |                 |                 |
    ;   |      PCLATU      |     PCLATH      |  ADDWF RESULT   |
    ;   |__________________|_________________|_________________|
    ;              |               |                  |
    ;              |               |                  | <------------ ADDWF PCL
    ;    _________\|/_____________\|/________________\|/_______ 
    ;   |    :             |                 |                 |
    ;   |000 :    PCU      |      PCH        |       PCL       |
    ;   |____:_____________|_________________|_________________|
    ;
    ;    \__/ \________________________________________________/
    ;     |                   PC is 21 bits wide
    ;     |
    ;     Upper 3bits should be zero
    ;
    ;
    ;   So make sure PCLATU and PCLATH are set before you adjust the PCL.
    ;   See Section 7.3 in the PIC18C MCU reference manual (DS39507A).
    ;
    ;   If the table straddles a page boundary, the following code is recommended:
    ;   (See: https://www.microchip.com/forums/m452263.aspx )
    ;
    ;	    movlw high Table
    ;	    movwf PCLATH
    ;	    movlw low Table
    ;	    banksel index
    ;	    addwf index, W
    ;	    btfsc STATUS, C
    ;       incf PCLATH, F
    ;	    movwf PCL
    ;	 Table
    ;	    goto l1
    ;	    goto l2
    ;	    goto l3
    ;	    goto l4
    ;
    ;================ THIS WORKS TOO, BUT ONLY IF NOT NEAR PAGE BOUNDARY =======
    ;    movlw   high (jmp_table)
    ;    movwf   PCLATH
    ;    movlb   0x0f    ; Bank select the SFR's
    ;    movlw   4	    ; <-- SELECTS CODE TO RUN (2=aaa, 4=bbb, 6=ccc, etc)
    ;    addwf   PCL
    ;===========================================================================
    

