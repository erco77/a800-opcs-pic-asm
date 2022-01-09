SENDING VELOCITIES FROM THE IBM PC TO THE A800 BOARD
----------------------------------------------------

The timing diagram on the back of the A800 board shows the handshake control signals
between the IBM PC and PIC chips (via the 8255) used to send velocities to the A800 board.
(This same diagram is on SHEET 4 of the A800 board's schematics)

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

    2. The PC then loads the LSB of channel A on the data bus (8255 port A), and then
         strobes the data (raises STB).

    3. The PC waits for an ACK from the PIC indicating it buffered the LSB.
         On receipt the PC lowers STB, and waits for ACK to go low.

    4. The PC then loads the MSB of channel A on the data bus (8255 port A), and then
         strobes the data (raises STB).

    5. The PC waits for an ACK from the PIC indicating it buffered the MSB.
         On receipt the PC lowers STB, and waits for ACK to go low.

    6. Repeat steps 2 through 5 for channels B, C and D.

