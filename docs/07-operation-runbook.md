# Chapter 7 — Operation & Bring-up Runbook

This chapter is the hands-on procedure to bring the card up from a freshly booted
host and prove both ports pass traffic. It reflects the exact, validated bench setup.

> **Convention for this chapter's examples**
>
> | Item | CMAC0 | CMAC1 |
> |------|-------|-------|
> | Local netdev | `enp1s0` (dev_port 0) | `enp1s0d1` (dev_port 1) |
> | Local IP | `10.99.0.1/24` | `10.99.1.1/24` |
> | Local MAC | `00:0a:35:b8:01:00` | `00:0a:35:b8:01:01` |
> | Remote peer | `.221` → `10.99.0.2` | `.223` → `10.99.1.2` |
> | Remote MAC | `10:70:fd:d6:9d:58` | `10:70:fd:d6:9d:20` |
> | Remote host / netdev | `alex@10.140.64.221` / `enp2s0np0` | `alex@10.140.64.223` / `enp2s0np0` |
>
> PCIe **BDF `0000:01:00.0`**, device `10ee:903f`, **single PF**.
> Netdev names and MACs are a function of the PCIe bus address — **they change if the
> card is moved to a different slot.** Always re-check with `ip -br link` after a move.

---

## 7.1 Prerequisites

- The **timing-closed bitstream is already flashed** to the card's SPI config flash
  (see Ch. 6). Confirm via the build-stamp register (Ch. 8 §8.2) — the validated
  clamp-fix image reads stamp `0x07010922`.
- The `onic` driver is built: `../open-nic-driver/onic.ko` exists (Ch. 5 §5.6).
- Passwordless sudo for the specific operations is installed via
  `tools/install_onic_sudoers.sh` → `/etc/sudoers.d/onic-test` (scoped to insmod of the
  exact `onic.ko` path, `rmmod onic`, `ip`, `dmesg`, `tcpdump`, `ernic-baremetal`, and
  `tee` for PCI rescan/reset).

## 7.2 Step 1 — Confirm the card enumerates

```bash
lspci -d 10ee: -nn                 # expect one 10ee:903f function at 01:00.0
lspci -s 01:00.0 -vvv | grep -i lnksta   # link speed/width
```

If the card is not present after a cold boot or a fresh flash, a PCIe rescan
(or a warm reboot) is usually enough — a full power cycle is only needed if the
flash was just written and the endpoint hasn't re-enumerated:

```bash
echo 1 | sudo tee /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 | sudo tee /sys/bus/pci/rescan
```

## 7.3 Step 2 — Load the driver

`insmod` **must** use the absolute path so it matches the NOPASSWD sudoers rule:

```bash
sudo rmmod onic 2>/dev/null
sudo insmod /home/alex/mpi-shfs/fpga/open-nic-driver/onic.ko
dmesg | tail -40        # expect: 1 PF probed, num_cmacs=2, two netdevs created
```

You should see **exactly two** netdevs created (not eight — if you see spurious
CMAC2–7 secondary-setup failures, you are running a pre-fix driver; see Ch. 5 §5.4).

```bash
ip -br link | grep -E 'enp1s0'      # enp1s0 (CMAC0) and enp1s0d1 (CMAC1)
cat /sys/class/net/enp1s0/dev_port    # -> 0
cat /sys/class/net/enp1s0d1/dev_port  # -> 1
```

## 7.4 Step 3 — Assign addresses (and defeat NetworkManager)

> ### ⚠️ The #1 bring-up gotcha: NetworkManager strips manual IPs
>
> On both the host and the remote peers, **NetworkManager will re-manage the interface
> and silently remove any manually-added IPv4** a short time after you set it. The
> symptom is a ping that suddenly reports **100 % loss** with the link **carrier still
> up** — because the source interface has no address. *This is not an FPGA fault.*
>
> The fix is to set the interface unmanaged **before** assigning the address, on every
> host involved.

**Local (host) side:**

```bash
for C in enp1s0 enp1s0d1; do sudo nmcli device set $C managed no; done
sudo ip addr flush dev enp1s0;   sudo ip addr add 10.99.0.1/24 dev enp1s0;   sudo ip link set enp1s0 up
sudo ip addr flush dev enp1s0d1; sudo ip addr add 10.99.1.1/24 dev enp1s0d1; sudo ip link set enp1s0d1 up
```

