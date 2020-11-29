<!-- vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4
     a800-opcs-pic-asm
-->

# PIC Firmware for OPCS A800 IBM PC ISA card - Stepper Motor Pulse Generator

    What is this project?
    ---------------------
    The Seriss Corporation OPCS (Optical Printer Control System) A800 board
    is an ISA motion control card for the IBM PC. It can manage up to 8
    stepper motors using 8 bit velocities for motor stepping rates from
    107 Hz to 27,285 Hz.

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

    How do I run a stepper motor using this software?
    -------------------------------------------------
    The computer sends stepper motor velocity values to the chip, and the chip
    handles the pulse train timing to make the motors run at that speed during
    the sample velocity time period (1/50th of a second). So sending a value of 1
    will send 50 pulses per second to the stepper motor.

    The chip can handle driving 4 stepper motors. With two chips programmed with
    the same software clocked by the same crystal, the two chips together can run
    8 stepper motors.

    The PIC chip generates an interrupt every time it's ready for a new set of
    velocities, which happens at approx 50 hz. The computer has that much time
    to write the four 16 bit velocity values to the PIC chip's internal buffer.
    On the next interrupt, it begins using the buffered velocities, and is ready
    to accept new velocities for the NEXT interrupt.

    The computer can send velocities to the PIC via simple hand-shaking using
    an 8 bit port and a few hand shaking bits. In the A800 application, an 8255
    24 bit I/O chip is used to interface between the IBM PC's ISA bus and the two
    synchronized PIC chips.

    Ignoring the details of the 8255 chip, the computer basically sends four
    16 bit velocities in order, 8 bits at a time; LSB first, MSB second.

    To begin a new stepper motor run, the computer first zeroes the PIC chip
    to initialize it:

       1. Set bits RA0 ("strobe") and RA2 ("Starting Velocities") to 1 to prepare PIC firmware for a new move
       2. Wait for acknowledge from the PIC: wait for RA1 to go high
       3. Clear strobe by setting RA0 and RA2 to 0
       4. Wait for acknowledge from the PIC: wait for RA1 to go low

    Pic is now ready to receive data on each interrupt pulse it sends from RA4,
    which is supposed to trip the computer's IRQ to send the 4 motor channels
    worth of 16 bit data as separate 8 bit quantities in this order:

        A LSB, A MSB, B LSB, B MSB, C LSB, C MSB, D LSB, D MSB

    ..so basically eight 8bit values are sent in order, and then the computer waits
    until the next interrupt tick to send the next velocities.

    Sending a single 8 bit value to the PIC involves this process:

       1. Wait for PIC to be ready to receive new data: wait for RA1 to go low
       2. Write low 8 bits of the A channel motor velocity to the PIC's PORT C (RC0 thru RC7).
       3. Strobe PIC to read the 8 bits of data by setting RA0 to 1
       4. Wait for ack from PIC: wait for RA1 to go high
       5. Clear strobe by setting RA0 to 0

    At the end of the motor move, the computer should send zero velocities to stop
    the motors, disabling the stepping pulse trains. By not writing new values, the PIC will
    simply keep sending last velocities written (0), keeping the motors stopped.

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


       IBMP PC                      OPCS A800 ISA CARD
      _________    #######################################################
     |         |   #                                                     #
     |         |   #                                                     #
     |         |   #                                                 ,---#--> Motor A steps
     |    IRQ5 |<--#----------------------------------------.        |---#--> Motor A dir
     |         |   #                                   _____|____    |---#--> Motor B steps
     |         |   #                                  |          |   |---#--> Motor B dir
     |         |   #         8255 PPI            ,--->| PIC CPU1 |---+---#--> Motor C steps
     |         |   #     ___________________     |    |__________|   |---#--> Motor C dir
     |         |   #    |                   |    |                   |---#--> Motor D steps
     |   0x300 |---#--->| 0x0300    PORT A  |----|                   `---#--> Motor D dir
     |   0x301 |---#--->| 0x0301    PORT B  |----|                       #
     |   0x302 |---#--->| 0x0302    PORT C  |----|                   ,---#--> Motor E steps
     |   0x303 |---#--->| 0x0303 CTRL WORD  |    |                   |---#--> Motor E dir
     |         |   #    |                   |    |     __________    |---#--> Motor F steps
     |         |   #    |___________________|    |    |          |   |---#--> Motor F dir
     |_________|   #                             `--->| PIC CPU2 |---+---#--> Motor G steps
                   #                                  |__________|   |---#--> Motor G dir
                   #                                                 |---#--> Motor H steps
                   #                                                 `---#--> Motor H dir
                   #                                                     #
                   #######################################################


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

MISC
----
    These links were useful to have open at all times during development:

    PIC 18F Instruction Set in HTML
    -------------------------------
    http://technology.niagarac.on.ca/staff/mboldin/18F_Instruction_Set/
    ..this is an HTML-ized version of the PIC 18F instruction set PDF.

    Also: https://onlinelibrary.wiley.com/doi/pdf/10.1002/9781119448457.app4
    In the data sheet, there's a chapter on the instruction set (below PDF's,
    in Chapter 36).

    PIC 18F24Q10 Data Sheet
    -----------------------
    "PIC18F24/25Q10 28-Pin, Low-Power, High-Performance Microcontrollers"
    See Chapter 36 for the instruction set.
    REV B: http://ww1.microchip.com/downloads/en/DeviceDoc/PIC18F24-25Q10-Data-Sheet-DS40001945B.pdf
    REV C: http://ww1.microchip.com/downloads/en/DeviceDoc/PIC18F2425Q10-28-Pin-Low-Power-High-Performance-MCU-40001945C.pdf

    PIC Assembler
    -------------
    "MPASM Assembler, MPLINK Object Linker, (etc) User's Guide"
    http://ww1.microchip.com/downloads/en/DeviceDoc/33014L.pdf
    ..useful stuff on the assembler; how to write macros, etc.

