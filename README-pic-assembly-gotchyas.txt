PIC INSTRUCTION FORMAT

    See: http://ww1.microchip.com/downloads/en/DeviceDoc/33014L.pdf
    ..specfically the subsection entitled "Instruction Set".

    Also: Find and look over the contents of the PIC include file for your
    processor to see what macros are defined. In my case the PIC 18F24Q10
    file is in:

        C:\Program Files (x86)\Microchip\MPLABX\v5.25\mpasmx\p18f24q10.inc

    Looking at this file, you can see important macros the assembler predefines
    that are often used throughout PIC assembly instructions, e.g.

        FSR0             EQU  0
	FSR1             EQU  1
	FSR2             EQU  2
        [..]
	W                EQU  0      \__ Used in e.g.
	A                EQU  0      /   DECF   my_var,W,A 
	ACCESS           EQU  0                         \_\___ used here
	BANKED           EQU  1

    General Syntax
	Assembly appears in space separated columns:

            <label>  <mnemonics/ops>   <operands>    <comments>

        Example:

		     list              p=18f24q10
		     #include          somefile.inc
	    Dest     equ               0x0b          ; define constant
		     org               0x0000
		     goto              Start
	    Start
		     movlw             0x0A
		     movwf             Dest
		     bcf               Dest, 3
		     goto Start
		     end

    Numeric constants:

	0xff        - hex  (also H'ff')
	.255        - decimal (also D'255')
	b'01010101' - binary (also B'01010101')

	low 0x1234  - gets 0x34
	high 0x1234 - gets 0x12

    String constants:
        'z'         - the character 'z' (also A'z' for ASCII char 'z')

    Assembler constants ("equates"):

        MAXFREQ    equ .300     ; declares macro MAXFREQ equal to 300 decimal (0x012c)
	MAXCHANS   equ .4

    Macro constants:

	#define    CPU_ID   PORTA,3        ; C preprocessor style macro
	#define    BIT_MASK b'00000101'    ; binary bitmask

    Variables:

        my_char  res 1		; declare 1 byte variable "my_char"
	my_int   res 2          ; declare 2 byte variable "my_int"
     
    Conditional code blocks:

        if (expr)     ; preferred
	#if (expr)    ; supported
	.if (expr)    ; supported

	Example:

	   if version == 100
	       movlw 0x0a
	       movwf io_1
	   else
	       movlw 0x01a
	       movwf io_2
	   endif

    "Operands"
        ..and those weird comma-separated letter/number flags after the instruction
	that are super important for understanding what the instruction will do.

	    DECF   my_var,W,A        DECF myvar,0,0
	           \________/             \________/
		    Operands               Operands

	Often there are comma separated letters or 0/1 values after the first
	operand, which tell the instruction what bank of memory to use, and what
	the destination for resulting values should go (W=WREG, F="File" Memory).

	Example:

	    DECF   my_var,W,A
	                  | |
			  | Access bit: can be B(BSR Bank) or A(Access Bank)
			  Destination bit: can be F("File" memory) or W(WREG)

	The WREG is considered the general "accumulator" register.

	The F/W "destination" and B/A "access" letters are really MACROS 
	that resolve to 0 or 1 values.

	For this reason these letter symbols are always UPPER CASE.

	Using the numeric 0/1 equivalents are also valid, but it's better
	for readability to use the macro names:

	    For "Destination Bit":
		F = 1 ; Result is placed in File Register
		W = 0 ; Result is placed in WREG Register

	    For access bit:
	        B = 1 ; Register used specified by BSR Bank Register
	        A = 0 ; Register used is in Access Bank

	So the "numeric equivalent" for the above "DECF  my_var,W,A" instruction is:

	    DECF   my_var,0,0
	                  | |
			  | Access bit: 0="A"=Access Bank
			  Destination bit: 0="W'=WREG

        When destination is "F", a memory location is modified (based on "Access").
	When destination is "W", the WREG is modified.

	When Access is "B", the BSR register determines the bank for memory accesses.
	When Access is "A", the "access bank" is used (which lets one access the first
	128 bytes in Bank Zero, and the last 128 bytes in Bank 15 which can access the 
	"Special Functions Registers") So with the Access Bank selected, one can access
	both low memory variables AND the Special Function Registers, without having to
	switch banks.

	OK, then there's bit testing things like the STATUS register, which uses
	some different UPPERCASE macros:

	    BTFSS    STATUS,0,C
	                |   | |__ C="Carry" (can be Z, C, DC, OV)
			|   |
	                |   |____ 0=Access bank (STATUS is an address within the Access bank) (Could also be "A" instead of "0")
			|
	                |________ STATUS is an address to the SFR (Special Function Register) "Status" register

    Data Memory:

        So memory is 15 banks of 256 bytes each. The BSR register (Bank Select Register)
	lets one choose which bank is being accessed, so that single byte addresses can
	be used to access memory within that bank.

        BSR       Data Memory
		  __________________
	0000b    |                  |
	         |    Segment 0     |------.
	         |- - - - - - - - - |       \
		 |      Bank 0      |        \
		 |__________________|         \
	0001b    |                  |          \
	         |                  |           \
	         |      Bank 1      |            \
		 |                  |             \
		 |__________________|              \        Access Bank
	0010b    |                  |               \      .-----------. 00h
	         |                  |                `---> | Segment 0 |
	         |      Bank 2      |                      |-----------| <-- DEVICE DEPENDENT BOUNDARY!
		 |                  |                ,---> | Segment 1 |
		 |__________________|               /      |___________| ffh
		 :                  :              /
		 |__________________|             /
	1110b    |                  |            /         When the "Access Bit" is "A"(0):
	         |                  |           /
	         |      Bank 14     |          /               > The BSR is ignored and the Access Bank is used
		 |                  |         /                > The "Segment 0" is the first bytes in RAM
		 |__________________|        /                 > The "Segment 1" is the Special Functions Registers
	1111b    |                  |       /                    from the last bytes in Bank 15, and whose addresses
	         |      Bank 15     |      /                     and functions are DEVICE SPECIFIC.
	         |- - - - - - - - - |     /
		 |     Segment 1    |----`
		 |__________________|

         So when the "Access Bit" of an instruction is "B"(1), the BSR is used to specify
	 the RAM location the instruction uses.

         XXX: So if the boundary between Segment 0 and Segment 1 are device specific,
	      how do you know how much RAM you can access via "Segment 0" if you don't know
	      where the boundary is??



    PIC18F Assembly Instructions:
	See: https://ww1.microchip.com/downloads/en/DeviceDoc/31029a.pdf
	Section 29

        In the instruction documentation, these lowercase letters indicate
        information about the operands:

	    f   - register file address (0x00 ~ 0x7f) to be used by the instruction
	    d   - destination bit: either 0 or 1:
		      0=W: Stored result will be in W (WREG)
		      1=F: Stored result will be in File register as specified by address 'f'
	    b   - bit address within an 8-bit file register (0 to 7)
	    k   - Literal field, constant data, or label (can be 8-bit or 11-bit)
	    x   - Don't care (0 or 1)
		  Assembler will generate code with x=0.
	    dest  Destination either the W register or the specified register file location

	EXAMPLE

	    The following code runs from top to bottom, showing results each step:

            MOVLB             ; set BSR to bank 5. All memory accesses from here on will be within this bank

                              ; MEM   ACCESS   WREG
			      ; 0x7F  0x5A       X   <-- starting value
			      ;  |     |         |
			      ; \|/   \|/       \|/
			      ;  v     v         v
            DECF my_var, F, B ; 0x7E  0x5A       X   <-- mem from BSR reg bank is decremented and saved back, e.g. 7F-01=7E
	                      ;
	    DECF my_var, F, A ; 0x7E  0x59       X   <-- mem in Access Bank is decrememented and saved back, e.g.  5A-01=59
	                      ;
	    DECF my_var, W, B ; 0x7E  0x59     0x7D  <-- mem is decremented, result saved in WREG
	                      ;  |               ^
	                      ;  |              /|\
			      ;   `---- DEC -----`
			      ;
	    DECF my_var, W, A ; 0x7E  0x59     0x58  <-- mem in Access Bank decremented, saved in WREG
	                 |  | ;         |        ^
	                 |  | ;         |       /|\
			 |  | ;         `--DEC--`
	                 |  |
	                 |  |___ "access" can be "B" or "A" -- F=1=File Register, W=0=WREG
			 |
	                 |______ "destination" can be "F" or "W" -- B=1=BSR Bank addressing, A=0=Access Bank addressing
        

