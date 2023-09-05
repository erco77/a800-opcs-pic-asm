SENDING VELOCITIES FROM THE IBM PC TO THE A800 BOARD
----------------------------------------------------

The timing diagram on the back of the A800 board shows the handshake control signals
between the IBM PC and PIC chips (via the 8255) used to send velocities to the A800 board.
(This same diagram is on SHEET 4 of the A800 board's schematics) The software has to
flip bits on the 8255 to match the diagram to send the velocities to the two PIC chips.

Each time the IBMPC receives an interrupt from the A800 (IRQ5), it should load the 4
new channel velocities to each of the PIC chips: channels A,B,C,D to CPU1, and E,F,G,H
to CPU2. The velocities are 16 bit values per channel, and are sent one byte-at-a-time.

The diagram shows the PC sending a "Start of Velocities" signal (SVEL) to one of
the PIC chips, and waits for an ACK. This tells the PIC we're about to send 4 channels
of data.

The PC then loads each byte to the 8255's PORT A (LSB first, MSB second) and strobes
each byte of data by raising STB, waiting for an ACK from the PIC, then lowering STB,
and waiting for the PIC to clear the ACK. This process is then repeated until all 4 velocities
(8 bytes total) are sent to the PIC.

There's separate SVEL/STB/ACK signals for CPU1 and CPU2, so the PC can talk to each
PIC separately; four 16-bit vels to CPU1 (A-D), and four 16-bit vels to CPU2 (E-H).

HANDSHAKE OVERVIEW
------------------
The following steps are the same for CPU1 and CPU2, depending on which control signals
are used (CPU1's or CPU2's). We use CPU1 (chans A-D) in this example:

    1. Before sending the four 16 bit velocities for channels A-D, "SVEL" (Start Vels)
       is strobed from the IBM PC telling the PIC we're about to send four new 16 bit velocities.
       The PC waits for an ACK from the PIC indicating it received the SVEL.

              outp(0x037a, 0x04);                       // set SVEL bit (START VELOCITIES)
              while ( (inp(0x0379) & 0x40) == 0 ) { }   // wait for ack from PIC firmware (0x40 is ack bit)
              outp(0x037a, 0x00);                       // clear SVEL bit (START VELOCITIES)

    2. The PC then loads the LSB of channel A on the data bus (8255 port A), and then
       strobes the data (raises STB).

    3. The PC waits for an ACK from the PIC indicating it buffered the LSB.
       On receipt the PC lowers STB, and waits for ACK to go low.

    4. The PC then loads the MSB of channel A on the data bus (8255 port A), and then
       strobes the data (raises STB).

    5. The PC waits for an ACK from the PIC indicating it buffered the MSB.
       On receipt the PC lowers STB, and waits for ACK to go low.

       The above steps 2 through 5 might be implemented as:

              short avel = 25;                        // A channel velocity will be 25

              // SEND LSB OF CHANNEL A'S VELOCITY
              while ( (inp(0x0379) & 0x40) ) { }      // wait for PIC to clear any previous ack
              outp(0x0378, avel & 0x0ff);             // put LSB byte of 'avel' on PIC's data bus
              outp(0x037a, 0x01);                     // set STROBE bit to send lower 8 bit vel
              while ( (inp(0x0379) & 0x40 == 0) ) { } // wait for PIC to ack our velocity
              outp(0x037a, 0x00);                     // clear STROBE bit

              // SEND MSB OF CHANNEL A'S VELOCITY
              //     Same code as above, but sending /upper/ 8 bits of 'avel'
              //
              while ( (inp(0x0379) & 0x40) ) { }      // wait for PIC to clear any previous ack
              outp(0x0378, (avel >> 8) & 0x0ff);      // put MSB byte of 'avel' on PIC's data bus
              outp(0x037a, 0x01);                     // set STROBE bit to send lower 8 bit vel
              while ( (inp(0x0379) & 0x40 == 0) ) { } // wait for PIC to ack our velocity
              outp(0x037a, 0x00);                     // clear STROBE bit

    6. Repeat steps 2 through 5 for channels B, C and D.

As described above, this sends 4 vels A,B,C,D to the first PIC chip (CPU1).
Repeat using different ports/bits to send 4 vels E,F,G,H to the second PIC chip (CPU2).

It's important to note that the 8255 I/O chip supports 24 bits of I/O, and is split
into three 8 bit ports: PORT A, PORT B and PORT C.

For the A800, PORT A is used as the common data bus to both PIC chips, used for
passing velocity bytes out to the PICs to set the stepper motor speed for each channel.

For each PIC chip there are separate start, strobe and acknowledge bits which are
used by the IBM PC software to choose which PIC chip is being sent data. Basically:

                 8255    PORT
        CPU      PORT    MASK  DESCRIPTION
        ------   ------  ----  -------------------------------------------------------------
        CPU #1   PORT-A  0xFF  8-bit Data bus (for sending bytes from PC -> PIC#1 and PIC#2)
        CPU #1   PORT-C  0x40  "SVEL strobe" bit (for sending 'start', PC -> PIC#1)
        CPU #1   PORT-C  0x10  "data strobe" bit (for sending vels, PC -> PIC#1)
        CPU #1   PORT-B  0x01  PIC #1 Acknowledge bit, PIC#1 -> PC.
        ------   ------  ----  -------------------------------------------------------------
        CPU #2   PORT-A  0xFF  8-bit Data bus (for sending bytes from PC -> PIC#2 and PIC#1)
        CPU #2   PORT-C  0x04  "SVEL strobe" bit (for sending 'start', PC -> PIC#2)
        CPU #2   PORT-C  0x01  "data strobe" bit (for sending vels, PC -> PIC#2)
        CPU #2   PORT-B  0x02  PIC #2 Acknowledge bit, PIC#2 -> PC.
