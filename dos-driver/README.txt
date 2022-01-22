This is the code for the DOS TSR Driver for the A800 board
to work with the OPCS software, and related C programs.

Start this driver once after the machine boots, e.g. via
the autoexec.bat.

When OPCS starts up, it will detect the driver's intercepting
INT 99H, and will use that interrupt to communicate with the
driver to setup pointers to the application's motor counters,
64k velocity ringbuffer to run the motors, etc.

To run a motor, the C application needs to (this is no where
near complete details, just the basics):

    1) The "Kuper" structure is defined and initialized:

	typedef struct {
	    uchar *ringbuffer;		// far pointer to 64K ring buffer
					// (char* because HEAD+TAIL are byte indexed)
	    long *counter;		// far pointer to (long) pulse counters
	    uint head,tail;		// ring buffer head/tail pointers
	    int stopped,		// motor routine hit last vels
		fault,			// a synchronization fault occurred
		allstop,		// C program flags int routine to allstop
		counttype;		// NOCOUNT || STEPCOUNT || FULLROTCOUNT
					// (describes how to update counters)
	    uint allstopaddress;	// new ring tail address for rampdown
	} Kuper;

       Where:
           counter[] is a pointer to the application's long counter array
	   that keeps track of all the motor positions.

	   counttype must be set to the type of counter adjustments
	   the motors being moved should make:

		NOCOUNTTYPE    -- No counter updating (homing motors)
		STEPCOUNTTYPE  -- Counters count in steps (focus, n/s/e/w, pan, zoom, etc)
		ROTCOUNTTYPE   -- Counters count in rotations (cam/pro shutters)

	   To count in ROTCOUNTTYPE, the FULLROTBIT must be set on
	   velocities that represent a full motor rotation.

    2) Some initial velocities are saved into the kuper->ringbuffer,
       advancing the kuper->head as needed.

    3) At some point the kuper driver is called to (a) tell it
       where the kuper structure is, and (b) start interrupts
       pulling values from the ringbuffer and sending them to the
       A800 card to start moving the motors.

       This is done by calling INT 99H:

	    static void start_kuper(void);
	    {
		union REGS in, out;

		// GIVE A800 DRIVER ADDRESS OF ABOVE Kuper STRUCTURE
		in.h.ah = 0;		        // Function 0: Set Kuper structure
		in.x.bx = FP_OFF(kuper);        // bx is offset of struct
		in.x.cx = FP_SEG(kuper);        // cx is segment of struct
		int86(0x99, &in, &out);         // INT 99H

		// START INTERRUPTS
		in.h.ah = 1;		        // Function 1: Start interrupts feeding
		int86(0x99, &in, &out);         // vels from kuper->ringbuffer to motors

		return;
	    }

     4) The C application then continues to push motor velocities into the 
        kuper->ringbuffer, adjusting kuper->head as it does. 

	The application can also be displaying the value of the 
	kuper->counter[] values in real time.

     5) When the motors should stop, special velocities are loaded
        into the ringbuffer that have the STOPBIT bit set (0x8000).
	(See a800drv.asm for the STOPBIT details), and when those
	get sent to the motors by the driver, the driver will
	automatically stop the interrupts, and flag to the application
	the motors have stopped by setting kuper->stopped = 1
