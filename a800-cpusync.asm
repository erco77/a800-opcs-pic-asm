;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; FUNCTION
;     Synchronize the two A800 processors
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CpuSync:
#if BUILD_CPU == 1
    ;                           #    
    ;  ####   #####   #    #   ##    
    ; #    #  #    #  #    #  # #    
    ; #       #    #  #    #    #    
    ; #       #####   #    #    #    
    ; #    #  #       #    #    #    
    ;  ####   #        ####   #####  
    ;

    ; // tell cpu2 we're syncing
    ; SET_SYNC = 1;
    bsf		SET_SYNC	; set sync (LATA,5)

    ; // Wait for cpu2 to ack sync
    ; while ( !IS_ACK ) { }
cs_loop1:
    btfss	IS_ACK		; Bit Test File, Skip If Set: (PORTA,6)==0?
    goto	cs_loop1	; clr? wait until set

    ; // drop sync to cpu2 (which waits for this)
    ; SET_SYNC = 0;
    bcf		SET_SYNC	; un-sync (LATA,5)

    ; // Wait for cpu2 to un-ack
    ; while ( IS_ACK ) { }
cs_loop2:
    btfsc	IS_ACK		; Bit Test File, Skip If Clear: (PORTA,6)==0?
    goto	cs_loop2	; set? wait until clear
    return

#else
    ;                         #####  
    ;  ####   #####   #    # #     # 
    ; #    #  #    #  #    #       # 
    ; #       #    #  #    #  #####  
    ; #       #####   #    # #       
    ; #    #  #       #    # #       
    ;  ####   #        ####  ####### 
    ;
    ; while (!IS_SYNC) { } // Wait for cpu1 to send us sync signal
cs_loop1:
    btfss	IS_SYNC		; Bit Test File, Skip If Set: (PORTA,6)==1?
    goto	cs_loop1	; clr? wait until set

    ; SET_ACK = 1; // ack sync signal
    bsf		SET_ACK		; ack (LATA,5) = 1

    ; while (IS_SYNC) { } // wait for cpu1 to drop sync
cs_loop2:
    btfsc	IS_SYNC		; Bit Test File, Skip If Clear: (PORTA,6)==0?
    goto	cs_loop2	; set? wait until clear

    ; SET_ACK = 0; // un-ack
    bcf		SET_ACK		; un-ack (LATA,5)=0
    return
#endif


