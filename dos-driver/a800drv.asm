; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4
title A800DRV - Terminate/Stay Resident driver for A800 card

; Greg Ercolano (C) 2020. All rights reserved.

; VERS  DATE     AUTHOR          NOTES
; ----  -------- --------------- -----------------------------------------
; 0.99  03/23/20 erco@seriss.com Copied rtmc48.asm, created a800drv.asm, start dev
; 1.00  03/26/20 erco@seriss.com First version working w/OPCS
; 1.10  05/02/20 erco@seriss.com Use a800_struct.BaseAddr for all port I/O
; 1.20  05/04/20 erco@seriss.com Disable timer ints during motor runs
;

; TODO: Should probably make IRQ# selectable from OPCS.
;       Currently code is hardwired to use INT 0dh only:
;       8259 bit, int vector table address, etc.
;
; NOTES:
;       The A800 board can manage 8 motor channels.
;       It has two CPUs; CPU1 for channels ABCD, CPU2 for EFGH.
;
;       Velocities are strobed to the board using the 8255's
;       8 bit register (PORT A) and for each cpu, 3 bits each
;       to bit bang strobe/ack/'start vels' signals.
;
; ALLSTOP BIT
; -----------
;       Keep in mind that only the A channel is checked for ALLSTOPBIT and
;       the STOPBIT. So you better make sure the A channel velocity has
;       the bit set, regardless of whether the A chan is moving or not.
;
;       A sample frame of velocities will get sent first, updating counters as
;       perscribed, and will THEN be checked for the ALLSTOP bit.
;       This ensures the velocities get sent, and counters update
;       correctly.
;
; INTERRUPT DRIVEN VELS: HEAD VS TAIL
; -----------------------------------
;       C program sets Head and Tail to 0000, then loads vels into 
;       A800_Head pointer, advancing it.
;
;       When ints are enabled, this driver pulls vels from A800_Tail,
;       advancing it. When we catch up to the Head, we stop.
;
;       When the C program's Head is about to catch up to the Tail, 
;       it first waits until the device driver pulls vels from Tail
;       before adding new vels and advancing the Head.
;       
; INTERRUPT DRIVEN VELS: BE READY WITH DATA
; -----------------------------------------
;       When the interrupts are started, they IMMEDIATLY start feeding
;       velocities from the arrays. That means some values better be there
;       already! So buffer a few values, THEN start the interrupt routine
;       going. And once the ints are running, you better keep ahead of it!
;
;       If you get so far ahead you wrap the entire 64K buffer, take care
;       to wait for the buffer to clear a little before jamming in new
;       values, or you'll overwrite values the ints haven't even fed
;       to the motors yet.
;

a800struc       struc
  A800_RingBuffer   dw 0,0      ;(far)    pointer to 64k ring buffer
  A800_Counter      dw 0,0      ;(far)    pointer to counter array
  A800_BaseAddr     dw 0        ;(ushort) base addr of a800 card (300h default)
  A800_Head         dw 0        ;(ushort) c program's leading pointer
  A800_Tail         dw 0        ;(ushort) hardware following pointer
  A800_Stopped      dw 0        ;(ushort) flags that int routine stopped
  A800_SyncFault    dw 0        ;(ushort) flags a sync error occurred
  A800_AllStop      dw 0        ;(ushort) flag to do an allstop
  A800_CountType    dw 0        ;(ushort) Type of counter update
  A800_ASAddr       dw 0        ;(ushort) address of vels for rampdown
a800struc       ends            ;         (set ASAddr first, then Allstop)

STOPBIT         equ 8000h       ;This bit in a velocity indicates
                                ;this is the last velocity in the ring.
ALLSTOPBIT      equ 4000h       ;This bit indicates 'check for allstop'
                                ;address in A800_AllStop for a rampdown.
SOFTREVBIT      equ 2000h       ;This bit tells the software counters
                                ;to count in reverse, regardless of
                                ;hardware bit (due to direction inverts)
FULLROTBIT      equ 1000h       ;This bit tells the driver to make a
                                ;count when using the ROTATION counter
                                ;update type. This bit should appear in
                                ;the last velocity of a full rotation.
DIRBIT          equ 0800h       ;Motor direction bit
HARDMASK        equ 08ffh       ;Leave hardware bits behind (dirbit + lo 8 bits)
COUNTMASK       equ 00ffh       ;Leave countable vel behind (lo 8 bits)

NOCOUNTTYPE     equ 0           ; no counter updating
STEPCOUNTTYPE   equ 1           ; counters count in steps
ROTCOUNTTYPE    equ 2           ; counters count in rotations (PPR)

;
; A800 ADDRESS OFFSETS
;   The A800 board uses an 8255 to manage all communications, which has three
;   8 bit ports (PORT A=BASE+0, B=BASE+1, C=BASE+2), and a control port (BASE+3).
;
BASE            equ 0300h
PORT_A          equ BASE+0
PORT_B          equ BASE+1
PORT_C          equ BASE+2
CTRL_8255       equ BASE+3

;
; 8255 RELATED COMMUNICATION EQUATES
;

; ACK handshake signal from a cpu
ack_bit_cpu1            equ 01h         ; 8255 PORT B0
ack_bit_cpu2            equ 02h         ; 8255 PORT B1

; STROBE data to a cpu
strobe_bit_cpu1         equ 10h         ; 8255 PORT C4
strobe_bit_cpu2         equ 01h         ; 8255 PORT C0

; SVEL handshake signal to a cpu
start_bit_cpu1          equ 40h         ; 8255 PORT C6
start_bit_cpu2          equ 04h         ; 8255 PORT C2

A800_8259_BIT           equ 20h         ; 8259 IRQ5: set=ints off, clr=ints on
KEYBOARD_BIT            equ 02h         ; (2 is to disable keyboard ints)
A800_CHANS              equ 8d          ; number of hardware channels A800 supports

;;;
;;; MACROS
;;;

jtrue           macro addr
                jnz addr
                endm

jfalse          macro addr
                jz addr
                endm

