#ifndef FIELDMESH_SIDECAR_ADDR_H
#define FIELDMESH_SIDECAR_ADDR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_SIDECAR_CTRL_BASE 0x43c00000u
#define FIELDMESH_SIDECAR_TX_DMA_BASE 0x43c10000u
#define FIELDMESH_SIDECAR_RX_DMA_BASE 0x43c20000u
#define FIELDMESH_SIDECAR_FIRMWARE_RING_BASE 0x43c30000u
#define FIELDMESH_SIDECAR_WINDOW_SIZE 0x00010000u

#define FIELDMESH_SIDECAR_CTRL_BASE_TEXT "0x43c00000"
#define FIELDMESH_SIDECAR_TX_DMA_BASE_TEXT "0x43c10000"
#define FIELDMESH_SIDECAR_RX_DMA_BASE_TEXT "0x43c20000"
#define FIELDMESH_SIDECAR_FIRMWARE_RING_BASE_TEXT "0x43c30000"
#define FIELDMESH_SIDECAR_WINDOW_SIZE_TEXT "0x10000"

#define FIELDMESH_SIDECAR_CTRL_NODE "fieldmesh-ctrl@43c00000"
#define FIELDMESH_SIDECAR_TX_DMA_NODE "dma@43c10000"
#define FIELDMESH_SIDECAR_RX_DMA_NODE "dma@43c20000"
#define FIELDMESH_SIDECAR_FIRMWARE_RING_NODE "fieldmesh-ring@43c30000"
#define FIELDMESH_SIDECAR_PACKET_NODE "fieldmesh-packet"

#define FIELDMESH_SIDECAR_CTRL_COMPAT "fieldmesh,sidecar-ctrl-1.0"
#define FIELDMESH_SIDECAR_DMA_COMPAT "adi,axi-dmac-1.00.a"
#define FIELDMESH_SIDECAR_FIRMWARE_RING_COMPAT "fieldmesh,firmware-ring-1.0"
#define FIELDMESH_SIDECAR_PACKET_COMPAT "fieldmesh,packet-sidecar-1.0"

static inline int fieldmesh_sidecar_addr_window_aligned(uint32_t base)
{
    return (base & (FIELDMESH_SIDECAR_WINDOW_SIZE - 1u)) == 0u;
}

static inline int fieldmesh_sidecar_addr_default_windows_disjoint(void)
{
    return FIELDMESH_SIDECAR_CTRL_BASE + FIELDMESH_SIDECAR_WINDOW_SIZE <=
               FIELDMESH_SIDECAR_TX_DMA_BASE &&
           FIELDMESH_SIDECAR_TX_DMA_BASE + FIELDMESH_SIDECAR_WINDOW_SIZE <=
               FIELDMESH_SIDECAR_RX_DMA_BASE &&
           FIELDMESH_SIDECAR_RX_DMA_BASE + FIELDMESH_SIDECAR_WINDOW_SIZE <=
               FIELDMESH_SIDECAR_FIRMWARE_RING_BASE;
}

static inline int fieldmesh_sidecar_addr_default_map_valid(void)
{
    return fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_CTRL_BASE) &&
           fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_TX_DMA_BASE) &&
           fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_RX_DMA_BASE) &&
           fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_FIRMWARE_RING_BASE) &&
           fieldmesh_sidecar_addr_default_windows_disjoint();
}

#ifdef __cplusplus
}
#endif

#endif
