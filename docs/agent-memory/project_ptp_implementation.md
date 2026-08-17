---
name: PTP IEEE 1588 timestamping implementation
description: PTP hardware timestamping added to OpenNIC shell and driver using Corundum modules; register map at BAR2+0x18000
type: project
---

PTP IEEE 1588 hardware timestamping has been integrated into both open-nic-shell (FPGA) and open-nic-driver.

**Why:** Enable hardware-precision timestamping for latency measurement and PTP clock sync via ptp4l.

**How to apply:**
- FPGA: src/ptp_subsystem/ contains all PTP RTL (Corundum modules + custom register/subsystem wrappers)
- Driver: onic_ptp.c/.h implements PTP clock ops, register map at BAR2+0x18000
- Address map: Global PTP regs at 0x18000, per-port TX TS at 0x19000/0x1A000
- CDC approach: Sideband async FIFOs in packet_adapter for timestamp/tag crossing (322MHz<->250MHz)
- tuser widening: RX carries 80-bit PTP TS, TX carries 16-bit PTP tag as separate sideband signals alongside existing tuser_err
- QDMA descriptor integration for RX timestamps not yet done (timestamps reach box_250mhz but are not in QDMA completion descriptors)