; OUTPUT A BYTE
;     usage:
;           output port,value
;     'port' can either be a register, fixed byte, memory location, equate, etc.
;     'value' can be al, ah, a fixed byte value, location, equate, etc.
;     This macro ensures no registers are modified.
;
output          macro port,value
                push ax
                push dx
                  mov dx,port
                  mov al,value
                  out dx,al
                pop dx
                pop ax
                endm

; READ BYTE FROM PORT INTO 'AL' REGISTER.
; usage:
;           inp_al port         ; reads 8 bit 'port', result into AL reg.
;     'port' can either be a register, fixed byte, memory location, equate, etc.
;     This macro ensures no other registers are modified.
;
inp_al          macro port
                push dx
                  mov dx,port
                  in al,dx
                pop dx
                endm

; DOS: PRINT A MESSAGE
;    Handles crlf and end of string. Usage:
;    print "Hello world."
;
print           macro msg
                local msgtext,skipmsg,print_loop,print_done
                jmp skipmsg
msgtext         db msg,0dh,0ah,'$'
skipmsg:        push ax
                push bx
                push cx
                push dx
                push si
                push di
                push ds
                  mov si,offset cs:msgtext
                  mov ax,cs
                  mov ds,ax
print_loop:
                  mov ah,0eh            ; BIOS VIDEO TELETYPE PRINT
                  mov al,[si]           ; al=char
                  cmp al,24h            ; '$'? (DOS style  EOS)
                  je print_done
                  cmp al,0              ; NUL? (nul terminated string)
                  je print_done
                  mov bx,0007h          ; bh=page, bl=fgcolor
                  int 10h
                  add si,1
                  jmp print_loop
print_done:
                pop ds
                pop di
                pop si
                pop dx
                pop cx
                pop bx
                pop ax
                endm

;
; ASSEMBLER HEADER
;
cseg    segment para
        assume cs:cseg, ds:cseg, es:cseg, ss:cseg
        org 0100h                       ;COM format

        jmp setup

; A800's 8255 PORTS
;
;     These are variables since the base address is configurable
;     by the jumpers on the A800, and the A800_struct.BaseAddr,
;     which must match.
;
;     'call set_ports' to initialize these variables based on
;     incase BaseAddr was changed.
;
data_port       dw 0    ; BASE+0 - PORT_A    - OUT: all 8 bits for data to PIC
ack_port        dw 0    ; BASE+1 - PORT_B    - IN:  cpu1(01h) cpu2(02h)
strobe_port     dw 0    ; BASE+2 - PORT_C    - OUT: cpu1(10h) cpu2(01h)
start_port      dw 0    ; BASE+2 - PORT_C    - OUT: cpu1(40h) cpu2(04h)
ctrl_port       dw 0    ; BASE+3 - CTRL_PORT - set to 82h for PORT A/C out, B in

;
; INTERRUPT ROUTINE REGISTER SAVE AREA
;
SAX_99          dw 0
SBX_99          dw 0
SCX_99          dw 0
SDX_99          dw 0
SSI_99          dw 0
SDI_99          dw 0
SBP_99          dw 0
SDS_99          dw 0
SES_99          dw 0
INT_99_RUNNING  db 0

;
; INT 99 DISPATCHER
;    This is how external applications (e.g. OPCS) talk to this driver
;    via INT 99. To see the various operations this interrupt provides,
;    see the 'funtab' (function table) below for the list and AH codes,
;    and see each function's code header comment for usage.
;
int_99:
        sti

        test cs:INT_99_RUNNING,1        ;are we running already?
        jfalse int_99_xrun

        mov si,offset cs:recursion_err  ;screen string is the first array in
        mov ax,cs                       ;the global environment
        mov ds,ax
        mov di,0

        push si
        push di
          mov ax,0b000h
          mov es,ax
          call slap_screen
        pop di
        pop si
        mov ax,0b800h
        mov es,ax
        call slap_screen

        mov si,offset cs:recursion_err  ;screen string is the first array in
        mov ax,cs                       ;the global environment
        mov ds,ax
        mov di,0
        push si
        push di
          mov ax,0b000h
          mov es,ax
          call slap_screen
        pop di
        pop si
        mov ax,0b800h
        mov es,ax
        call slap_screen

halt_sys:       jmp halt_sys

int_99_xrun:
        mov cs:INT_99_RUNNING,1         ;flag we're running (avoid recursion)

        mov cs:SAX_99,ax                ;save all regs w/out wasting stack
        mov cs:SBX_99,bx
        mov cs:SCX_99,cx
        mov cs:SDX_99,dx
        mov cs:SSI_99,si
        mov cs:SDI_99,di
;       mov cs:SBP_99,bp
        mov cs:SDS_99,ds

        mov     al,ah
        xor     ah,ah
        rol     al,1                    ;offset into table
        mov     di,offset cs:funtab
        add     di,ax
        push    cs
        pop     ds
        jmp     word ptr [di]           ;branch to the function

funtab          dw      int99_set_a800_struct   ;0d
                dw      int99_start_a800        ;1d
                dw      int99_stop_a800         ;2d (currently NOP)
                dw      int99_wait_a800         ;3d (currently NOP)
                dw      int99_dummy             ;4d
                dw      int99_dummy             ;5d
                dw      int99_dummy             ;6d
                dw      int99_dummy             ;7d
                dw      int99_dummy             ;8d
                dw      int99_dummy             ;9d
                dw      int99_get_env_ptr       ;10d
                dw      int99_display_screen    ;11d
                dw      int99_scroll_height     ;12d
                dw      int99_dummy             ;13d was a (broken?) cswait
                dw      int99_dummy             ;14d
                dw      int99_dummy             ;15d
                dw      int99_dummy             ;16d

int_99_done:
        mov ax,cs:SAX_99                ;save all regs w/out wasting stack
        mov bx,cs:SBX_99

int_99_retval:
        mov cx,cs:SCX_99
        mov dx,cs:SDX_99
        mov si,cs:SSI_99
        mov di,cs:SDI_99
