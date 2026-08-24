	.syntax unified
	.thumb
	.text

	.word	0x20020000
	.word	__start

	.global	__start
  	.type 	__start, %function
__start:

	.equ GPIOA_LCKR,	0x4002001C @ Lock PA[14:13] for ST-LINK
	.equ RCC_AHB1ENR,  	0x40023830 @ PA : [0] = 1, PC : [2] = 1

	@ GPIOA, GPIOC clock on
	LDR   	r0, =RCC_AHB1ENR
	LDR   	r1, [r0]
	ORR	  	r1, r1, #(0x1<<2)|(0x1<<0)
	STR   	r1, [r0]

	@ Lock PA[14:13] pin configuration for ST-LINK
	LDR		r0, =GPIOA_LCKR
	LDR		r1, =(0x1<<16)|(0x3<<13)
	STR		r1, [r0]
	LDR		r1, =(0x0<<16)|(0x3<<13)
	STR		r1, [r0]
	LDR		r1, =(0x1<<16)|(0x3<<13)
	STR		r1, [r0]
	LDR		r1, [r0]

	@ CRT Startup Code

	.extern __RO_LIMIT__
	.extern __RW_BASE__
	.extern __ZI_BASE__
	.extern __ZI_LIMIT__

	LDR		r0, =__RO_LIMIT__
	LDR		r1, =__RW_BASE__
	LDR		r3, =__ZI_BASE__

	CMP		r0, r1
	BEQ		2f

1:
	CMP		r1, r3
	ITT		LO
	LDRLO	r2, [r0], #4
	STRLO	r2, [r1], #4
	BLO		1b

2:
	LDR		r1, =__ZI_LIMIT__
	MOV		r2, #0x0
3:
	CMP		r3, r1
	ITT		lo
	STRLO	r2, [r3], #4
	BLO		3b

	.extern Main

	BL		Main

	B		.
			
	.end
