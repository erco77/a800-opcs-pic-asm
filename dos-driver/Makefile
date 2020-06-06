a800drv.com: a800drv.asm
	masm a800drv.asm a800drv.obj a800drv.lst;
	link a800drv;
	debug a800drv.exe < tocom
	del a800drv.com
	move aout.com a800drv.com
	del a800drv.exe
	@echo *** CREATED: a800drv.com