;       mov bp,cs:SBP_99
        mov ds,cs:SDS_99
        mov es,cs:SES_99
        mov cs:INT_99_RUNNING,0         ;not running anymore.

ignore_99:
        iret

;
; INT99 Dummy handler (NOP)
;
int99_dummy:    jmp int_99_done

; INT 99 - AH=0
;     BX = offset  (LSW) of ptr to kuper structure
;     CX = segment (MSW) of ptr to kuper structure
;
int99_set_a800_struct:
        mov cs:[a800_struct+0],bx       ; offset
        mov cs:[a800_struct+2],cx       ; segment
        jmp int_99_done

; INT 99 - AH=1
;
; Enable the kuper interrupt driver to start feeding velocities
; from the ring buffer.
;
int99_start_a800:
        mov bx,cs:[a800_struct+0]
        mov ds,cs:[a800_struct+2]
        call set_ports          ; Applies BaseAddr -> port variables

        call set_counter_type
        mov word ptr ds:[bx].A800_Stopped,0
        mov word ptr ds:[bx].A800_SyncFault,0

        ;;; A800 INIT ;;;

        ; Program 8255 I/O
        output cs:[ctrl_port], 82h      ; PORT A+C output, PORT B input
        output cs:[data_port], 0        ; zero data bus
        output cs:[strobe_port], 0      ; disable start+strobe

        ;; COMMENTED OUT - IS NOT SYNCHRONIZED WITH IRQ5,
        ;; SO DONT DO IT.
        ;;
        ;; ; Send zero vels for all channels
        ;; call hardstop                 ; send zero vels to all channels

        ; Enable interrupts
        call setup_8259_ints            ; enable IRQ5 interrupts

        ; Return to caller with ints running in background
        jmp int_99_done

; INT 99 - AH=2
int99_stop_a800:
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=3
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_wait_a800:
        jmp int_99_retval

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=10d (0ah)
;     Returns a pointer to the global 'environment'
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_get_env_ptr:
        mov ax,cs
        mov bx,offset cs:environment
        jmp int_99_retval

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=11d
;     The screen array is a NULL terminated string that can wrap around
;     the screen up to 6 times. Embedded special bytes in the screen array
;     can switch text attributes (like an escape character):
;       0 - NUL, terminates the string
;       1 - enables 'NORMAL' text (see atr_tab)
;       2 - enables 'BRIGHT' text (see atr_tab)
;       3 - enables 'FLASH' text (see atr_tab)
;       4 - enables 'INVERSE' text (see atr_tab)
;       5 - enables 'FLASHINVERSE' text (see atr_tab)
;       6 - enables 'HIDE' text (see atr_tab)
;     Appearence of these characters enable the modes. NO MIXED MODES.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_display_screen:
        mov si,offset cs:environment    ;screen string is the first array in
        mov ax,cs                       ;the global environment
        mov ds,ax

        mov di,0
        mov ax,0b000h
        mov es,ax
        call slap_screen

        mov si,offset cs:environment
        mov ax,cs
        mov ds,ax

        mov di,0
        mov ax,0b800h
        mov es,ax
        call slap_screen

        jmp int_99_done


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=12d
;    Sets screen scroll height to value in AL
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_scroll_height:
        mov ax,cs:SAX_99
        mov cs:[scrollheight],al
        jmp int_99_done
scrollheight    db 3

NULL            equ     00              ;never used
NORMAL          equ     07h             ;1
BRIGHT          equ     0fh             ;2
FLASH           equ     087h            ;3
INVERSE         equ     70h             ;4
FLASHINVERSE    equ     0f0h            ;5
HIDE            equ     00h             ;6

;
; Table of screen attributes
;
;                   0      1       2      3        4          5         6
atr_tab         db NULL, NORMAL, BRIGHT, FLASH, INVERSE, FLASHINVERSE, HIDE

;
; SLAP A NUL TERMINATED STRING DIRECTLY TO THE SCREEN
;    This does a direct memory transfer from ds:si -> es:di, stopping
;    at the NUL terminator.
;
;    Expects DS:SI to point to source NUL terminated string
;    Expects ES:DI to point to destination screen memory (e.g. b800:0000)
;
;    The special characters 0 thru 6 are handled specially:
;
;       0 - NUL, terminates the string
;       1 - enables 'NORMAL' text (see atr_tab)
;       2 - enables 'BRIGHT' text (see atr_tab)
;       3 - enables 'FLASH' text (see atr_tab)
;       4 - enables 'INVERSE' text (see atr_tab)
;       5 - enables 'FLASHINVERSE' text (see atr_tab)
;       6 - enables 'HIDE' text (see atr_tab)
;
slap_screen:
          mov ah,NORMAL       ; ah will be attribute (until changed by codes 1-6)
ss_loop:
          mov al,ds:[si]      ; read each char from source string
          cmp al,0            ; NUL? done
          je ss_done
          cmp al,7            ; attribute change codes are <7
          jnc ss_text         ; jge than 7? continue text..
          push si             ; less than 7? Use screen attribute from atr_tab
            mov si,offset cs:atr_tab
            xor ah,ah
            add si,ax         ; use char as index into atr_tab
            mov ah,cs:[si]
          pop si
          jmp ss_atr
ss_text:  mov es:[di],al      ; write char to screen
          inc di
          mov es:[di],ah      ; write attribute to screen
          inc di
ss_atr:   inc si                        
          jmp ss_loop
ss_done:  ret

;
; The following intercepts the BIOS keyboard interrupt service...
; If no keys await in keyboard buffer, the screen display is updated before
; calling the keyboard BIOS.
;
kb_int:
        push ax
        push ds
            mov ax,0040h                ;keyboard buffer area
            mov ds,ax
            mov al,ds:[006ch]           ;timer count (18 / sec)
            and al,0f8h
            cmp al,cs:[lastcount]       ;dont update faster than half a second
            mov cs:[lastcount],al
            je nodisp

            mov al,ds:[0017h]           ;shift key states
            and al,10h                  ;SCROLL LOCK?
            jz nodisp                   ;if scroll lock not enabled, forget it

            mov ah,11d                  ;redisplay screen (saves regs)
            int 99h

