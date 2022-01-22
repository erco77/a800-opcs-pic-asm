; vim: autoindent tabstop=8 shiftwidth=4 expandtab softtabstop=4
title A800DRV - Terminate/Stay Resident driver for A800 card

; VERS  DATE       NOTES
; ----  ---------- -----------------------------------------
; 0.99  03/23/2020 Copied rtmc48.asm, created a800drv.asm, start dev
; 1.00  03/26/2020 First working version w/OPCS
; 1.10  05/02/2020 Use a800_struct.BaseAddr for all port I/O
; 1.20  05/04/2020 Disable timer ints during motor runs
;
;   ^
;   +-- (sync version #'s with RTMC48.ASM)
;   v
;
; 4.01  07/16/2021 > slap_screen now uses separate txt/attribute arrays (K2.03)
;                  > Env size enlarged from 20k to 25k for larger txt/att arrays
;
; 4.10  01/19/2022 > Added command line flags -h/-b/-i to set baseaddr + IRQ
;                  > Resynced mods w/rtmc48
;                  > BaseAddr removed from Kuper struct (cmdline sets now)
;                  > Fixed kb_int int 99 recursion err (goes back to K1.xx!)
;                  > Force CLD for all LODSB/STOSB operations
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
;
; NOTES:
;       The A800 board can manage 8 motor channels.
;       It has two CPUs; cpu1 for channels ABCD, cpu2 for EFGH.
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
;       prescribed, and will THEN be checked for the ALLSTOP bit.
;       This ensures the velocities get sent, and counters update
;       correctly.
;
;       If ALLSTOP bit is being used, the ASAddr must be set to point
;       to the rampdown velocities BEFORE setting the A800_Allstop flag.
;
;       Once the A800_Allstop flag is set, when the motor routines
;       see this flag AND the A channel ALLSTOP bit set, they will
;       send these vels to the motor and will THEN switch to using
;       the rampdown velocities from then on to stop the motors.
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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;

; The A800 structure
;    (Same as the Kuper structure)
;    See OPCS src "env.h"
;    NOTE: In 2.10/TC, 'BaseAddr' removed from Kuper/A800 struct
;
                                ;OFFS (SIZE)   DESCRIPTION
a800struc struc                 ;---- ------   ---------------------------
      A800_RingBuffer   dw 0,0  ;+00h (far)    pointer to 64k ring buffer
      A800_Counter      dw 0,0  ;+04h (far)    pointer to counter array
      A800_Head         dw 0    ;+08h (ushort) c program's leading pointer
      A800_Tail         dw 0    ;+0ah (ushort) hardware following pointer
      A800_Stopped      dw 0    ;+0ch (ushort) flags that int routine stopped
      A800_SyncFault    dw 0    ;+0eh (ushort) flags a sync error occurred
      A800_AllStop      dw 0    ;+10h (ushort) flag to do an allstop
      A800_CountType    dw 0    ;+12h (ushort) Type of counter update
      A800_ASAddr       dw 0    ;+14h (ushort) address of vels for rampdown
a800struc ends                  ;              (set ASAddr first, then Allstop)

STOPBIT         equ 8000h               ;This bit in a velocity indicates
                                        ;this is the last velocity in the ring.
ALLSTOPBIT      equ 4000h               ;This bit indicates 'check for allstop'
                                        ;address in A800_AllStop for a rampdown.
SOFTREVBIT      equ 2000h               ;This bit tells the software counters
                                        ;to count in reverse, regardless of
                                        ;hardware bit (due to direction inverts)
FULLROTBIT      equ 1000h               ;This bit tells the driver to make a
                                        ;count when using the ROTATION counter
                                        ;update type. This bit should appear in
                                        ;the last velocity of a full rotation.
DIRBIT          equ 0800h               ;Motor direction bit
HARDMASK        equ 08ffh               ;Leave hardware bits behind (dirbit + lo 8 bits)
COUNTMASK       equ 00ffh               ;Leave countable vel behind (lo 8 bits)

NOCOUNTTYPE     equ 0                   ;different types of counter updating
STEPCOUNTTYPE   equ 1
ROTCOUNTTYPE    equ 2

;
; A800 ADDRESS OFFSETS
;   The A800 board uses an 8255 to manage communications which has three
;   8bit ports: (BASE+0 thru BASE+2) and a control port (BASE+3):
;
;       PORT_A     - BASE+0
;       PORT_B     - BASE+1
;       PORT_C     - BASE+2
;       CTRL_8255  - BASE+3
;
;   Since the base address for the 8255 is configurable, we use
;   these variables to hold the configured values:
;
;       Variable         Default Offset Description
;       ---------------- ------- ------ --------------------------------------
;       cs:[base_0]      0300h   BASE+0 Set with -b (NEW/UNUSED)
;       cs:[base_1]      0301h   BASE+1 Set with -b (NEW/UNUSED)
;       cs:[base_2]      0302h   BASE+2 Set with -b (NEW/UNUSED)
;       cs:[base_3]      0303h   BASE+3 Set with -b (NEW/UNUSED)
;
;       cs:[data_port]   0300h   BASE+0 PORT_A    OUT:8 bits (data to PIC)
;       cs:[ack_port]    0301h   BASE+1 PORT_B    IN:cpu1(01h) cpu2(02h)
;       cs:[strobe_port] 0302h   BASE+2 PORT_C    OUT:cpu1(10h) cpu2(01h)
;       cs:[start_port]  0302h   BASE+2 PORT_C    OUT:cpu1(40h) cpu2(04h)
;       cs:[ctrl_port]   0303h   BASE+3 CTRL_PORT set to 82h (A/C out, B in)
;

;
; 8255 RELATED COMMUNICATION EQUATES
;

; ACK handshake signal from a cpu
ack_bit_cpu1            equ 01h
ack_bit_cpu2            equ 02h

; STROBE data to a cpu
strobe_bit_cpu1         equ 10h
strobe_bit_cpu2         equ 01h

; SVEL handshake signal to a cpu
start_bit_cpu1          equ 40h
start_bit_cpu2          equ 04h

;;;
;;; MISC EQUATES
;;;

KEYBOARD_BIT     equ 02h         ; (2 is to disable keyboard ints)
A800_CHANS       equ 8d          ; number of hardware channels A800 supports

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
                
; Compare two segment registers
cmp_seg         macro areg,breg
                push ax
                push bx
                  mov ax,areg     ; seg areg -> ax
                  mov bx,breg     ; seg breg -> bx
                  cmp ax,bx       ; compare
                pop bx
                pop ax
                endm

; BIOS: PRINT A MESSAGE
;    Handles CRLF at end of msg
;    Usage: print "Hello world."
;
print           macro msg
                local msgtext,skipmsg,print_loop,print_done
                jmp skipmsg
msgtext         db msg,'$'
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
                  cmp al,'$'            ; '$'? (DOS style EOS)
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

; DOS PRINT A MESSAGE WITH CRLF
;    Uses INT 21/AH=09h to print string
;    Usage: dosprint "Hello world."
;
dosprint        macro msg
                local msgtext,skipmsg
                jmp skipmsg
msgtext         db msg,0dh,0ah,'$'
skipmsg:        push ax
                push dx
                  mov  dx,offset cs:msgtext
                  mov  ah,9
                  int  21h
                pop dx
                pop ax
                endm

; DOS: PRINT A MESSAGE (NO CRLF)
;    Uses INT 21/AH=09h to print string
;    Usage: dosprint_nocrlf "Value is: "
;
dosprint_nocrlf macro msg
                local msgtext,skipmsg
                jmp skipmsg
msgtext         db msg,'$'
skipmsg:        push ax
                push dx
                  mov  dx,offset cs:msgtext
                  mov  ah,9
                  int  21h
                pop dx
                pop ax
                endm

;
; ASSEMBLER HEADER
;
sseg    segment stack
sseg    ends

cseg    segment para
        assume cs:cseg,ds:cseg,ss:sseg
        org 0100h                       ;COM format

        jmp setup

;
; A800's BASE ADDRESS FOR 8255 PORTS
;     Base address + IRQ are configurable via the driver command line,
;     and by jumpers on the A800 card, which must both agree on the values.
;     'call set_baseaddr' to initialize these variables.
;
base_0          dw 0300h   ; BASE+0 address (changed with -b)
base_1          dw 0301h   ; BASE+1 address (changed with -b) (NEW/UNUSED)
base_2          dw 0302h   ; BASE+2 address (changed with -b) (NEW/UNUSED)
base_3          dw 0303h   ; BASE+3 address (changed with -b) (NEW/UNUSED)

data_port       dw 0300h   ; BASE+0 - PORT_A    - OUT: all 8 bits (data to PIC)
ack_port        dw 0301h   ; BASE+1 - PORT_B    - IN:  cpu1(01h) cpu2(02h)
strobe_port     dw 0302h   ; BASE+2 - PORT_C    - OUT: cpu1(10h) cpu2(01h)
start_port      dw 0302h   ; BASE+2 - PORT_C    - OUT: cpu1(40h) cpu2(04h)
ctrl_port       dw 0303h   ; BASE+3 - CTRL_PORT - set 82h for PORT A/C out, B in

; A800 IRQ
;     'call set_irq' to initialize these variables based on cmdline args
;
irq_num         db 05h     ; IRQ value (5 default)
irq_int_num     db 0dh     ; IRQ interrupt# (IRQ# + 08h = INT#)
irq_8259_mask   db 20h     ; 8259 'mask irq' bit (1 << irq_num)
                           ; set=IRQ int off, clr=ints on

old_irq_vec_lo  dw 0       ; old vector for IRQ interrupt
old_irq_vec_hi  dw 0
old_8259_flags  dw 0       ; saves flags before we started motors

; INT 99 - register save area
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

; Misc variables
scrollheight    db 3       ; used by int99/AH=12d, int10/AH=9d,14d
a800_struct     dw 0,0     ; far pointer to a800 structure
update          dw offset no_count_update   ; points to motor update function
kbint_lastcount db 0                        ; limit timer counter

;
; INT 99 DISPATCHER
;    This is how external applications (e.g. OPCS) talk to this driver
;    via INT 99. To see the various operations this interrupt provides,
;    see the 'funtab' (function table) below for the list and AH codes,
;    and see each function's code header comment for usage.
;
int_99:
        sti

        test   cs:INT_99_RUNNING,1      ;are we running already?
        jfalse int_99_xrun
	jmp    int99_recursion_halt

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
                dw      int99_buzz1sec          ;4d DEBUGGING ONLY
                dw      int99_nop               ;5d
                dw      int99_nop               ;6d
                dw      int99_nop               ;7d
                dw      int99_nop               ;8d
                dw      int99_get_baseaddr_irq  ;9d  new/unused 2022
                dw      int99_get_env_ptr       ;10d
                dw      int99_display_screen    ;11d
                dw      int99_scroll_height     ;12d
                dw      int99_cs_wait           ;13d currently nop - was a (broken?) cswait
                dw      int99_nop               ;14d
                dw      int99_nop               ;15d
                dw      int99_nop               ;16d

int_99_done:
        mov ax,cs:SAX_99                ;save all regs w/out wasting stack
        mov bx,cs:SBX_99

int_99_ret_ax_bx:
        mov cx,cs:SCX_99                ;restore all regs except AX/BX for ret
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
; INT 99 - Dummy handler (NOP)
;
int99_nop:    jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=0 (00h)
;
;     Sets the s800_struct to the segment:offset address in CX:BX
;     For a definition of this structure, see 'a800struc'.
;
;     BX = offset  (LSW) of ptr to a800/kuper structure
;     CX = segment (MSW) of ptr to a800/kuper structure
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_set_a800_struct:
        mov cs:[a800_struct+0],bx       ; offset
        mov cs:[a800_struct+2],cx       ; segment
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
; INT 99 - AH=1 (01h)
;
;     Enable the kuper interrupt driver to start feeding velocities
;     from the ring buffer.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_start_a800:
        mov bx,cs:[a800_struct+0]
        mov ds,cs:[a800_struct+2]

        ; Copy counter type from struct
        call set_counter_type

        ; Zero 'Stopped' and 'SyncFault' before each run
        mov word ptr ds:[bx].A800_Stopped,0
        mov word ptr ds:[bx].A800_SyncFault,0

        ;;; A800 INIT ;;;

        ; Program 8255 I/O
        output cs:[ctrl_port],82h       ; PORT A+C output, PORT B input
        output cs:[data_port],0         ; zero data bus
        output cs:[strobe_port],0       ; disable start+strobe

        ;; COMMENTED OUT - IS NOT SYNCHRONIZED WITH IRQ, SO DONT DO IT.
        ;;
        ;; ; Send zero vels for all channels
        ;; call hardstop                ; send zero vels to all channels

        ; Enable interrupts
        call setup_8259_ints            ; enable IRQ5 interrupts

        ; Return to caller with ints running in background
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=2 (02h)
;     Stop the A800 (opposite of int99_start_a800).
;
;     >> This is a nop because it's better the main application
;     >> handle ramping the motors to zero vels with STOPBIT set,
;     >> than to try to do any logic here to do that.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_stop_a800:
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=3d (03h)
;     Wait for the A800 to finish running motors.
;
;    >> This is a nop because it's better for the main application
;    >> to simply wait for the K.Allstop to be set.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_wait_a800:
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=4d (04h)
;     DEBUGGING ONLY
;     Buzz the screen for 1sec (107 samples)
;     Added 01/17/2022.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_buzz1sec:
        ; Program 8255 I/O
        output cs:[ctrl_port],82h       ; PORT A+C output, PORT B input
        output cs:[data_port],0         ; zero data bus
        output cs:[strobe_port],0       ; disable start+strobe

        ; Send zero vels for all channels
        call hardstop                ; send zero vels to all channels

        ; Enable interrupts
        call setup_buzz1sec          ; enable IRQ5 interrupt to buzz screen

        ; Return to caller with ints running in background
        jmp int_99_done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=09d (09h)
;     Returns IRQ# in AL and BaseAddr in BX.
;     Not currently used by apps, but provided in the API should they need it.
;     Added 01/17/2022.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_get_baseaddr_irq:
        mov ah,0
        mov al,cs:[irq_num]
        mov bx,cs:[base_0]
        jmp int_99_ret_ax_bx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=10d (0ah)
;     Returns a pointer to the global 'environment'
;     AX:BX returns the far pointer.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_get_env_ptr:
        mov ax,cs
        mov bx,offset cs:screen_txt     ; K2.03+
        jmp int_99_ret_ax_bx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
; (K2.03+)
;
; INT 99 - AH=11d
;     The environment's screen_txt[] and screen_att[] arrays are managed
;     by the application and are 'slapped' to the screen. The number of
;     lines transferred by 'slap_screen' is the current 'scrollheight' value,
;     which must never exceed 14 (the maximum number of lines).
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_display_screen:
        call update_screen
        jmp  int_99_done

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;
; INT 99 - AH=13d (0dh)
;    Wait number of centiseconds (cs) in AX.
;
;    >> This is a nop because the old code didn't work well/unreliable,
;    >> and isn't needed anymore anyway, because Turbo C provides this.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
int99_cs_wait:
        jmp int_99_done

;; *** END OF INTERRUPT 99 HANDLERS ***
;; *** END OF INTERRUPT 99 HANDLERS ***
;; *** END OF INTERRUPT 99 HANDLERS ***

; K2.03+
; Screen attributes
;    No longer used by our code, as main program would now use these,
;    but keep here simply for reference..
;
;    Name           Attrib     Index
;    -----------    ------     ---------------
;    NULL           equ 0      ;0 [never used]
;    NORMAL         equ 07h    ;1
;    BRIGHT         equ 0fh    ;2
;    FLASH          equ 87h    ;3
;    INVERSE        equ 70h    ;4
;    FLASHINVERSE   equ 0f0h   ;5
;    HIDE           equ 00h    ;6

; K2.03+
;
; SLAP AN ENVIRONMENT BUFFER TO THE SCREEN
;        ds:si  - src env buffer    (e.g. env->screen_txt)
;        es:di  - dst screen buffer (e.g. 0b800:0000 or 0b800:0001)
;    Moves #bytes to move based on 'scrollheight'.
;
slap_screen:
        ; Save stuff
        push bx
        push cx
        push dx
        push ds         ; save src segment
        push si         ; save src offset
        push es         ; save dst segment
        push di         ; save dst offset
          ;
          ; Determine how many bytes to transfer: 
          ;    bytes = scrollheight x 80d
          ; ..which will be the loop counter.
          ;
          mov ax,0
          mov al,cs:[scrollheight]
          mov bx,80d
          mul bx              ; unsigned 16bit: AX * BX -> DX:AX
          mov cx,ax           ; 16bit result of multiply -> CX

          ; Do buffer move:
          ;    DS:SI - src buffer (e.g. env->screen_txt)
          ;    ES:DI - dst screen (e.g. 0xb800:0000)
          ;    CX    - src bytes to move
          ;
	  pushf              ; save dir flag
	    cld
ss_loop:    lodsb            ; DS:SI -> AL, SI++
            stosb            ; AL -> ES:DI, DI++
            inc  di          ; write to every OTHER byte
            loop ss_loop
	  popf

        pop di
        pop es
        pop si
        pop ds
        pop dx
        pop cx
        pop bx
ss_done:
        ret

; SLAP AN ATTRIBUTE TO SCREEN RANGE
;    es:di - starting point of attribute range
;    cx    - length of attribute range
;    al    - attribute (e.g. f0 = flash/inverse)
;
slap_attrib:
    or   di,1		; attribute addresses are odd numbered
    push cx
    pushf               ; save dir flag
      cld               ; count up
ssa_loop:
      stosb		; store AL -> ES:DI, DI++
      inc di            ; DI++ (step by 2's for next attrib)
      loop ssa_loop
    popf
    pop cx
    ret

;
; The following intercepts the BIOS keyboard interrupt service...
; If no keys await in keyboard buffer, the screen display is updated before
; calling the keyboard BIOS.
;
kb_int:
        push ax
        push ds
            mov ax,0040h                ; keyboard buffer area
            mov ds,ax
            mov al,ds:[006ch]           ; timer count (18 / sec)
            and al,0f8h
            cmp al,cs:[kbint_lastcount] ; dont update faster than half a second
            mov cs:[kbint_lastcount],al
            je nodisp

            mov al,ds:[0017h]           ; shift key states
            and al,10h                  ; SCROLL LOCK?
            jz nodisp                   ; if scroll lock not enabled, skip

;NO!;	    mov ah,11d			; redisplay screen (saves regs)
;NO!;	    int 99h
            call update_screen          ; redisplay screen

nodisp:   pop ds
          pop ax

          db 0eah                       ; jmp far
KB_BIOS   dw 0,0

;
; INTERCEPT VIDEO SCROLLS (make sure counter's lines dont scroll off)
;
vid_int:
        cmp ah,6                ;scrollup?
        je scrollup
        cmp ah,0eh              ;print teletype?
        je teletype

to_vid_bios:
                db 0eah         ;jmp far
VID_BIOS        dw 0,0          ;far address to jump to

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; INT 10H
;     (AH) = 14d (0eh) WRITE TELETYPE TO ACTIVE PAGE
;            (AL) = CHAR TO WRITE
;            (BL) = FOREGROUND COLOR IN GRAPHICS MODE
;            NOTE -- SCREEN WIDTH IS CONTROLLED BY PREVIOUS MODE SET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
        jz to_vid_bios          ;if scroll lock not enabled, skip

        push ds
          mov ax,0040h
          mov ds,ax
          mov al,ds:[0051h]     ;get vertical cursor position from BIOS
        pop ds
        cmp al,24d              ;bottom of screen?
        jl  te_xbott            ;no, then just print the linefeed

        push bx
         push cx
          push dx
            ; From INT 10H docs:
            ;    "CS,SS,DS,ES,BX,CX,DX PRESERVED DURING CALL
            ;     ALL OTHERS DESTROYED" ie. AX,SI,DI
            ;
            mov ax,0601h             ;INT 10H/AH=6, AL=lines to scroll (1)
            mov cl,0                 ;   (CL)=col of upper left (0)
            mov ch,cs:[scrollheight] ;   (CH)=row of upper left
            mov bx,0707h             ;   (BH)=attribute for blank line
            mov dx,184fh             ;   (DH,DL)=row/col of lower right
            int 10h                  ; do scroll with our values
          pop dx
         pop cx
        pop bx
        mov ax,0e0ah
        iret

te_xbott:
        mov ax,0e0ah
        jmp to_vid_bios

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; INT 10H
;     (AH)=6    SCROLL ACTIVE PAGE UP
;               (AL) = NUMBER OF LINES, INPUT LINES BLANKED AT WIN BOTTOM
;                      AL = 0 MEANS BLANK ENTIRE WINDOW
;               (CH,CL) = ROW,COL OF UPPER LEFT CORNER OF SCROLL
;               (DH,DL) = ROW,COL OF LOWER RIGHT CORNER OF SCROLL
;               (BH) = ATTRIBUTE TO BE USED ON BLANK LINE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
scrollup:
        push ds
        push ax
            mov ax,0040h
            mov ds,ax
            mov al,ds:[0017h]     ;shift key states
            and al,10h            ;SCROLL LOCK?
        pop ax
        pop ds
        jz to_vid_bios            ;if scroll lock not enabled, skip

        cmp ch,1d                 ;scroll screen check (top line)
        jg to_vid_bios
        cmp dh,22d                ;scroll screen check (bottom line)
        jl to_vid_bios
        mov ch,cs:[scrollheight]  ;HACK!!! Should probably return
                                  ;original value after scrolling?
        jmp to_vid_bios

;
; INT 99 RECURSION ERROR - Print error and stop the machine!
;
int99_recursion_halt:

        ; Insert hex values of conflicting INT 99 calls (AH=??) into errmsg
        push ax                          ; Save INT 99 AH=xx
	  ; CONVERT THIS CALL'S AH TO HEX
          xchg al,ah                     ; Show AH: move it to AL
          call byte2hex                  ; Returns AL as hex chars in AH/AL
          mov  cs:[recursion_hex_A+0],ah ; Insert hex chars into recursion_err
          mov  cs:[recursion_hex_A+1],al
	  ; CONVERT CONFLICTING CALL'S AH TO HEX
          mov  ax,cs:SAX_99              ; get parent AH call
          xchg al,ah                     ; Show AH: move it to AL
          call byte2hex                  ; Returns AL as hex chars in AH/AL
          mov  cs:[recursion_hex_B+0],ah ; Insert hex chars into recursion_err
          mov  cs:[recursion_hex_B+1],al
        pop ax
        ;
        ; Enable keyboard ints (so user can hit CTRL-ALT-DEL)
        ; and disable kuper ints (so they don't overwrite our errormsg)
        ;
        in  al,21h
        or  al,KEYBOARD_BIT       ; 8259 keyboard int mask bit
        xor al,KEYBOARD_BIT       ; bit OFF to enable keyboard
        or  al,cs:[irq_8259_mask] ; disable kuper ints
        out 21h,al

;WHY?;  ; Update screen counters
;WHY?;  call update_screen

        ; Jam error msg onto top line of screen
        ;    Include the two conflicting INT 99 functions (AH=??) as hex
        ;    in the error msg.
        ;
        mov si,offset cs:recursion_err  ; screen string is the first array in 
        mov ax,cs                       ; the global environment
        mov ds,ax
        mov di,0

        push si
        push di
          mov ax,0b000h
          mov es,ax
          call slap_screen      ; write to MDA
	  pop di
	  push di
	  mov al,0f0h		; flashing inverse
	  mov cx,80d            ; do entire line
	  call slap_attrib	; write to MDA
        pop di
        pop si
	push si
	push di
          mov ax,0b800h
          mov es,ax
          call slap_screen      ; write to VGA
	  pop di
	  push di
	  mov al,0f0h		; flashing inverse
	  mov cx,80d            ; do entire line
	  call slap_attrib	; write to VGA
        pop di
        pop si
        ;
        ; Halt machine!
        ; This is a very fatal error.
        ;
halt_sys:
        jmp halt_sys

;
; K2.03+
; Transfer the environment env->screen_txt/att to the screen buffer
;
update_screen:
        push ax
        push si
        push di
        push ds
        push es

          ;;; FIRST, DO TEXT BUFFER (env->screen_txt)
          ; env->screen_txt -> DS:SI
          mov si,offset cs:screen_txt
          mov ax,cs
          mov ds,ax
          ; 0xb800:0000 -> ES:DI
          mov di, 0000h
          mov ax,0b800h
          mov es,ax
          call slap_screen

          ;;; NEXT, DO ATTRIBUTE BUFFER (env->screen_att)
          ; env->screen_att -> DS:SI
          mov si,offset cs:screen_att
          mov ax,cs
          mov ds,ax
          ; 0xb800:0001 -> ES:DI
          mov di, 0001h
          mov ax,0b800h
          mov es,ax
          call slap_screen

        pop es
        pop ds
        pop di
        pop si
        pop ax
        ret

;;;                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; A800 ROUTINES   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 80 ;;
;;;                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

; Convert byte in AL to two hex chars in AH/AL
byte2hex:
        push bx         ; (we use bx for scratch)
          mov bx,ax     ; save ax -> bx
          shr al,1      ; move MSN -> LSN
          shr al,1
          shr al,1
          shr al,1
          call b2h_nib  ; returns MSN as hex in AL
          mov ah,al     ; save hex -> AH
          mov al,bl     ; restore AL
          call b2h_nib  ; returns LSN as hex in AL
          ;
          ; We now have:
          ;    Hex of MSN in AH
          ;    Hex of LSN in AL
          ;
        pop bx
        ret
; Return binary LSN of AL as hex char in AL
; e.g. IN: AL=72  OUT: AL='2'
;             ::          .:.
;             ::...........:
;             :
;             Don't care about MSN
;
b2h_nib:  and al,0fh
          cmp al,09h
          jle b2h_num
          add al,('A'-0ah)
          ret
b2h_num:  add al,'0'
          ret

;
; Set the a800 base address to 16bit value in AX
;
set_baseaddr:
        mov  cs:[base_0],ax
        mov  cs:[data_port],ax          ; PORT_A (BASE+0)
        inc  ax
        mov  cs:[base_1],ax
        mov  cs:[ack_port],ax           ; PORT_B (BASE+1)
        inc  ax
        mov  cs:[base_2],ax
        mov  cs:[strobe_port],ax        ; PORT_C (BASE+2)
        mov  cs:[start_port],ax         ; PORT_C (BASE+2) - same as above
        inc  ax
        mov  cs:[base_3],ax
        mov  cs:[ctrl_port],ax          ; CTRL_PORT (BASE+3)
        ret

;
; Set the a800 IRQ to 8bit value in AL
;
;    AL=IRQ#, e.g. 02h for IRQ2, 05h for IRQ5, etc
;
set_irq:
        push cx
          push ax
            mov ds:[irq_num],al
            add al,08h
            mov ds:[irq_int_num],al
          pop ax

          ; AL = (1 << irq_num)
          mov cl,al
          mov al,1                  ;                    7654 3210
          shl al,cl                 ; e.g. IRQ5 -> 020h (0010 0000)
          mov ds:[irq_8259_mask],al ; 8259 bit: set=disable IRQ, clr=enable IRQ
        pop cx
        ret                         ; return to caller

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

;;DEBUG;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;DEBUG mov ax,0b000h                   ;DEBUGGING ONLY - buzz mda scrn
;;DEBUG mov ds,ax
;;DEBUG inc byte ptr ds:[0f00h]         ; 0f00 for bottom left
;;DEBUG
;;DEBUG mov ax,0b800h                   ;DEBUGGING ONLY - buzz vga scrn
;;DEBUG mov ds,ax
;;DEBUG inc byte ptr ds:[0f00h]         ; 0f00 for bottom left
;;DEBUG;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
                                        ;    ..and update counters

        ; Get A channel's vel word from ring buffer
        ;    Code after this needs to test the A channel's vels to:
        ;    Check if STOPBIT set (to see if motors stopped),
        ;    and check ALLSTOPBIT to see if we need to start a rampdown.
        ;
        push ds
        push si
          mov si,ds:[bx].A800_Tail         ; get tail of ring buffer
          mov ax,ds:[bx].A800_RingBuffer+2 ; +2: gets segment address of ring
          mov ds,ax
          mov ax,ds:[si]                   ; A chan RTMC vel from ring buf
        pop si
        pop ds

;;      ; See if head and tail are the same, indicating end of buffer.
;;      ; If they're the same, THEN check for STOPBITs in vels.
;;      mov cx,ds:[bx].A800_Tail
;;      cmp cx,ds:[bx].A800_Head        ; Check if those were last velocities?
;;      jne notlast                     ; No, skip..
;;
;;      ; Caught up with head. Check if it was intentional by checking
;;      ; for a hi 'stop' bit in the A channel's velocity
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
        call restore_8259_int           ; restore old int pointer
        jmp done_a800_int               ; return from interrupt for last time

        ;
        ; Check for an allstop condition. If so, set A800_Tail to address
        ; in A800_ASAddress to execute allstop when appropriate.
        ;
notlast:
        cmp word ptr ds:[bx].A800_AllStop,1 ; Caller wants us to stop?
        jne notallstop

        test ax,ALLSTOPBIT              ; Check if it's appropriate to stop
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

        mov ax,ds:[bx].A800_ASAddr      ;ALLSTOP. Load ASA to the tail
        mov ds:[bx].A800_Tail,ax        ;and acknowledge the allstop.
        mov word ptr ds:[bx].A800_AllStop,0
        jmp done_a800_int               ;(skip past the A800_Tail advance)

notallstop:
        ; Handle advancing Tail to next set of vels
        add ds:[bx].A800_Tail,32d       ;32 bytes for 16 channels

done_a800_int:
        mov al,20h                      ; acknowledge interrupt
        out 20h,al                      ; EOI -> 8259

        pop es
        pop ds
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        iret

;;;;;;;;;;;;
a800_buzz1sec_int:
        cli
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push ds
        push es
            ; THIS IS ALL WE DO - BUZZ SCREEN
            mov ax,0b800h               ;DEBUGGING ONLY
            mov ds,ax
            cmp byte ptr ds:[0f00h],0   ; at zero? done
            je abz_stopints
            dec byte ptr ds:[0f00h]     ; buzz screen until char==0
            jmp abz_done
abz_stopints:
            ; Done - stop ints
            call restore_8259_int       ; restore old int pointer
abz_done:
        mov al,20h                      ;acknowledge interrupt
        out 20h,al                      ; EOI -> 8259

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

step_count_update:  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

rot_count_update:  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;
; SUBROUTINES FOR ABOVE PROCEDURES
; ALL ROUTINES ASSUME ds:[bx] POINTS TO THE KUPER STRUCTURE
;

; Mask off the 8259's A800 IRQ (default int 0d) prevents generating ints
mask_a800_int           proc near
        in al,21h
        or al,cs:[irq_8259_mask]     ;disable a800 IRQ interrupts
;       or al,KEYBOARD_BIT      ;;;; DONT ASSUME KEYBOARD BIT ON
;       xor al,KEYBOARD_BIT     ;;;; DONT ASSUME KEYBOARD BIT ON ;enable kbd
        out 21h,al
        ret
mask_a800_int           endp

; Unmask 8259's A800 IRQ (default int 0d), allow generating ints
unmask_a800_int proc near
        in  al,21h
        or  al,cs:[irq_8259_mask]
        xor al,cs:[irq_8259_mask]  ; enable a800 IRQ interrupts
        or  al,KEYBOARD_BIT        ; disable keyboard ints while A800 ints running
        out 21h,al
        ret
unmask_a800_int endp

; SET THE A800 IRQ VECTOR (default int 0dh)
;    Saves previous setting (to allow driver to be uninstalled).
;
;     Input: No regs. cs:[irq_int_num] is IRQ# to set vector for.
;    Output: No regs. Old vector saved in [old_irq_vec_{lo|hi}], new set to cs:a800_int
;
set_vector      proc near
        push bx
        push cx
        push dx
        push es
          mov     ah,35h                    ; DOS: Get vector..
          mov     al,cs:[irq_int_num]       ; ..for A800 irq
          int     21h                       ; returns vector in ES:BX

          ; SAVE EXISTING IRQ VECTOR
          ;    First see if vector already pointing to us?
          ;    Skip if so; we don't want to loose 'old' vector
          ;
          cmp     bx,offset cs:a800_int     ; compare offsets
          jne     sv_doset
          cmp_seg cs,es                     ; compare segment regs CS: <-> ES:
          jne     sv_doset
          je      sv_skipset

sv_doset:
          ; Save old vector for restore later
          mov     cs:[old_irq_vec_lo],bx
          mov     ax,es
          mov     cs:[old_irq_vec_hi],ax

          ; Set vector to our interrupt handler
          push ds
            mov   dx,offset cs:a800_int     ; offset of a800_int
            mov   ax,cs
            mov   ds,ax                     ; segment of a800_int
            mov   ah,025h                   ; DOS: Set vector in AL to (DS:DX)
            mov   al,cs:[irq_int_num]       ; AL is interrupt#
            int   21h
          pop ds
sv_skipset:
        pop es
        pop dx
        pop cx
        pop bx
        ret
set_vector      endp

set_vector_buzz1sec:
        push bx
        push cx
        push dx
        push es
        push ds
          ; Save old vector
          push es
          push bx
              mov     ah,35h                    ; DOS: Get vector..
              mov     al,cs:[irq_int_num]       ; ..for A800 irq
              int     21h                       ; returns vector in ES:BX
              mov     cs:[old_irq_vec_lo],bx
              mov     ax,es
              mov     cs:[old_irq_vec_hi],ax
          pop bx
          pop es

          ; Set vector to our interrupt handler
          mov   dx,offset cs:a800_buzz1sec_int
          mov   ax,cs
          mov   ds,ax                     ; our code segment
          mov   ah,025h                   ; DOS: Set vector in AL to (DS:DX)
          mov   al,cs:[irq_int_num]       ; AL is interrupt#
          int   21h
        pop ds
        pop es
        pop dx
        pop cx
        pop bx
        ret

;
; Used by INT 99 AH=04h
;
setup_buzz1sec:
        ; First initialize char on screen to 107.
        ;     We count it down until it reaches 0
        ;
        push ds
            mov ax,0b800h
            mov ds,ax
            mov byte ptr ds:[0f00h],107d
        pop ds

        ; save current 8259 flags for restore later
        in  al,21h
        mov cs:[old_8259_flags],ax
        cli
          call mask_a800_int
          call set_vector_buzz1sec
          call unmask_a800_int
        sti                   ; enable ints again
        ret

; SETUP A800 IRQ INTERRUPT VECTOR
;    No regs.
;    Disables ints, saves old vec, sets our vector, enables.
;
setup_8259_ints proc near
        ; save current 8259 flags for restore later
        in  al,21h
        mov cs:[old_8259_flags],ax

        cli                   ; disable ints
          call mask_a800_int
          call set_vector
          call unmask_a800_int

          ; Disable timer interrupt while motors running
          in  al,21h
          or  al,01h          ; disable timer int: 8259 mask TIMER bit
          out 21h,al
        sti                   ; enable ints again

        ret
setup_8259_ints endp

restore_8259_int        proc near

        ; Disable a800 ints
        in  al,21h
        or  al,cs:[irq_8259_mask]         ; disable a800 IRQ interrupts
        out 21h,al

        ; Restore old IRQ vector
        push ds
          mov   dx,cs:[old_irq_vec_lo]    ; offset of saved IRQ vec
          mov   ax,cs:[old_irq_vec_hi]    ; segment of saved IRQ vec
          mov   ds,ax
          mov   ah,025h                   ; DOS: Set vector in AL to (DS:DX)
          mov   al,cs:[irq_int_num]       ; AL is interrupt#
          int   21h
        pop ds

        ; Restore 8259 flags before our IRQ ints were turned on
        ;     This will restore timer int too
        ;
        mov ax,cs:[old_8259_flags]
        out 21h,al

        ret
restore_8259_int        endp

;
; ALLOCATED SPACE FOR THE GLOBAL ENVIRONMENT
; The screen_txt/att array size must MATCH the C code's array sizes.
; (This chunk of memory resides until machine turned off!)
;
SCRNSIZE        equ (80*14)          ; 80 x 14 lines of screen memory K2.03+
recursion_err   db "@@@  A800DRV: INT 99h RECURSION/REENTRY: AH=0x"
recursion_hex_A db "XX vs. 0x"       ; halt writes over "XX" w/hex digits
recursion_hex_B db "XX"              ; halt writes over "XX" w/hex digits
                db "  @@@  (SYS HALT)  ",0
; K2.03+
screen_txt      db SCRNSIZE dup (0)  ; uchar screen_txt[80*14] for scrn text
screen_att      db SCRNSIZE dup (0)  ; uchar screen_att[80*14] for scrn attribs
                db 25000-(SCRNSIZE*2) dup (0) ; pad env to 25000 bytes total

;       ^
;      /|\
;       |
; This code resides in memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This code does NOT reside
;       |
;      \|/
;       v

;==========================================================
; SETUP INTERRUPT DRIVERS. From here on, code does not reside,
; since it's only run once during setup.

; DONT do any init of the A800 board yet -- defer to when main
; application starts moving motors.

; Setup INT 99h
setup:
        ; First parse command line; handle any flags specified
        call parse_cmdline

        ; Initialize
        mov ah,35h                      ; DOS: Get interrupt vector
        mov al,99h                      ; for INT 99 in ES:BX
        int 21h
        cmp bx,offset cs:int_99
        jne xalready
        mov dx,offset cs:already
        mov ah,9                        ; DOS: Print string
        int 21h
        int 20h

xalready:
        mov dx,offset copyright
        mov ah,9                        ; DOS: Print string
        int 21h

        ; Print program banner
        mov dx,offset reside
        mov ah,9                        ; DOS: Print string
        int 21h

        dosprint_nocrlf "BaseAddr: "
        mov             ax,ds:[base_0]
        call            printhexword
        dosprint        "h"
        dosprint_nocrlf "     IRQ: "
        mov             ah,0
        mov             al,ds:[irq_num]
        call            printhexbyte
        dosprint        "h"

        ; Setup the INT 99 software interrupt handler
        mov ah,25h                      ; DOS: Set vector in AL to (DS:DX)
        mov al,99h                      ; ..for INT 99 handler
        mov dx,offset cs:int_99
        int 21h

        ;
        ; Setup Keyboard Intercept
        ;
        mov ah,35h                      ; DOS: Get interrupt vector
        mov al,16h                      ; for INT 16h in ES:BX
        int 21h

        mov ax,es
        mov cs:[KB_BIOS+0],bx           ; save in JMP FAR for fall thrus
        mov ds:[KB_BIOS+2],ax

        mov ah,25h                      ; DOS: Set vector in AL to (DS:DX)
        mov al,16h
        mov dx,offset cs:kb_int
        int 21h

        ;
        ; Setup Video Intercept
        ;
        mov ah,35h                      ; DOS: Get interrupt vector
        mov al,10h                      ; get current video int service vector
        int 21h                         ; (ES:BX returns current)

        mov ax,es
        mov cs:[VID_BIOS+0],bx          ; save in JMP FAR for fall thrus
        mov ds:[VID_BIOS+2],ax

        mov ah,25h                      ; DOS: Set vector in AL to (DS:DX)
        mov al,10h                      ; for INT 10h
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
        ; Reside the entire TSR application into memory.
        ;
        ;     Everything before the address of the 'setup' procedure
        ;     is to resize in memory. Everything past is returned to the OS.
        ;
        mov dx,offset cs:setup          ;reside all service routines
        mov ax,cs
        mov es,ax
        int 27h                         ;RESIDE/RETURN TO DOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; K2.10+
; Handle parsing the command line
;    Use CX as the character counter, SI as the parse character index.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
parse_cmdline:
        mov ch,0                ; use CX as character counter
        mov cl,ds:[0080h]       ; # option chars in CL
        cmp cl,0                ; no options specified?
        jnz pcl_cmdline2
        jmp pcl_done            ; done!
pcl_cmdline2:
        mov si,0081h            ; use SI as index to parse option chars
pcl_loop:
        ;
        ; Parsing loop - look for leading flag character
        ;
        mov al,ds:[si]          ; get next char
        cmp al,'-'              ; option flag?
        jz  pcl_option          ; handle -x option..
        cmp al,'/'              ; handle /x option..
        jz  pcl_option
pcl_next:
        inc si                  ; advance index
        loop pcl_loop           ; nothing we expected, skip whatever it is
        jmp pcl_done

pcl_option:
        ; Handle an option char - move to next parse position..
        dec cl
        inc si
        cmp cl,0                ; sneaky - with no argument?
        jne pcl_opt2

pcl_badargument:
        dosprint "A800DRV: ERROR: bad argument specified. (-h for help)"
        int 20h
pcl_opt2:
        mov al,ds:[si]          ; parse option character (a/i/h/?)

        ; Help?
        cmp al,'h'
        jnz pcl_nothelp
pcl_jmp_showhelp_exit:
        jmp pcl_showhelp_exit
        cmp al,'?'
        jz  pcl_jmp_showhelp_exit

pcl_nothelp:
        ; Set IRQ?
        cmp al,'i'
        jnz  pcl_not_setirq
        call pcl_setirq         ; handle setting irq
        jmp pcl_next            ; parse next parameter

pcl_not_setirq:
        ; Set base address?
        cmp  al,'b'
        jnz  pcl_unknown
        call pcl_setbaseaddr    ; handle setting base addr
        jmp  pcl_next           ; parse next parameter

pcl_unknown:
        ;
        ; Unknown command line flag? print error w/offending char
        ;
        dosprint_nocrlf "A800DRV: ERROR: unknown option '"
        mov   dl,al     ; offending character
        mov   ah,2      ; DOS print char
        int   21h
        dosprint "' (-h for help)"
        ;
        ; Terminate process with exit code of 1
        ;
        mov   ah,4ch    ; DOS: Terminate process with exit code
        mov   al,1      ; exit code
        int   21h       ; exit

pcl_showhelp_exit:
        ;
        ; Print help, exit
        ;
        mov dx,offset copyright
        mov ah,9        ; DOS: Print string
        int 21h
        mov dx,offset help
        mov ah,9        ; DOS: Print string
        int 21h
        ;
        ; Terminate process with exit code of 0
        ;
        mov ah,4ch      ; DOS: Terminate process with exit code
        mov al,0        ; exit code
        int 21h         ; exit
        
pcl_setirq:
        ;
        ; Handle "-i#", e.g. -i5
        ;
        dec cl
        inc si
        cmp cl,0
        jne pcl_setirq2
        jmp pcl_badargument
pcl_setirq2:
        ; Parse value as hex string
        push bx
          call parsehex           ; in: [si], out: ax=val, bx=cnt, [si] at eos
        pop bx
        cmp al,02h
        jl  pcl_setirq_range_err
        cmp al,07h
        jg  pcl_setirq_range_err
        call set_irq            ; set IRQ to value in AL
        ret                     ; return to pcl parser

;DEL;   mov al,ds:[si]          ; parse numeric digit that follows "-i"
;DEL;   cmp al,'2'
;DEL;   jl  pcl_setirq_range_err
;DEL;   cmp al,'7'
;DEL;   jg  pcl_setirq_range_err
;DEL;   ; Set the IRQ
;DEL;   and al,07h              ; CONVERT ASCII->BINARY (e.g. '2' -> 02h, etc)
;DEL;   call set_irq            ; set IRQ to value in AL
;DEL;   ret                     ; return to pcl parser

pcl_setirq_range_err:
        dosprint "A800DRV: ERROR: -i must be 2 thru 7"
        int 20h

;
; Set base address specified by user on command line
;
;     Parse hex string at ds:[si], make sure it's 200 - 3c0.
;
pcl_setbaseaddr:
        dec cl
        inc si                  ; move past "-b"
        cmp cl,0
        jne pcl_setbaseaddr2
        jmp pcl_badargument
pcl_setbaseaddr2:
        call parsehex
        ; Valid values
        cmp ax,0200h            ; minimum
        je  pcl_okbaseaddr
        cmp ax,0240h
        je  pcl_okbaseaddr
        cmp ax,0280h
        je  pcl_okbaseaddr
        cmp ax,02c0h
        je  pcl_okbaseaddr
        cmp ax,0300h
        je  pcl_okbaseaddr
        cmp ax,0340h
        je  pcl_okbaseaddr
        cmp ax,0380h
        je  pcl_okbaseaddr
        cmp ax,03c0h            ; maximum
        je  pcl_okbaseaddr
        jmp pcl_badbaseaddr

pcl_okbaseaddr:
        call set_baseaddr
        ret
pcl_badbaseaddr:
        dosprint "A800DRV: ERROR: -b#, where '#' must be one of:"
        dosprint "         200|240|280|2c0|300|340|380|3c0 (-h for help)"
        int 20h

pcl_done:
;DEBUG; dosprint_nocrlf "BaseAddr: "
;DEBUG; mov ax,ds:[base_0]
;DEBUG; call printhexword
;DEBUG; dosprint "h"
;DEBUG; dosprint_nocrlf "     IRQ: "
;DEBUG; mov ah,0
;DEBUG; mov al,ds:[irq_num]
;DEBUG; call printhexbyte
;DEBUG; dosprint "h"
;DEBUG; dosprint "PCL DONE - STOP."
;DEBUG; int 20h
        ret
;
; Print 16bit value in AX as 4 digit hex
;
printhexword:
        push ax
            mov al,ah   ; print MSB first
            call printhexbyte
        pop ax          ; restore to print LSB last
        jmp printhexbyte

;
; Print 8bit value in AL as a 2 digit hex byte
;    First prints MSN (Most Significant Nibble) followed by LSN.
;    Returns with AX trashed.
;
printhexbyte:
        push ax
        push cx
        push dx
          push ax
            mov cl,4
            shr al,cl             ; Move MSN -> low 4 bits for printing
            call phb_print_nibble ; print MSN (prints low 4 bits)
          pop ax                  ; restore byte
          call phb_print_nibble   ; fallthru to print LSN
        pop dx
        pop cx
        pop ax
        ret

phb_print_nibble:
        and al,0fh              ; focus on low 4 bits
        cmp al,09h              ; numeric hex?
        jle phb_num             ; print numeric hex
        add al,('A'-0ah)        ; convert to alpha hex
        jmp phb_print           ; print it
phb_num:
        add al,'0'              ; convert to numeric hex
phb_print:
        mov ah,2                ; DOS: Print char in DL
        mov dl,al               ; char to print
        int 21h
        ret
;
; Parse up to 16-bit hexadecimal string
; 1.0 erco 01/13/22
;
;     Understands upper or lowercase hex.
;     Parses up to 4 chars of hex max (e.g. FFFF)
;     Stops parsing at first non-hex char (0-9,A-F,a-f),
;     or after parsing 4 chars.
;
; In:
;     ds:[si] points to start of ascii hex string to parse.
;
; Out:
;     AX: the parsed hex as a 16-bit unsigned value
;     BX: # chars parsed
;     SI: pointing at next char PAST the parsed hex string
;
parsehex:
        push dx
        push cx
          mov bx,0
          mov dx,0
          mov cx,4       ; max count
pahx_loop:
          mov al,ds:[si]
          cmp al,'f'
          jg  pahx_done  ; non-hex char, stop
          cmp al,'a'     ; lowercase?
          jl  pahx_isupper
          and al,0dfh    ; convert a-f -> A-F, i.e. toupper
pahx_isupper:
          cmp al,'F'
          jg  pahx_done  ; non-hex char, stop
          cmp al,'A'
          jl pahx_isdigit
          sub al,37h     ; convert 'A' -> 0x0a, etc
          jmp pahx_converted
pahx_isdigit:
          ; See if char is a valid numeric char (0-9)
          cmp al,'0'
          jl  pahx_done
          cmp al,'9'
          jg  pahx_done
          sub al,'0'     ; convert '0' -> 0x00, etc
pahx_converted:
          ; shift existing bits in DX up one nibble
          shl dx,1
          shl dx,1
          shl dx,1
          shl dx,1
          or  dl,al      ; apply converted nibble to low 4 bits of DX
          inc si         ; move to parse next char
          inc bx         ; keep count of chars successfully parsed
          loop pahx_loop ; up to 4 chars max
pahx_done:
          mov ax,dx      ; return parsed value in AX
        pop cx
        pop dx
        ret

already db "A800 routines already resident",0dh,0ah,"$"

reside:
    db "A800 - Motor driver routines loaded (INT 99h)",0dh,0ah
    db "       Allocated 25,000 bytes for shared memory area.",0dh,0ah
    db "       When SCROLL LOCK on, counters will display.",0dh,0ah,0ah
    db "$"

copyright:
    db "A800DRV V4.10 01/19/22 - A800 Stepper Driver",0dh,0ah
    db "OPTICAL PRINTER CONTROL SYSTEM",0dh,0ah
    db "  (C) Copyright 1999,2007 Gregory Ercolano. "
    db "All rights reserved",0dh,0ah
    db "  (C) Copyright 2008,2022 Seriss Corporation. "
    db "All rights reserved",0dh,0ah
    db 0ah,"$"

help:
    db "Usage:",0dh,0ah
    db "    a800drv [-b300] [-i5] [-help]",0dh,0ah
    db 0ah
    db "Options:",0dh,0ah
    db 0ah
    db "  -b#  - Sets base address as 3 digit hex for the a800 card",0dh,0ah
    db "         e.g. -b300 for 0300h (default)",0dh,0ah
    db "         Should match jumper setting for JP1 on A800 card.",0dh,0ah
    db 0ah
    db "  -i#  - Sets IRQ, e.g. -i5 for IRQ5 (default)",0dh,0ah
    db "         '#' can be values 2 through 7 (default:5).",0dh,0ah
    db "         Should match jumper setting for JP2 on A800 card.",0dh,0ah
    db 0ah
    db "  -h   - Help (this info)",0dh,0ah
    db 0ah
    db "Caveats:",0dh,0ah
    db "    Only compatible with OPCS K2.10/TC and up.",0dh,0ah
    db "$"

cseg    ends
        end
