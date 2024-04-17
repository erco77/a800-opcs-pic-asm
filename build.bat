
"C:\Program Files (x86)\Microchip\MPLABX\v5.25\mpasmx\mpasmx.exe" ^
	-p18f24q10 ^
	-q ^
	-l"build/default/production/a800-opcs-asm.lst" ^
	-e"build/default/production/a800-opcs-asm.err" ^
	-o"build/default/production/a800-opcs-asm.o" ^
	"a800-opcs-asm.asm" 

"C:\Program Files (x86)\Microchip\MPLABX\v5.25\mpasmx\mplink.exe" ^
	-p18f24q10  ^
	-m"dist/default/production/a800-opcs-asm-REV-B.X.production.map" ^
	-z__MPLAB_BUILD=1  ^
	-o"dist/default/production/a800-opcs-asm-REV-B.X.production.cof" ^
	-i"foo.lst" ^
	build/default/production/a800-opcs-asm.o     
