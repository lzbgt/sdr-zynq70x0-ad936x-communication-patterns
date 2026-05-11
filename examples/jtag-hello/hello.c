#include <stdint.h>

#define UART1_BASE 0xE0001000u
#define UART_CR    (*(volatile uint32_t *)(UART1_BASE + 0x00u))
#define UART_SR    (*(volatile uint32_t *)(UART1_BASE + 0x2Cu))
#define UART_FIFO  (*(volatile uint32_t *)(UART1_BASE + 0x30u))

#define UART_CR_RXEN 0x00000004u
#define UART_CR_TXEN 0x00000010u
#define UART_SR_TXFULL 0x00000010u

static void uart_putc(char c)
{
    if (c == '\n') {
        uart_putc('\r');
    }
    while ((UART_SR & UART_SR_TXFULL) != 0u) {
    }
    UART_FIFO = (uint32_t)c;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s++);
    }
}

static void uart_puthex(uint32_t value)
{
    static const char hex[] = "0123456789abcdef";
    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(hex[(value >> shift) & 0xfu]);
    }
}

void main(void)
{
    UART_CR = UART_CR_RXEN | UART_CR_TXEN;

    uart_puts("\nSDR-Z203 JTAG hello\n");
    uart_puts("custom ARM ELF is running from DDR at ");
    uart_puthex(0x04000000u);
    uart_puts("\nUART1 base ");
    uart_puthex(UART1_BASE);
    uart_puts("\nno Linux, no QSPI write\n");

    for (;;) {
        __asm__ volatile("nop");
    }
}