**Remote peers** (over ssh; each remote uses `enp2s0np0`):

```bash
ssh alex@10.140.64.221 'sudo nmcli device set enp2s0np0 managed no; \
  sudo ip addr flush dev enp2s0np0; sudo ip addr add 10.99.0.2/24 dev enp2s0np0; sudo ip link set enp2s0np0 up'
ssh alex@10.140.64.223 'sudo nmcli device set enp2s0np0 managed no; \
  sudo ip addr flush dev enp2s0np0; sudo ip addr add 10.99.1.2/24 dev enp2s0np0; sudo ip link set enp2s0np0 up'
```

## 7.5 Step 4 — Pin static neighbors (both directions)

Static ARP entries remove neighbor-discovery flakiness from the test. Use the **current**
MACs (they move with the slot):

```bash
# local -> remote
sudo ip neigh replace 10.99.0.2 lladdr 10:70:fd:d6:9d:58 dev enp1s0
sudo ip neigh replace 10.99.1.2 lladdr 10:70:fd:d6:9d:20 dev enp1s0d1
# remote -> local
ssh alex@10.140.64.221 'sudo ip neigh replace 10.99.0.1 lladdr 00:0a:35:b8:01:00 dev enp2s0np0'
ssh alex@10.140.64.223 'sudo ip neigh replace 10.99.1.1 lladdr 00:0a:35:b8:01:01 dev enp2s0np0'
```

## 7.6 Step 5 — Verify each port, then both concurrently

**Single port, both directions:**

```bash
ping -I enp1s0   -c 100 10.99.0.2      # CMAC0 -> .221
ping -I enp1s0d1 -c 100 10.99.1.2      # CMAC1 -> .223
```

**Both ports at once** (the real test — proves the demux/arbiter under simultaneous load):

```bash
ping -I enp1s0   -c 2000 -i 0.002 -W1 10.99.0.2 > /tmp/cc0.txt 2>&1 &
ping -I enp1s0d1 -c 2000 -i 0.002 -W1 10.99.1.2 > /tmp/cc1.txt 2>&1 &
wait
grep -E 'packets transmitted|rtt' /tmp/cc0.txt /tmp/cc1.txt
```

**Expected (validated) result:** `2000 received, 0% packet loss` on **both**, RTT
avg ≈ 0.13 ms (CMAC0) / 0.20 ms (CMAC1).

## 7.7 Step 6 — Throughput measurement (optional)

The iperf sources are at `/home/alex/mpi-shfs/fpga/iperf/src`. Run a server on each
remote peer and a client per port on the host:

```bash
# on each remote:
ssh alex@10.140.64.221 'iperf3 -s -1' &
ssh alex@10.140.64.223 'iperf3 -s -1' &
# on host:
iperf3 -c 10.99.0.2 -t 20 &      # CMAC0
iperf3 -c 10.99.1.2 -t 20 &      # CMAC1
wait
```

**Expected:** ≈ 20–22 Gbps/port. This is the **remote Mellanox peers' Gen3 ×4 PCIe
slot ceiling**, *not* an FPGA limit. TCP retransmits under this load are benign
congestion at that ceiling — see Ch. 8 §8.5 for the full evidence (CMAC error
counters and netdev drops are zero).

## 7.8 Verifying which CMAC is on which cable

The physical CMAC↔peer mapping depends on which QSFP cage each cable is in and **is not
guessable** — on this bench it turned out **inverted** from the naive assumption. The
authoritative method is the **per-CMAC RX diagnostic counters**: ping *one* peer only,
then read the two per-CMAC RX counters and see which one increments. Full procedure in
Ch. 8 §8.3.

## 7.9 Making the config survive reboots (optional hardening)

The manual steps above evaporate on reboot (NetworkManager, and the neighbor table).
To make the bring-up persistent, install per-interface connection profiles that pin the
static IP and set the interface unmanaged, on all three hosts. This is offered but not
yet applied — see the note at the end of Ch. 8. The driver itself can be made to load at
boot via a `modules-load.d` + `depmod`/`modprobe` install if desired.
