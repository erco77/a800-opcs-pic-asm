BEST WAY TO MOVE DATA
---------------------
     This PIC has a MOVFF instruction, which will transfer data from/to
     memory in a single instruction that takes 2 cycles.

     So e.g.
     	movff from,to

     If you need to move lots of data around, you can use the
     auto-incrementing indexing registers (FSR0 == POSTINC0, FSR1 == POSTINC1, etc):

	movlw 0
     	movff WREG,POSTINC0		- Puts 0 into mem pointed to by FSR0 and increments it
     	movff WREG,POSTINC0		- Puts 0 into mem pointed to by FSR0 and increments it
     	movff WREG,POSTINC0		- etc

     Or from one memory location to another:

	movff POSTINC1,POSTINC2		- move from FSR1 -> FSR2, increment both


MOVFF TIMING: 2 CYCLES OR 3? (ANS: 2)
-------------------------------------
    The docs for movff say the #cycles is "2(3)", but apparently
    it's only ever 2, according to this thread:
    https://www.microchip.com/forums/m52915.aspx
    ..which says it's a constant 2 cycle instruction.

    Checking in the simulator with the stopwatch function, it's clear
    it's a 2 cycle instruction.

BEST WAY TO WALK AN INDEX?
--------------------------
    Load the e.g. FSR0 reg using 'lfsr' to point to the head of
    the mem you want to index, but when it comes to accessing the
    memory with e.g. movf or movff, use POSTINC0 (instead of FSR0):

	    movwf POSTINC0

    ..which will index thru FSR0 to resolve memory, and will autoincrement
    FSR0 properly.

    If you don't want to auto-increment, and just want to index FSR0,
    then use e.g. INDF0 in place of FSR0:

	    movwf INDF0

    To manually adjust FSR0, /don't/ adjust FSR0, refer to the separate 8bit
    FSRL/FSRH instead. Trying to adjust FSR0 *apparently is a NOP*.

JUMP TABLE
----------
    A jump table is used for the large "32 state" state machine, to avoid
    having a long series of multiple "IF" statements that take a lot of
    execution time.

    With a jump table, no matter which index is used for the switch(),
    one can run the proper code after a simple few math instructions
    to handle the full 21bit memory address to jump to, so that even
    if the table crosses a page boundary, the address will be correct.

    The jump table is a series of GOTO commands which are 4 bytes each,
    allowing for a constant of 4 to be used for index step rate.

    So assuming "my_index" contains the 8bit index number (0,1,2,3...)
    of the function we want to jump to:

	    ; Multiply index by 4 and save, to properly jump into the GOTO table..
	    movf    my_index,W            ; state -> WREG
	    rlncf   WREG,0,0              ; rotate left to multiply by 2
	    rlncf   WREG,0,0              ; rotate left to multiply by 4
	    movwf   my_index_x4,BANKED    ; save x4 result for actual PCL adjust below

	    ; Now do the math for the jump table that handles page boundaries..
	    movlw   high (my_jmp_table)   ; Get hi address of jmp table, and..
	    movwf   PCLATH                ; ..put it in PCLATH (high PC latch).
	    movlw   low  (my_jmp_table)   ; Get low address of jmp table..
	    addwf   my_index_x4,W,BANKED  ; add on the index * 4, sets carry on overflow (page bound)
	    btfsc   STATUS,C		  ; carry clear? Skip
	    incf    PCLATH,F		  ; carry set? inc PCLATH

	    movwf   PCL         	  ; <-- THIS single instruction causes the actual jmp into my_jmp_table,
	    				  ;     triggering the PC counter to simultaneously load itself with:
					  ;          > High bits from PCLATH
					  ;	     > Low bits from WREG
	my_jmp_table:
	    goto STATE_0		; ends up here if WREG was 0
	    goto STATE_1		; ends up here if WREG was 1
	    goto STATE_2		; ends up here if WREG was 2
	    ..etc..


