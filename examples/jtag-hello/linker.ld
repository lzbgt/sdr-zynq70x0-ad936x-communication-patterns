ENTRY(_start)

MEMORY
{
    DDR (rwx) : ORIGIN = 0x04000000, LENGTH = 16M
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
    } > DDR

    .data : ALIGN(4)
    {
        *(.data*)
    } > DDR

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        __bss_end__ = .;
    } > DDR

    . = ALIGN(8);
    . = . + 0x4000;
    _stack_top = .;
}
