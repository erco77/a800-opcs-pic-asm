# a800-opcs-pic-asm

PIC Firmware for OPCS A800 IBM PC ISA card - Stepper Motor Pulse Generator

    What is this project?
    ---------------------
    The Seriss Corporation OPCS (Optical Printer Control System) A800 board
    is an ISA motion control card for the IBM PC. It can manage up to 8
    stepper motors using 8 bit velocities for motor stepping rates from
    57 Hz to 12,800 Hz.

    OPCS is commercial software. However, the stepper motor board itself
    (PCB design), the board's PIC chip firmware (this code here), and 
    related device drivers (A800DRV.ASM) will all be open source, so that
    other programs can be written to control motors with this board, and
    the board can be freely printed and used by others interested in doing
    stepper motor control using motor velocities.

    What does one do with this code?
    --------------------------------
    The assembly files here are meant to be brought into Microchip's
    free MPLABX (v.5.25) IDE environment for programming PIC chips 
    in either C or PIC assembly.

    In this case the code here is intended for the PIC assembler (MPASM 5.84),
    so one would create a new "PIC Assembler" project in the MPLABX IDE,
    and then bring in the .asm files of this github repo into the MPLABX project.

    The separate README-mplabx.txt file describes how to bring this code into
    MPLAB in order to build and burn onto the PIC chips.

    The opcs-a800-asm.asm file is the top level file, and is the only file the
    IDE needs to be told about. This file will pull in all the other .asm files
    using "include", and the IDE will bring up those files during debug sessions
    automatically.

    What's a PIC chip?
    ------------------
    The PIC chips are single chip computers that have their own flash memory,
    static memory, and are basically programmable I/O pins. 

    The chips used for this project are the PIC18F24Q10, a 28 pin through-hole
    chip that can run at 64MHz either with its own internal clock, or by an
    external 16MHz crystal (which the A800 board uses), that runs the CPU at
    64Mhz with a 4x PLL inside the chip.

    Except for the +5 and ground pins, all the other pins on the 28 pin chip
    can be used for digital I/O. (We don't use any of the analog features of
    these chips)

    The chips are socketed on the A800 board so the chips can be
    easily inserted/removed during development. These chips are very
    cost effective, around $1.16 each as of this writing, and can be
    re-programmed repeatedly using a simple protoboard and a PicKit4 USB
    programmer (around $50), and the free MPLABX software which comes
    with both the C compiler and Assembler.

    Does this code use any special features of this PIC?
    ----------------------------------------------------
    This project is pretty much straight simple code, no threading or timers,
    or really any special hardware features of the chip are used, other than
    its ability to run at high speed (64MHz) and its programmable ditial
    I/O pins running in normal +5/gnd TTL/CMOS compatible operation, with
    built-in pullups on the programmed inputs.

    How fast can this chip run stepper motors?
    ----------------------------------------------
    For micro stepping drives that run motors using 2000 pulses per revolution,
    this means motor speeds range in RPS (Revs Per second) from .02 RPS to 6.3 RPS,
    or a top speed of 1 full rotation every 0.15 seconds. (Speeds slower than 
    .02 RPS can be achieved by sending a velocity of 1 followed by any value
    delay, so really there's no slow speed limit.)

    Two on board PIC chips (PIC18F24Q10) running at 64MHz each use the firmware
    in this project to manage reading velocities from the IBM PC (via an 8255 PIA)
    and generates stepper motor pulses that can directly run micro-stepping
    stepper motor drivers like the Gecko 201X and Centent CNO-142/143.


       IBMP PC                     OPCS A800 ISA CARD
      _________    .................................................
     |         |   :                                               :
     |    IRQ5 |<-------------------------------------.            :
     |         |   :                                  |            :
     |         |   :        8255 PPI            ,--> PIC CPU1 -----:--> Motor A steps    
     |         |   :    ___________________     |              |---:--> Motor A direction
     |         |   :   |                   |    |              |---:--> Motor B steps    
     |   0x300 |---:-> | 0x0300    PORT A  |----|              |---:--> Motor B direction
     |   0x301 |---:-> | 0x0301    PORT B  |----|              |---:--> Motor C steps    
     |   0x302 |---:-> | 0x0302    PORT C  |----|              |---:--> Motor C direction
     |   0x303 |---:-> | 0x0303 CTRL WORD  |    |              |---:--> Motor D steps    
     |         |   :   |                   |    |              `---:--> Motor D direction
     |         |   :   |___________________|    |                  :
     |_________|   :                            `--> PIC CPU2 -----:--> Motor E steps
                   :                                           |---:--> Motor E direction
                   :                                           |---:--> Motor F steps
	           :                                           |---:--> Motor F direction
	           :                                           |---:--> Motor G steps
	           :                                           |---:--> Motor G direction
	           :                                           |---:--> Motor H steps
		   :                                           `---:--> Motor H direction
		   :                                               :
                   :...............................................:


    How does the PC use this A800 card to run a motor?
    --------------------------------------------------

    The card design runs motors using velocity values. An 8 bit number
    between 0 and 255 is the number of stepping pulses sent in 1/50th
    of a second.  So a value of 0 means dead stop, a velocity value of
    1 generates pulses at 50Hz, a velocity of 2 is 100Hz, a value of 3
    is 150Hz, etc. up to 255 for 12,750Hz.

    When the PC wants to run the motors, it enables the 8255, and sends
    8 new velocities in response to each interrupt request (IRQ5), which
    comes at a 50Hz rate.

    So to run the two motors A and B motors moving at the same rate,
    on receipt of the first IRQ, the PC might send:

         5 to channel A
	 5 to channel B
	 0 to channel C
	 0 to channel D
	 :
	 : etc
	 :
	 0 to channel H

    Then 1/50th of a second later, the A800 board will send another interrupt,
    which will feed the above 5 vel to channel A and B, and zeroes to C-H, and
    the PC will send the next 8 velocities, e.g. a little faster:

         10 to channel A
	 10 to channel B
	 0  to channel C
	 :
	 : etc
	 :
	 0  to channel H

    In this way, precise motor ramping and positioning is possible over time.
    All the software has to do is keep the velocities coming each time an
    interrupt is received. So the software must have the 8 vels ready to go
    50 times a second, otherwise a fault will occur.

    A DOS device driver, "A800DRV.ASM" written in 8086 assembly language
    is used to feed the motors to the card, and C programs can write to the
    driver's 64K ring buffer to ensure staying well ahead of the motors.

    The device driver is written in such a way to allow the commercial
    OPCS software to control the A800 board in the same way it has with
    other commercial industrial stepper motor cards.

    The DOS driver source code is also provided on github.

    I'm also working on an RTLINUX device driver, and may also write a
    regular linux device driver, if possible, and if so will provide it
    on github as well, as it seems possible for modern linux kernels 
    (as of 2020) are capable of "reliable enough" realtime execution 
    if the executable is running at a high enough priority and has memory
    pages locked down to prevent it being swapped out by another process
    hogging memory. 