VARIABLES
---------
    I've declared all variables as uninitialized in RAM with e.g.

        my_vars         udata 0x80      ; Originate variables at 0x80, past low memory area used by processor
	G_maxfreq       res 2           ; indicates 2 bytes of uninitialized data
	G_maxfreq2      res 2

    Variables are uninitialized because RAM is random on boot; the only program
    memory loaded is in ROM, so we have to initialize variables ourselves.

    The assember does provide directives for pre-initialized variables, but 
    involves running assembler generated code to do the initialization, so
    I'd rather do that code myself.

    All variable initialization is in 'MAIN', and is done after the CPU hardware
    initialization, which is first done by the config bits (a800-config.h) followed
    by code in a800-init.asm.

BOOT PROCEDURE
--------------
    On boot these things happen in order:

        1) PIC starts up with the config bits defined in a800-config.h to set the
	   CPU speed and external 16MHz clock on RA1.

	2) PIC jumps to 0x0000 which we configure to have a GOTO instruction to jump
	   over the interrupt and low memory area reserved for the processor to our
	   MAIN code:

	       RES_VECT  CODE    0x0000            ; processor reset vector
	       GOTO    START                       ; go to beginning of program

	       [..#included code..]

	       ; main()
	       START:
	           ; Init(); -- Initialize PIC hardware
		   call    Init
		   [..]

	   ..which the first thing it does is call Init(), defined in a800-init.asm,
	   which initializes the rest of the hardware for I/O, disables features we don't
	   use like analog I/O, timers, etc.

	3) Variable initialization
	   Initializes all the RAM variables to proper values, since their contents is
	   random on boot.

	4) Sleep for about 1 second.
	   This allows both processors (CPU1 and CPU2) time to boot/initialize I/O
	   enough to be able to be safely synchronized by the next step..

	5) Synchronize the CPUs by calling CpuSync(), defined in a800-cpusync.asm.

	   The A800 board has 2 PIC chips, and they must run the main code perfectly
	   synchronized in order to run the stepper motors correctly.

	   CPU1 sends a strobe signal to CPU2 and waits for CPU2 to acknowledge it.
	   When CPU2 sees the strobe it raises the acknowledge, causing CPU1 to drop
	   the strobe signal and wait for ACK to drop to 0, then both processors
	   begin their main loop perfectly synchronized.

	6) The main loop runs and never exits.

