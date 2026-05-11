    .section .vectors, "ax"
    .global _start
    .type _start, %function

_start:
    b reset
    b .
    b .
    b .
    b .
    b .
    b .
    b .

reset:
    cpsid if
    ldr sp, =_stack_top

    ldr r0, =__bss_start__
    ldr r1, =__bss_end__
    mov r2, #0
1:
    cmp r0, r1
    bhs 2f
    str r2, [r0], #4
    b 1b
2:
    bl main
3:
    wfe
    b 3b