nodisp:   pop ds
          pop ax

          db 0eah                       ;jmp far
KB_BIOS   dw 0,0

lastcount db 0

;
; The following intercepts the BIOS video service.
; Handles scrolling to make sure counters don't scroll off screen.
;
vid_int:
        cmp ah,6                        ;scrollup?
        je scrollup
        cmp ah,0eh                      ;print teletype?
        je teletype

to_vid_bios:
                db 0eah                 ;jmp far
VID_BIOS        dw 0,0                  ;far address to jump to

teletype:
        cmp al,0ah              ;linefeed?
        jne to_vid_bios

        push ds
        push ax
            mov ax,0040h
            mov ds,ax
            mov al,ds:[0017h]   ;shift key states
            and al,10h          ;SCROLL LOCK?
        pop ax
        pop ds
        jz to_vid_bios          ;if scroll lock not enabled, forget it

        push ds
          mov ax,0040h
          mov ds,ax
          mov al,[0051h]        ;get vertical cursor position from BIOS
        pop ds
        cmp al,24d              ;bottom of screen?
        jle te_xbott            ;no, then just print the linefeed

        push bx
         push cx
          push dx
            mov ax,0601h        ;scroll up one line
            mov cl,0
            mov ch,cs:[scrollheight]
            mov bx,0707h
            mov dx,184fh
            int 10h
          pop dx
         pop cx
        pop bx
        mov ax,0e0ah
        iret

te_xbott:
        mov ax,0e0ah
        jmp to_vid_bios

scrollup:
        push ds
        push ax
            mov ax,0040h
            mov ds,ax
            mov al,ds:[0017h]   ;shift key states
            and al,10h          ;SCROLL LOCK?
        pop ax
        pop ds
        jz to_vid_bios          ;if scroll lock not enabled, forget it

        cmp ch,1                ;scroll screen check (top line)
        jg to_vid_bios
        cmp dh,22               ;scroll screen check (bottom line)
        jl to_vid_bios
        mov ch,cs:[scrollheight]        ;HACK!!! Should probably return
                                        ;original value after scrolling?
        jmp to_vid_bios

;       cmp ch,0
;       jne to_vid_bios
;       mov ch,cs:[scrollheight];HACK! Probably should return with
;                               ;original value!
;       jmp to_vid_bios

;;;                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; A800 ROUTINES   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;;;                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

a800_struct             dw 0,0  ; long pointer to a800 structure

old_clock_vec_lo        dw 0    ; old vectors for interrupt 0x0d
old_clock_vec_hi        dw 0
old_8259_flags          dw 0

;;
;; 8255 COMMUNICATION ROUTINES
;;

;
; SEND "START VELOCITIES" TO A800
;     This tells A800's two CPUS we're about to send new set of motor vels
;     in answer to IRQs from the A800 board. This resets each CPU's internal
;     communication state machine.
;
send_start_a800:
        push ax
          ; CPU1
          output   cs:[start_port], (start_bit_cpu1+strobe_bit_cpu1)
          call     wait_ack_cpu1        ; wait for ack from PIC
          output   cs:[start_port], 0   ; start+strobe "off"
          call     wait_unack_cpu1      ; wait for ack to clear
          ; CPU2
          output   cs:[start_port], (start_bit_cpu2+strobe_bit_cpu2)
          call     wait_ack_cpu2        ; wait for ack from PIC
          output   cs:[start_port], 0   ; start+strobe "off"
          call     wait_unack_cpu2      ; wait for ack to clear
        pop ax
        ret

;
; Separate functions to send a single byte to CPU1 / CPU2.
;     Load data, strobe, wait for ack, drop strobe.
;
send_byte_cpu1:
        call   wait_unack_cpu1     ; wait for PIC to drop ack before send
        output cs:[data_port],al   ; put byte on data bus
        call   strobe_cpu1
        call   wait_ack_cpu1       ; wait for ack from PIC
        call   unstrobe_cpu1
        ret

send_byte_cpu2:
        call   wait_unack_cpu2     ; wait for PIC to drop ack before send
        output cs:[data_port],al   ; put byte on data bus
        call   strobe_cpu2
        call   wait_ack_cpu2       ; wait for ack from PIC
        call   unstrobe_cpu2
        ret

