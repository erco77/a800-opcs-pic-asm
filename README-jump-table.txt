    ***
    NOTE: See also the "JUMP TABLE" section of README-pic-assembly-gotchyas.txt
    ***

    PIC18F PROGRAM COUNTER MODIFICATION
    
      When you write to the PCL (lower 8bits of the 21bit PC)
      with e.g. "addwf PCL", the value in latches PCLATU/PCLATH
      are brought down into the upper bits of the PC (PCU + PCH)
      as part of the write operation, so that all 21bits are
      adjusted atomically:
    
       __________________ _________________ _________________
      |                  |                 |                 |
      |      PCLATU      |     PCLATH      |  ADDWF RESULT   |
      |__________________|_________________|_________________|
                 |               |                  |
                 |               |                  | <------------ ADDWF PCL
       _________\|/_____________\|/________________\|/________
      |     :             |                 |                 |
      | 000 :    PCU      |      PCH        |       PCL       |
      |_____:_____________|_________________|_________________|
    
       \___/ \________________________________________________/
        |                   PC is 21 bits wide
        |
        Upper 3bits should be zero
    
    
      So make sure PCLATU and PCLATH are set before you adjust the PCL.
      See Section 7.3 in the PIC18C MCU reference manual (DS39507A).
    
      If the table straddles a page boundary, the following code is recommended:
      (See: https://www.microchip.com/forums/m452263.aspx )
    
           banksel index
           movlw   high my_Table
           movwf   PCLATH
           movlw   low my_Table
           addwf   index, W		; Value of 'index' indicates which Func_X to run
           btfsc   STATUS, C
          incf    PCLATH, F
           movwf   PCL
        my_table:
           goto    Func_0
           goto    Func_1
           goto    Func_2
           goto    Func_3
          :
    
    =============== THIS WORKS TOO, BUT ONLY IF NOT NEAR PAGE BOUNDARY =======
       movlw   high (jmp_table)
       movwf   PCLATH
       movlb   0x0f    ; Bank select the SFR's
       movlw   4	    ; <-- SELECTS CODE TO RUN (2=aaa, 4=bbb, 6=ccc, etc)
       addwf   PCL
    ==========================================================================
    

