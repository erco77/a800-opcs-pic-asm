------------------------------------------------------------------------------------
This is a copy/paste from the comments in a800-opcs-asm.asm
which documents how the software operates the I/O pins.
------------------------------------------------------------------------------------

;;
;; PIC CHIP PIN ASSIGNMENTS
;; ------------------------
;;                         CPU1                               #                     CPU2
;;  PIN#                  _    _                         PIN# # PIN#               _    _                       PIN#
;;   1    RES (VPP) MCLR | |__| | RB7 ->(ICSPDAT) D-Dir   28  #  1      " "  MCLR | |__| | RB7 (ICSPDAT) H-Dir   28
;;   2   STB_8255-> RA0  |      | RB6 ->(ICSPCLK) D-Step  27  #  2      " "  RA0  |      | RB6 (ICSPCLK) H-Step  27
;;   3   <-ACK_8255 RA1  |      | RB5 ->C-Dir             26  #  3      " "  RA1  |      | RB5 G-Dir             26
;;   4  SVEL_8255-> RA2  |      | RB4 ->C-Step            25  #  4      " "  RA2  |      | RB4 G-Step            25
;;   5   CPUID_+5-> RA3  |      | RB3 ->B-Dir             24  #  5 CPUID_GND RA3  |      | RB3 F-Dir             24
;;   6  <-IRQ_IBMPC RA4  |      | RB2 ->B-Step            23  #  6      " "  RA4  |      | RB2 F-Step            23
;;   7  <-CPU1 SYNC RA5  |      | RB1 ->A-Dir             22  #  7      " "  RA5  |      | RB1 E-Dir             22
;;   8        (VSS) GND  |      | RB0 ->A-Step            21  #  8      " "  GND  |      | RB0 E-Step            21
;;   9  16MHz Clk-> RA7  |      | +5  (VDD)               20  #  9      " "  RA7  |      | +5     "    "         20
;;   10  CPU1 Ack-> RA6  |      | GND (VSS)               19  #  10     " "  RA6  |      | GND    "    "         19
;;   11     Data0-> RC0  |      | RC7 <-Data7             18  #  11     " "  RC0  |      | RC7    "    "         18
;;   12     Data1-> RC1  |      | RC6 <-Data6             17  #  12     " "  RC1  |      | RC6    "    "         17
;;   13     Data2-> RC2  |      | RC5 <-Data5             16  #  13     " "  RC2  |      | RC5    "    "         16
;;   14     Data3-> RC3  |______| RC4 <-Data4             15  #  14     " "  RC3  |______| RC4    "    "         15
;;                                                            #
;;                      PIC18F24Q10                           #                 PIC18F24Q10
;;
;; NOTE: In "REV-0", RA3 was unused (labeled "SMOT").
;;       In "REV-A" (and up), RA3 is now the CPU_ID, where the input value is:
;;         Logic 1 (+5V) if CPU #1
;;	       Logic 0 (GND) if CPU #2
;;       This bit is used by CpuSync() to autodetect which CPU we're running on.
;;       Previously (in REV-0), we had to build separate binaries for CPU1+2.
;;
;; SIGNAL MAPPING BETWEEN PC <-> 8255 <-> PIC
;; ------------------------------------------
;;
;;     IBMPC        --8255--       --PIC---
;;     PORT:MASK    PORT:BIT       PORT:BIT(CPU) SIGNAL NAME
;;     ---------    ---------      ------------- -------------
;;      0300:ff  -> PORTA:0-7  ->  RC0-7(CPU1+2) DATA
;;      0301:01  <- PORTB:0    <-  RA1  (CPU1)   ACK CPU1
;;      0301:02  <- PORTB:1    <-  RA1  (CPU2)   ACK CPU2
;;      0301:fc  <- PORTB:2-7  <-  unused
;;      0302:01  -> PORTC:0    ->  RA0  (CPU2)   STROBE CPU2
;;      0302:02  -> PORTC:1    ->  unused        -
;;      0302:04  -> PORTC:2    ->  RA2  (CPU2)   SVEL CPU2
;;      0302:08  -> PORTC:3    ->  unused        -
;;      0302:10  -> PORTC:4    ->  RA0  (CPU1)   STROBE CPU1
;;      0302:20  -> PORTC:5    ->  unused        -
;;      0302:40  -> PORTC:6    ->  RA2  (CPU1)   SVEL CPU1
;;      0302:80  -> PORTC:7    ->  unused        -
;;
;; 8255 PIN ASSIGNMENTS
;; --------------------
;;
;;     --8255--
;;     PORT:BIT   I/O  DESCRIPTION
;;     ========== ==== ===============================
;;     PORT A     OUT  8 bit data bus, 8255 -> CPU1+2
;;     -----------------------------------------------
;;     PORT B:0   IN   CPU0 ACK
;;     PORT B:1   IN   CPU1 ACK
;;     PORT B:2-7 IN   unused
;;     -----------------------------------------------
;;     PORT C:0   OUT  CPU2 STROBE
;;     PORT C:1   OUT  unused
;;     PORT C:2   OUT  CPU2 START VEL
;;     PORT C:3   OUT  unused
;;     PORT C:0   OUT  CPU1 STROBE
;;     PORT C:1   OUT  unused
;;     PORT C:2   OUT  CPU1 START VEL
;;     PORT C:3   OUT  unused
;;
;; PICKIT 4 PROGRAMMER 5-PIN CONNECTOR
;; -----------------------------------
;;
;;     PICKIT PIC  PIC
;;     PIN#   PIN# SIGNAL
;;     ------ ---- ------
;;     1      1    MCLR
;;     2      20   +5 (VDD)
;;     3      19   GND
;;     4      28   ICSP_DAT
;;     5      27   ICSP_CLK
;;     Do not connect other pins past 5
