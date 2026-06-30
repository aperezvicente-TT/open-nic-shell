# Bring-up runbook — 1-PF / 2-CMAC pure-Ethernet (eth_2cmac_1pf)

Goal: flash the bitstream, then bring up **two `onic` netdevs on a single PF** (one per CMAC port) and smoke-test.

Artifacts (after the build completes):
- bit: `build/au200_eth_1pf_2cmac_qid/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit`
- mcs: `…/impl_1/open_nic_shell.mcs`
- driver: `../open-nic-driver` on branch `feature/eth-dual-netdev-1pf` → `onic.ko`

Expected topology: **1 PCIe PF** (`10ee:903f`), the driver spawns **2 netdevs** (`onic<bus>s<slot>f<func>c0` and `…c1`), CMAC0↔c0 (qid 0–63), CMAC1↔c1 (qid 64–127).

---

## 1. Flash the FPGA
Two options:

**A. JTAG .bit (fast, volatile — lost on power cycle; good for first test):**
```bash
cd open-nic-shell/script
./program_fpga.sh -p ../build/au200_eth_1pf_2cmac_qid/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit
```
After JTAG programming, the PCIe endpoint changes → the host must re-enumerate (warm reboot, or a PCIe hot-reset/rescan — see step 2). A warm reboot is the reliable path.

**B. .mcs to flash (persistent across power cycles):**
```bash
./program_fpga.sh -p ../build/au200_eth_1pf_2cmac_qid/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.mcs
# then COLD power-cycle the host so the FPGA boots from flash and PCIe enumerates it
```

## 2. Re-enumerate PCIe & confirm the single PF
```bash
# after warm reboot, or to rescan without reboot:
sudo sh -c 'echo 1 > /sys/bus/pci/devices/<BDF>/remove' 2>/dev/null   # if a stale device exists
sudo sh -c 'echo 1 > /sys/bus/pci/rescan'

lspci -d 10ee: -nn
#  EXPECT: exactly ONE Xilinx function ending in 903f  (1 PF).
#  If you see 903f AND 913f -> the bitstream is 2-PF, wrong build.
```

## 3. Build & load the driver
```bash
cd ../../open-nic-driver
git switch feature/eth-dual-netdev-1pf      # if not already on it
make -j$(nproc)
sudo insmod ./onic.ko                         # (debug: sudo insmod ./onic.ko debug_level=2)
dmesg | tail -40
#  EXPECT in dmesg: "device is a master PF", num_cmacs >= 2, two register_netdev OK,
#                   PTP init on both. No ERNIC/ib calls (stripped).
```

## 4. Verify the two netdevs (the key success criterion)
```bash
ip -br link | grep onic
#  EXPECT TWO interfaces: onic...c0 and onic...c1, distinct MACs (last byte differs).
ethtool -i onic...c0    # driver = onic
```
If only ONE appears → driver didn't see `num_cmacs>=2` (check dmesg) or the bitstream is single-CMAC.

## 5. Link up + smoke test
```bash
for d in onic...c0 onic...c1; do sudo ip link set $d up; done
ethtool onic...c0 | grep -i 'link detected'      # needs a cable/loopback/peer

# Assign IPs (point-to-point to a peer, or loop the two QSFP ports together):
sudo ip addr add 10.0.1.1/24 dev onic...c0
sudo ip addr add 10.0.2.1/24 dev onic...c1

# Traffic test (to a peer, or between the two looped ports in separate netns):
ping -I onic...c0 10.0.1.2
# throughput:
iperf3 -s &        # on peer / other port
iperf3 -c 10.0.1.2 -i 1 -t 10
```

## 6. qid-steering sanity (this build's whole point)
Confirm BOTH ports actually move host traffic (proves the qid demux/arbiter + EXT_QID):
```bash
# RX: traffic into CMAC1 must land on c1's queues, not c0.
ethtool -S onic...c1 | grep -iE 'rx_(packets|bytes)'   # should climb when c1 receives
ethtool -S onic...c0 | grep -iE 'tx_(packets|bytes)'   # should climb when c0 sends
# If c1 RX stays 0 while wire traffic arrives on port 2 -> C2H qid tagging / EXT_QID issue.
# If c1 TX never egresses port 2 -> H2C qid-demux issue.
```

## 7. (Optional) PTP
```bash
sudo ptp4l -i onic...c0 -m -2     # hardware timestamping rides the C2H tuser path
ethtool -T onic...c0              # confirm HW tx/rx timestamping capabilities
```

---

## Troubleshooting quick map
| Symptom | Likely cause |
|---|---|
| 0 netdevs, probe fails | driver/bitstream mismatch; check `lspci -d 10ee:` and dmesg |
| only c0 (1 netdev) | `num_cmacs<2` discovered, or single-CMAC bitstream |
| c1 RX = 0 | C2H qid tag / `EXT_QID` not steering (qdma_subsystem_function) |
| c1 TX no egress | H2C qid-demux (`qid[6]`) routing |
| both ports cross-talk / wrong port | qid range or `tuser_dst` mismatch |
| link never up | FEC/QSFP/cable; `RS_FEC_ENABLED` modparam |

Branches: shell `feature/eth-1pf-2cmac-qid`, driver `feature/eth-dual-netdev-1pf`.