PREVENTING RACES ON PORT BITS
-----------------------------
    To prevent strange race conditions when reading port bits in order,
    a snapshot is made of the input ports at the beginning of each iteration
    of the main loop:

	; // Buffer ports with inputs
	movff   PORTA,G_porta	; snapshot PORT1 -> G_porta variable buffer
	movff   PORTC,G_portc	; snapshot PORT1 -> G_porta variable buffer

    This way bits can be tested in the port serially without concern one bit
    or the other changed during the serial execution; we want the main loop
    to operate as if it all runs instantly, so for this we snapshot the input
    variables.

    Also, when we want to change bits, we accumulate the changes in the buffer
    variable, then write out the bits all in one instruction at the end of the
    main loop. This is important especially for the step bits, to ensure all
    4 motor channels receive their step pulse at the same moment, and not chan A
    first, then a few uSecs later chan B, etc. e.g.

        ; PORTB = G_portb.all; // apply accumulated step/dir bits all at once
	movff   G_portb, PORTB
	goto    main_loop        ; FOREVEVER MAIN LOOP


    There are some careful use cases where the port is written directly instead
    of being buffered, e.g. the IBMPC_IRQ bit:

        #define IBMPC_IRQ_BIT       LATA,4
	[..]
	bsf     IBMPC_IRQ_BIT
	[..]
	bcf     IBMPC_IRQ_BIT

MANAGING ARRAYS
---------------
    There are at least three arrays in the code:

        vels - 2D array of 8bit values; uchar vels[2][4]
	       ..where [2] is the "new" vs "now" velocities:

	           vels[new_vix][chan] being the ones being read in from the IBM PC
		   vels[now_vix][chan] being the ones currently writing to the stepper motors

	       In the code, FSR0 is used to index this array.

	dirs - 2D array of 8bit values; uchar dirs[2][4]
	       This is the "new" vs "now" direction bits:

	           dirs[new_vix][chan] being either 0 (fwd) or 1 (rev) for vels being read from IBM PC
		   dirs[now_vix][chan] being either 0 (fwd) or 1 (rev) for vels currently sent to stepper motor

	       In the code, FSR1 is used to index this array.

	pos - 1D array of 16bit values; ushort pos[4]
	      This variable contains the accumulated velocity count used to detect
	      overflows that cause each step pulse to be generated.

    Auto-incrementing indexing of the FSR registers is used to both
    initialize and manage these arrays.

    For the vels[][] and dirs[][] arrays, the two index variables new_vix and now_vix
    are used to calculate the first dimension of the array; reading from the PC uses the
    new_vix index, and writing steps uses the now_vix. These two variables always hold the
    opposite value; when new_vix is 1, now_vix is 0. And these alternate every time new
    velocities are loaded each IRQ interrupt.