;
; Send 16 bit velocity to PIC in AX to A800 card.
;
;    AX=RTMC16 style velocity (0800=direction bit, 07ff are vel bits)
;    DL=channel # (A=0, B=1, .. H=7)
;
;    Handles translating RTMC16 style bits to A800 (8000=dir, 00ff=vel),
;    clipping vels above ff to be ff.
;    It is up to the caller to send "START" before sending any vels.
;
;    ALSO HANDLES TRANSLATING DIRECTION BIT (from 0800h -> 8000h)
;
;    OPCS uses RTMC16 bit layout:     But A800 hardware wants:
;    (This is what's in ring buffer)  (This is what we must send to A800 cpus)
;
;         ---MSB--- ---LSB---         ---MSB--- ---LSB---
;         xxxx 1000 0000 0000         1xxx xxxx 0000 0000
;         |__| ||___________|         ||______| |_______|
;         soft |  11 vel bits         | unused  8 vel bits
;         bits |                      |
;              Dir bit (bit 12)       Dir bit (bit 15)
;
;    ..so we handle this bit translation here.
;
send_vel:
        push ax                 ; save unmodified ax for later
          ; Assume AX is an RTMC16 velocity; 0800 is direction, 07ff is vel

          ; CONVERT DIRECTION BIT FIRST
          and  ax, 0fffh        ; mask off software bits, leaving 12 hardware bits
          test ax, 0800h        ; check for RTMC16 dir bit
          jfalse sv_xrev        ; no, skip
          and ax, 07ffh         ; yes, remove 800h bit, keep rest
          or  ax, 8000h         ; move dir bit from 800h -> 8000h
sv_xrev:
          ; HANDLE CLIPPING
          ;    Make sure any vel 0100h thru 07ffh is clipped to 00ffh
          ;
          push ax               ; save vel with converted dir bit
            and ax, 7fffh       ; ignore dir bit, see if 11 bit vel above ffh
            cmp ax, 00ffh       ; vel greater than 00ffh?
          pop ax
          jle sv_noclip         ; less or equal? no clip
          ; clip to either 80ff or 00ff
          and ah, 80h           ; greater? mask msb, keeping only dir bit
          mov al, 0ffh          ; force lsb to ffh
sv_noclip:
          ; Send xlated vel to either CPU1 (if A-D) or CPU2 (if E-H)
          cmp dl,4                ; E channel?
          jl  send_vel_cpu1       ; less, use CPU1
          jmp send_vel_cpu2       ; else, use CPU2

; SEND AN A800 VELOCITY TO SPECIFIC A800 PROCESSOR (CPU1 OR CPU2)
;    Handles sending both lsb and msb.
;    Assumes vels are in A800 format: 8000h is direction, 00ffh is vel.
;    Strobes each of the bytes to the PIC, waits for ACK/UNACK,
;    returns with strobe disabled so next vel can be sent.
;
;    It is up to the caller to send "START" before sending any vels.
;
send_vel_cpu1:
          ; Send LSB and MSB (in AX currently) to PIC
          call send_byte_cpu1   ; send lsb to PIC
          xchg al,ah            ; exchange to send msb
          call send_byte_cpu1   ; send msb to PIC
        pop ax                  ; restore 16bit vel we were called with
        ret

send_vel_cpu2:
          ; Send LSB and MSB (in AX currently) to PIC
          call send_byte_cpu2   ; send lsb to PIC
          xchg al,ah            ; exchange to send msb
          call send_byte_cpu2   ; send msb to PIC
        pop ax                  ; restore 16bit vel we were called with
        ret

;
; Strobe the PIC to receive data (or a "start" signal)
;
strobe_cpu1:
        output  cs:[strobe_port], strobe_bit_cpu1
        ret

strobe_cpu2:
        output  cs:[strobe_port], strobe_bit_cpu2
        ret

;
; Un-strobe the PIC chip.
;     No wait loop, just forces strobe disabled and returns.
;
unstrobe_cpu1:
        output  cs:[strobe_port], 0
        ret

unstrobe_cpu2:
        output  cs:[strobe_port], 0
        ret

;
; Wait for ACK from PIC chip to go high
;
wait_ack_cpu1:
        push ax
wait_ack_cpu1_loop:
          inp_al cs:[ack_port]          ; read port to check ACK bit
          test   al, ack_bit_cpu1
          jz     wait_ack_cpu1_loop     ; wait until ack set
        pop ax
        ret

wait_ack_cpu2:
        push ax
wait_ack_cpu2_loop:
          inp_al cs:[ack_port]          ; read port to check ACK bit
          test   al, ack_bit_cpu2
          jz     wait_ack_cpu2_loop     ; wait until ack set
        pop ax
        ret

;
; Wait for ACK from PIC to go low
;
wait_unack_cpu1:
        push ax
wait_unack_cpu1_loop:
          inp_al cs:[ack_port]
          test   al, ack_bit_cpu1
          jnz    wait_unack_cpu1_loop   ; wait until ack clear
        pop ax
        ret

wait_unack_cpu2:
        push ax
wait_unack_cpu2_loop:
          inp_al cs:[ack_port]
          test   al, ack_bit_cpu2
          jnz    wait_unack_cpu2_loop   ; wait until ack clear
        pop ax
        ret

;
; SEND ZERO VELOCITY TO ALL CHANNELS
;    This stops all motors from running on the next IRQ timer tick.
;
hardstop:
        ; Send zero velocity to all motors
        ;     Send 0 vel for all channels
        ;
        mov ax,00               ; send zero to all channels
        ;
        call send_start_a800    ; start sending 4 chans of vels to A800
        call send_vel_cpu1      ; A
        call send_vel_cpu1      ; B
        call send_vel_cpu1      ; C
        call send_vel_cpu1      ; D
        ;
        call send_vel_cpu2      ; E
        call send_vel_cpu2      ; F
        call send_vel_cpu2      ; G
        call send_vel_cpu2      ; H
        ret

; Read a800_struct.BaseAddr and sets port variables
;
; INPUT:
;     Assumes DS:BX points to a800_struct.
;
;     Call this whenever the main application might have
;     changed BaseAddr.
;
set_ports:
        push dx
          mov  dx,ds:[bx].A800_BaseAddr
          mov  cs:[data_port],dx        ; PORT_A (BASE+0)
          inc  dx
          mov  cs:[ack_port],dx         ; PORT_B (BASE+1)
          inc  dx
          mov  cs:[strobe_port],dx      ; PORT_C (BASE+2)
          mov  cs:[start_port],dx       ; PORT_C (BASE+2) - same as above
          inc  dx
          mov  cs:[ctrl_port],dx        ; CTRL_PORT (BASE+3)
        pop dx
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; This routine gets serviced every time the A800 card is ready for new
; velocities, which is around 50 times a second.
;
; It feeds the 64K ring buffer to the motors until the head and
; tail pointers match each other, indicating the hardware has caught up
; with the head of the array.
;
; The C program must be supplying velocities faster than the hardware
; can use them, keeping the buffer filled. If it doesnt, a SYNC FAULT
; will occur, indicating the C program was not keeping up.
;
; WARNING!!!
;     This program assumes an entire segment has been allocated for the
;     ringbuffer, segment alligned. That means xxxx:0000 thru xxxx:ffff.
;     The C compiler's MALLOC() does not return all zeroes for the offset,
;     so use the DOS malloc() call when allocating this buffer.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;

update  dw ?            ; pointer to motor update function

; INTERRUPT SERVICE HANDLER FOR IRQ TICK (IRQ5=INT 0dh)
a800_int:
        cli     ; <-- IMPORTANT: KEEP OTHER INTS (TIMER) OFF UNTIL WE'RE DONE
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push ds
        push es

        ; Load DS:BX with address of a800_struct
        mov bx,cs:[a800_struct+0]
        mov ds,cs:[a800_struct+2]

        ; Load ES:DI with address of motor counter to update
        mov di,ds:[bx].A800_Counter+0
        mov es,ds:[bx].A800_Counter+2

        ; Call the motor update function
        ;    Depending on the current counter type configured in A800_CountType:
        ;
        ;        no_count_update   - just sends vels, no counter updating
        ;        step_count_update - count in step pulses
        ;        rot_count_update  - count in rotations (uses FULLROTBIT)
        ;
        call cs:[update]                ; ** SEND VELS TO A800 **

        ; Get A channel's vel word from ring buffer
        ;    Check if STOPBIT set (to see if motors stopped),
        ;    and check ALLSTOPBIT to see if we need to start a rampdown.
        ;
        push ds
        push si
          mov si,ds:[bx].A800_Tail      ; Send tail of ring buffer to motors
          mov ax,ds:[bx].A800_RingBuffer+2
          mov ds,ax
          mov ax,ds:[si]                ; get A chan RTMC16 vel from ring buf
        pop si
        pop ds

;;      ; See if head and tail are the same, indicating end of buffer.
;;      ; If they're the same, THEN check for STOPBITs in vels.
;;      mov cx,ds:[bx].A800_Tail
;;      cmp cx,ds:[bx].A800_Head        ; Check if those were last velocities?
;;      jne notlast                     ; No, skip..
;;
;;        ; Caught up with head. Check if it was intentional by checking
;;        ; for a hi 'stop' bit in the A channel's velocity
;;      test ax,STOPBIT                 ; Test A chan vel for intentional stop
;;      jtrue lastone

        ; See if STOPBIT set on A channel's vel.
        ; If so, last vels, stop NOW.
        ;
        test ax,STOPBIT                 ; Test A chan vel for intentional stop
        jtrue lastone

        ; If tail caught up with head and not last vels, it's a SYNC FAULT.
        mov cx,ds:[bx].A800_Tail
        cmp cx,ds:[bx].A800_Head        ; Check if those were last velocities?
        jne notlast                     ; No, skip..

        ; SYNC FAULT: Caught up with head before C program expected
        or   ds:[bx].A800_SyncFault,1   ; flag to C program to fault
        call hardstop                   ; STOP ALL MOTORS!

lastone:
        or ds:[bx].A800_Stopped,1       ; Set the STOP flag, indicate we stopped

        ; Back to old 8259 flags so no other int occurs
        mov ax,cs:[old_8259_flags]
        out 21h,al
        call restore_8259_int           ; restore old int pointer
        jmp done_a800_int               ; return from interrupt for last time

        ;
        ; Check for an allstop condition. If so, set A800_Tail to address
        ; in A800_ASAddress to execute allstop when appropriate.
        ;
notlast:
        cmp word ptr ds:[bx].A800_AllStop,1 ; Caller wants us to stop?
        jne notallstop

        test ax,ALLSTOPBIT              ; Is it appropriate to stop?
        jfalse notallstop

;;;; INSTALLED FOR DEBUGGING: TELLS PostMortum() AT WHICH POINT
;;;; WE ACKNOWLEDGED THE ALLSTOP, AND SKIPPED AHEAD TO THE ASAddr...
;;;; (WARNING: THIS MODIFIES THE HIGH 4 BITS OF THE ALREADY TRANSMITTED
;;;;           'a' VELOCITY. DON'T TRY TO INTERROGATE THIS VEL'S BITS FOR
;;;;           DIR/ROT/AS INFO NOW HERE ON!
;;;;
        push ds
          push si
            push ax
              mov si,ds:[bx].A800_Tail
              mov ax,ds:[bx].A800_RingBuffer+2  ;(ring segment)
              mov ds,ax
              or word ptr ds:[si],0f000h        ;flag 'a' chan's velo
            pop ax
          pop si
        pop ds
;;;; END OF DEBUG CODE

        mov ax,ds:[bx].A800_ASAddr              ;ALLSTOP. Load ASA to the tail
        mov ds:[bx].A800_Tail,ax                ;and acknowledge the allstop.
        mov word ptr ds:[bx].A800_AllStop,0
        jmp done_a800_int                       ;(skip past the A800_Tail advance)

notallstop:
        ; Handle advancing Tail to next set of vels
        add ds:[bx].A800_Tail,32d               ;advance tail to next velocities

done_a800_int:
debug:
        mov ax,0b000h                   ;DEBUGGING ONLY
        mov ds,ax
        inc byte ptr ds:[0f00h]

        mov ax,0b800h                   ;DEBUGGING ONLY
        mov ds,ax
        inc byte ptr ds:[0f00h]

        mov al,20h                      ;acknowledge interrupt
        out 20h,al

        pop es
        pop ds
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        iret

;
; 3 VELOCITY UPDATE ROUTINES
;       0 = no_count_update   - No Counter updating at all (phase shifts, etc)
;       1 = step_count_update - Step Counter update (go, etc)
;       2 = rot_count_update  - Rotation Counter update (windoffs, etc)
;
; Entry:
;    [A800_TAIL] - address into ring buffer for next vels set to hardware
;    [A800_HEAD] - address into ring buffer for last vels app put in ring
;    DS:BX       - pointer to a800_struct
;    DX          - Base address for a800 card (e.g. 0300)
;    ES:DI       - address of motor counter
;
no_count_update:  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        push ds
        push cx
        push dx
        push si

          ; Tell CPU1+2 we're about to send new vels
          call send_start_a800          ; start sending 4 chans of vels to A800

          ; Use DL as a channel counter; 0-3 for CPU1, 4-7 for CPU2
          mov dl,0
          mov si,ds:[bx].A800_Tail      ; Send tail of ring buffer to motors
          mov ax,ds:[bx].A800_RingBuffer+2
          mov ds,ax
          mov cx,A800_CHANS             ; #channels A800 actually supports
ncu_chan_loop:
          ;
          ;         RTMC16 Velocity Word        A800 Velocity Word
          ;         ====================        ==================
          ;
          ;         ---MSB--- ---LSB---         ---MSB--- ---LSB---
          ;         xxxx 1000 0000 0000         1xxx xxxx 0000 0000
          ;         |__| ||___________|         ||______| |_______|
          ;         soft |  11 vel bits         | unused  8 vel bits
          ;         bits |                      |
          ;              Dir bit (bit 12)       Dir bit (bit 15)
          ;                 ^
          ;                /|\
          ;                 |________________________
          ;                                          |
          mov  ax,ds:[si]             ; get 16 bit RTMC16 style vel sent from OPCS
          call send_vel               ; Send word to A800; handles RTMC16 -> A800 xlate
          add  si,2                   ; next vel
          inc  dl                     ; next channel
          loop ncu_chan_loop          ; channel loop

        pop si          ; return si unmodified (pointing at A channel vels)
        pop dx
        pop cx
        pop ds
        ret

step_count_update: ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        push ds
        push cx
        push dx
        push si

          ; Tell CPU1+2 we're about to send new vels
          call send_start_a800          ; start sending 4 chans of vels to A800

          ; Use DL as a channel counter; 0-3 for CPU1, 4-7 for CPU2
          mov dl,0
          mov si,ds:[bx].A800_Tail      ; Send tail of ring buffer to motors
          mov ax,ds:[bx].A800_RingBuffer+2
          mov ds,ax
          mov cx,A800_CHANS             ; #channels A800 actually supports (8)
scu_chan_loop:
          push cx
          push dx

            ; Get RTCM16 style vel from OPCS. 'send_vel' handles translating
            ; RTMC16 style vels -> A800 vels (e.g. 0800 dir -> 8000 dir)
            mov  ax,ds:[si]             ; get 16bit vel for this channel
            call send_vel               ; send 16bit vel to A800

            ; Handle step counter
            ;     Use SOFTREVBIT to determine if counting up or down,
            ;     since hardware bit might be opposite direction..
            ;
            test ax,SOFTREVBIT          ; check software counter dir bit
            jfalse scu_fwd
            and ax,COUNTMASK            ; get unsigned countable velocity
            sub word ptr es:[di+0],ax   ; count down: 16bit vel -> 32bit ctr
            sbb word ptr es:[di+2],0
            jmp short scu_rev
scu_fwd:
            and ax,COUNTMASK            ; get unsigned countable velocity
            add word ptr es:[di+0],ax   ; count up: 16bit vel -> 32bit ctr
            adc word ptr es:[di+2],0

scu_nocount:
scu_rev:    add si,2                    ; next index: 16bit velocity
            add di,4                    ; next index: 32bit counter
          pop dx
          pop cx
          inc dl                        ; next channel
          loop scu_chan_loop
        pop si                          ; si back to pointing at channel A
        pop dx
        pop cx
        pop ds
        ret

rot_count_update: ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        push ds
        push cx
        push dx
        push si

          ; Tell CPU1+2 we're about to send new vels
          call send_start_a800          ; start sending 4 chans of vels to A800

          ; Use DL as a channel counter; 0-3 for CPU1, 4-7 for CPU2
          mov dl,0
          mov si,ds:[bx].A800_Tail      ; Send tail of ring buffer to motors
          mov ax,ds:[bx].A800_RingBuffer+2
          mov ds,ax
          mov cx,A800_CHANS             ; #channels A800 actually supports
rcu_chan_loop:
          mov  ax,ds:[si]               ; get RTMC16 style vel sent from OPCS
          call send_vel                 ; Send word to A800; handles RTMC16 -> A800 xlate

          ; Rotation bit set? If so, adjust counter +/-1
          test ax,FULLROTBIT            ; a full rotation?
          jfalse rcu_nocount            ; no, skip counter adjust
          test ax,SOFTREVBIT            ; yes, check dir bit to see if +/-
          jfalse rcu_fwd                ; fwd? jump ahead
          sub word ptr es:[di+0],1      ; rev? decrease rotation counter -1
          sbb word ptr es:[di+2],0
          jmp short rcu_rev
rcu_fwd:  add word ptr es:[di+0],1      ; fwd? advance rotation counter +1
          adc word ptr es:[di+2],0

rcu_nocount:
rcu_rev:  add si,2                      ;next vel (int velocity index)
          add di,4                      ;next ctr (long counter index)
          inc  dl                       ; next channel
          loop rcu_chan_loop            ; do all chans

        pop si          ; si back to pointing at channel A
        pop dx
        pop cx
        pop ds
        ret

;;;
;;; INTERRUPT HANDLER SUBROUTINES
;;;     All assume ds:[bx] points to the kuper structure.
;;;

; SET UP COUNTER UPDATE ROUTINE
;    Set cs:[update] based on value in A800_CountType.
;    Assumes ds:[bx] already points to kuper structure.
;
set_counter_type        proc near
        cmp ds:[bx].A800_CountType,NOCOUNTTYPE
        jne sctxno
        mov ax,offset cs:no_count_update

sctxno: cmp ds:[bx].A800_CountType,ROTCOUNTTYPE
        jne sctxrot
        mov ax,offset cs:rot_count_update

sctxrot:cmp ds:[bx].A800_CountType,STEPCOUNTTYPE
        jne sctxstp
        mov ax,offset cs:step_count_update

sctxstp:mov cs:[update],ax              ;save address of update routine to use
        ret
set_counter_type        endp

; Mask off the 8259's A800 IRQ (int 0d), prevents it generating ints
mask_a800_int           proc near
        in al,21h
        or al,A800_8259_BIT     ;disable a800 IRQ interrupts (int 0dh)
;       or al,KEYBOARD_BIT      ;;;; DONT ASSUME KEYBOARD BIT ON
;       xor al,KEYBOARD_BIT     ;;;; DONT ASSUME KEYBOARD BIT ON ;enable kbd
        out 21h,al
        ret
mask_a800_int           endp

; Unmask 8259's A800 IRQ (int 0d), allowing it to generate ints
unmask_a800_int proc near
        in  al,21h
        or  al,A800_8259_BIT
        xor al,A800_8259_BIT    ; enable a800 IRQ interrupts (int 0dh)
        or  al,KEYBOARD_BIT     ; disable keyboard ints while A800 ints running
        out 21h,al
        ret
unmask_a800_int endp

; SET THE 'int 0dh' VECTOR
;    No regs.
;    Saves previous setting (to allow driver to be uninstalled).
;
set_vector      proc near
        push es
          ; SAVE CURRENT 'int 0dh' VECTOR
          xor ax,ax
          mov es,ax

          ; Is our vector already set?
          ;    Skip if so; we don't want to loose 'old' vector
          ;
          cmp es:[0034h],offset cs:a800_int
          jne sv_doset
          mov ax,cs
          cmp es:[0036h],ax
          jne sv_doset
          je  sv_skipset
sv_doset:
          ; Save old vector first, for restore later
          mov ax,es:[0034h]             ; save prev int 0d vector offset
          mov cs:[old_clock_vec_lo],ax
          mov ax,es:[0036h]             ; save prev int 0d vector segment
          mov cs:[old_clock_vec_hi],ax

          ; Set vector to our interrupt handler
          mov word ptr es:[0034h],offset cs:a800_int    ; int 0d vector
          mov word ptr es:[0036h],cs                    ; int 0d vector
sv_skipset:
        pop es
        ret
set_vector      endp

; SETUP A800 IRQ INTERRUPT VECTOR
;    No regs.
;    Disables ints, saves old vec, sets our vector, enables.
;
setup_8259_ints proc near
        ; save current 8259 flags for restore later
        in  al,21h
        mov cs:[old_8259_flags],ax

        cli                 ; disable ints
        call mask_a800_int
        call set_vector
        call unmask_a800_int

        ; Disable timer interrupt while motors running
        in  al,21h
        or  al,01h                      ; disable timer int: 8259 mask TIMER bit
        out 21h,al

        sti                             ; enable ints again

        ret
setup_8259_ints endp

restore_8259_int        proc near

        ; Disable a800 ints
        in  al,21h
        or  al,A800_8259_BIT            ; disable a800 IRQ interrupts (int 0dh)
        out 21h,al

        ; Restore old 'int 0d' vector
        push es
          xor ax,ax
          mov es,ax
          mov ax,cs:[old_clock_vec_lo]
          mov es:[0034h],ax             ; int 0d vector
          mov ax,cs:[old_clock_vec_hi]
          mov es:[0036h],ax             ; int 0d vector
        pop es

        ; Restore 8259 flags before ints were turned on
        mov ax,cs:[old_8259_flags]
        out 21h,al

        ret
restore_8259_int        endp

;
; ALLOCATED SPACE FOR THE GLOBAL ENVIRONMENT
; (This chunk of memory resides until machine turned off!)
;
recursion_err   db 3,"@@@  INTERRUPT 99h CALLED RECURSIVELY  @@@  (SYS HALT)",0
environment     db 20000 dup (0)

;==========================================================
; SETUP INTERRUPT DRIVERS. From here on, code does not reside,
; since it's only run once during setup.

; DONT do any init of the A800 board yet -- the main application
; hasn't yet setup the A800_struct.BaseAddr, so there's no point
; in doing anything until the base port and IRQ have been set 
; using "defs.exe startup.defs".


; Setup INT 99h
setup:
        mov ah,35h                      ;get current INT 99 vector
        mov al,99h
        int 21h
        cmp bx,offset cs:int_99
        jne xalready
        mov dx,offset cs:already
        mov ah,9
        int 21h
        int 20h

xalready:
        ; Print program banner
        mov dx,offset reside_msg
        mov ah,9
        int 21h

        ; Setup the INT 99 software interrupt handler
        mov ah,25h                      ;setup INT 99 handler
        mov al,99h
        mov dx,offset cs:int_99
        int 21h

        ;
        ; Setup Keyboard Intercept
        ;
        mov ah,35h
        mov al,16h                      ;get current KB int service vector
        int 21h                         ;(ES:BX returns current)

        mov ax,es
        mov cs:[KB_BIOS+0],bx           ;save in JMP FAR for fall thrus
        mov ds:[KB_BIOS+2],ax

        mov ah,25h                      ;vector to our routine
        mov al,16h
        mov dx,offset cs:kb_int
        int 21h

        ;
        ; Setup Video Intercept
        ;
        mov ah,35h
        mov al,10h                      ;get current video int service vector
        int 21h                         ;(ES:BX returns current)

        mov ax,es
        mov cs:[VID_BIOS+0],bx          ;save in JMP FAR for fall thrus
        mov ds:[VID_BIOS+2],ax

        mov ah,25h                      ;vector to our routine
        mov al,10h
        mov dx,offset cs:vid_int
        int 21h

        ;; -- Disabled for now --
        ;;
        ;; ENABLE SCROLL LOCK KEY
        ;;
        ;;      push ax
        ;;      push ds
        ;;          mov ax,0040h                ;keyboard buffer area
        ;;          mov ds,ax
        ;;          or byte ptr ds:[0017h],10h  ;turn on scroll lock key
        ;;      pop ds
        ;;      pop ax

        ;
        ; reside the whole magilla into memory.
        ;
        mov dx,offset cs:setup          ;reside all service routines
        mov ax,cs
        mov es,ax
        int 27h                         ;RESIDE/RETURN TO DOS

already db "A800 routines already resident",0dh,0ah,"$"

reside_msg:
        db "*** ERCOLANO OPCS A800 STEPPER DRIVER - V1.20 05/04/20 ***",0dh,0ah
        db "(C) Copyright 1999,2020 Gregory Ercolano. "
        db "All rights reserved",0dh,0ah
        db 0dh,0ah
        db "A800 - Driver routines loaded (INT 99h)",0dh,0ah
        db "       IRQ: INT 0dh (IRQ5/LPT2), 0000:0034-0000:0036",0dh,0ah
        db "       Allocated 20,000 bytes for shared memory area.",0dh,0ah
        db "       When SCROLL LOCK is on, counters will display.",0dh,0ah,0ah
        db "$"

cseg    ends
        end
