MOVFF TIMING: 2 CYCLES OR 3?
----------------------------
    The docs for movff say the #cycles is "2(3)", but apparently
    it's only ever 2, according to this thread:
    https://www.microchip.com/forums/m52915.aspx
    ..which says it's a constant 2 cycle instruction.

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