SYMMETRIC EXECUTION OF CONDITIONALS
-----------------------------------
    This is a very important consideration in this code, as both processors
    are running the same code, and must stay in sync.

    To do this, each iteration of the main loop must be the exact same
    number of cpu cycles in execution time, no matter what "IF" conditions
    occur in the code.

    Whenever there is a conditional, there's the potential for breaking execution
    time symmetry.

    To avoid this, EVERY condition in the code has the faster path of execution 
    padded out with NOPs to ensure regardless of which condition path is taken,
    the execution time is the same.

    This means the main loop's execution time is always the worst case execution
    time. It has to be, to ensure consistent timing.

    So every branch/skip operation has to be carefully timed, care taken where
    GOTO commands are skipped (which are 4 byte instructions), which means when
    a skip occurs, the skip path can take 3 cycles (instead of 2, and the non-skip
    path can take 1 cycle.

    Cycle counts for instructions are documented in the instruction set manual:

         ONLINE: http://technology.niagarac.on.ca/staff/mboldin/18F_Instruction_Set/
	OFFLINE: pic-instruction-set.pdf

PROCESSOR SPEED
---------------
    On the A800 board, the processor runs at its max clock speed of 64MHz.
    A single instruction cycle takes 4 cycles of the cpu clock, which means 16MHz.

    The external crystal clock is 16MHz, which is fed into both PIC chips to clock
    them at the same rate with the same crystal frequency. The cpus have a 4XPLL
    (Phase Locked Loop) that raises the 16Mhz to 64Mhz.

    Since each instruction cycle is 16MHz, a single NOP at this speed executes in
    1/16,000,000th of a second, or 0.0000000625 secs, or 0.0625 uSecs.

    16 nops will run in .096 uSecs (pretty close to 1uSec).

USING MACROS FOR BIT MANIPULATION
---------------------------------
    The assembler might provide a better way to directly access individual
    I/O bits, but I've been using macros to do this.

    Some instructions use e.g. "portname,<bit#>" to set/test bits, e.g.

    	bsf   LATA,4
	bcf   LATA,4

    ..while others would need to use a bit mask, e.g.

	andlw b'00000100'
	xorlw b'00000100'
    
    To avoid confusion, I used _BIT for the former, and _MASK for the latter
    as a macro naming convention, e.g.

	#define IBMPC_IRQ_BIT       LATA,4
	[..]
	bsf IBMPC_IRQ_BIT       ; becomes "bsf LATA,4", sets bit 4 of PORTA
	bcf IBMPC_IRQ_BIT       ; becomes "bcf LATA,4", sets bit 4 of PORTA

	#define IBMPC_STB_MASK      b'00000101'
	[..]
	andlw IBMPC_STB_MASK
        xorlw IBMPC_STB_MASK

    WARNING: Don't mix them up: the compiler won't throw an error if you 
    accidentally use XXX_BIT name with e.g. andlw; if the bit number is 
    0 or 1, that can end up looking like the syntax the assembler uses 
    for setting the instruction set's 'd' destination option flag for 
    e.g. "ADDWF REG,0" vs "ADDWF REG,1".

BEST WAY TO MOVE DATA
---------------------
    This PIC has a MOVFF instruction, which will transfer data from/to
    memory in a single instruction that takes 2 cycles.

    So e.g.
       movff from,to

    If you need to move lots of data around, you can use the
    auto-incrementing indexing registers (FSR0 == POSTINC0, FSR1 == POSTINC1, etc):

       movlw 0                          - Load WREG with 0
       movff WREG,POSTINC0		- Puts WREG's 0 into mem pointed to by FSR0 and increments it
       movff WREG,POSTINC0		- Puts WREG's 0 into mem pointed to by FSR0 and increments it
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
    execution time. A jump table ensures a fixed execution time to resolve
    no matter which index is used for the switch().

    With a jump table, no matter which index is used for the switch(),
    one can run the proper code after a simple few math instructions
    to handle the full 21bit memory address to jump to, so that even
    if the table crosses a page boundary, the address will be correct.

    The jump table is a series of GOTO commands which are 4 bytes each,
    allowing for a constant of 4 to be used for index step rate.

    So assuming "my_index" contains the 8bit index number (0,1,2,3...)
    of the function we want to jump to:

	    ; Multiply index by 4 and save, to properly jump into the GOTO table..
	    movf    my_index,W            ; index -> WREG                       _
	    rlncf   WREG,0,0              ; rotate left to multiply by 2         |__ multiply by 4
	    rlncf   WREG,0,0              ; rotate left again to multiply by 2  _|
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

     For more info on jump tables, see ./README-jump-table.txt
