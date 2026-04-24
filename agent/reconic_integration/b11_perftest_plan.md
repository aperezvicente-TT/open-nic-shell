# B11 — perftest Validation Plan for `onic_0100` (ERNIC v4.2)

**Status:** PLAN (not executable today). Blocked on B5/B6/B7/B8.
**Owner:** aperezvicente@tenstorrent.com
**Last touched:** 2026-04-23

This document is the *contract* for how we will validate the `onic.ko` +
`libonic` stack using the standard `perftest` suite (`ib_write_bw`,
`ib_read_bw`, `ib_send_bw`, `*_lat`) once the minimum viable verbs path
lands. It is not a runbook you can execute against today's tree.

---

## 1. Scope and non-goals

**In scope**

- Lab-scale, two-node validation over a single 100 GbE cable between
  `desktop-2` (FPGA, `onic_0100`) and `desktop` (Mellanox, `mlx5_0`).
- A small FPGA↔FPGA loopback matrix if a second FPGA is wired up.
- Exercising the RC verbs subset ERNIC v4.2 actually implements:
  WRITE / READ / SEND, single MR per QP, single SGE, no atomics, no SRQ.
- Producing reproducible throughput and latency numbers with a clear
  pre-flight checklist, counter deltas and dmesg diffs per run.

**Out of scope**

- Production sign-off. This plan yields *lab* pass/fail, not MTBF,
  burn-in, thermal or qualification data.
- Head-to-head benchmark against Mellanox. When Mellanox is the peer,
  its numbers are just context; this plan does not tune against them.
- Multi-rail, RoCE-LAG, GPUDirect, or any collective library.
- `ib_atomic_bw` — hardware lacks atomics. Any plan to support it
  requires an ERNIC rev, not a driver change.
- `ib_*` runs that rely on SRQ, XRC, DC, or UD above QP1 — not supported.

---

## 2. Test matrix

Two nodes, one cable. Shorthand:

- **M** = `desktop` / `mlx5_0` / `enp2s0np0` / 10.0.0.1
- **F** = `desktop-2` / `onic_0100` port 1 / `enp1s0d1` / 10.0.0.2

| # | Tool | Direction | QPs | MTU | Expect | Upstream block | Notes |
|---|------|-----------|-----|-----|--------|---------------|-------|
| 1 | `ib_write_bw`  | M → F | 1  | 4096 | 80–98 Gb/s  | B5/B6/B7/B8 | baseline one-sided WRITE, receiver passive |
| 2 | `ib_write_bw`  | F → M | 1  | 4096 | 70–95 Gb/s  | B5/B6/B7/B8 | stresses FPGA TX + MR fetch |
| 3 | `ib_read_bw`   | M → F | 1  | 4096 | 60–90 Gb/s  | B5/B6/B7/B8 | FPGA must respond to READ requests (read responder path) |
| 4 | `ib_send_bw`   | M ↔ F | 1  | 4096 | 60–90 Gb/s  | B5/B6/B7/B8 | two-sided — exercises RX descriptor posting on FPGA |
| 5 | `ib_write_lat` | M ↔ F | 1  | 256  | 2–5 µs p50, <15 µs p99 | B5/B6/B7/B8 | small payload latency |
| 6 | `ib_send_lat`  | M ↔ F | 1  | 256  | 2–6 µs p50 | B5/B6/B7/B8 | two-sided latency |
| 7 | `ib_write_bw`  | M → F | 4  | 4096 | 85–98 Gb/s  | B5/B6/B7/B8 | multi-QP — checks QP context isolation |
| 8 | `ib_write_bw`  | M → F | 16 | 4096 | 85–98 Gb/s  | B5/B6/B7/B8 | moderate fan-in, stays under 32-QP comfort ceiling |
| 9 | `ib_write_bw`  | M → F | 32 | 4096 | degraded, note behaviour | B5/B6/B7/B8 | stress; may trip one-shot CC |

Tests 1 and 5 are the minimum viable gate — if those pass, we declare
the verbs fast path "works at all".

Explicitly **not** in the matrix:

- `ib_atomic_bw` / `ib_atomic_lat` — no atomics in ERNIC v4.2.
- SRQ variants (`--use_srq`) — no SRQ.
- XRC (`-R` in some perftest builds) — no XRC.
- `--inline_size > 0` beyond whatever libonic exposes as device cap;
  plan assumes `inline_size=0` until libonic reports otherwise.
- `--use_event` (CQ event channel) is optional — deferred until B8
  completion confirms comp_channel wake-ups are reliable.

---

## 3. Per-test detailed recipes

Common assumptions for every test:

- FPGA side command prefix: `ib_* -d onic_0100 -i 1` (port 1 = CMAC1).
- Mellanox side command prefix: `ib_* -d mlx5_0 -i 1`.
- Default IB GID index for RoCEv2 on both — select explicitly with
  `-x <idx>` once `show_gids` output is captured in pre-flight.
- Peer IP is always the other node's 10.0.0.x address.
- Results file path: `results/b11/<test>_<date>.txt`.

### 3.1 Test 1 — `ib_write_bw`, Mellanox → FPGA

**Server (receiver, FPGA, desktop-2):**

```
ib_write_bw -d onic_0100 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F --report_gbits
```

**Client (sender, Mellanox, desktop):**

```
ib_write_bw -d mlx5_0 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F \
    --report_gbits 10.0.0.2
```

**Success criteria**

- Connection established, `ibv_modify_qp` returns 0 on both sides.
- 10^6 WRITEs complete with zero CQE errors.
- Reported BW in the 80–98 Gb/s band.
- `dmesg` diff on FPGA host: no WARN/OOPS, no `onic: ... err` lines.
- ERNIC `INSRRPKTCNT` delta ≈ number of WQEs drained; `ERRSTS` = 0.

**Failure modes and triage**

| Symptom | Likely cause | First move |
|---------|--------------|------------|
| `create_qp` returns `EOPNOTSUPP` | B5 not landed or libonic stub | Check `ibv_devinfo -v` QP caps |
| `modify_qp INIT→RTR` returns `EINVAL` | B6 state machine bug | Enable libonic debug, dump QPCONFi |
| `modify_qp RTR→RTS` returns `EINVAL` | SQ PSN / timer fields rejected | Check QPCONFi timeout/retry |
| First CQE returns error status | MR translation wrong | Check PDTi, DATBUFBA vs WQE LKEY |
| Hang (no CQEs, link UP) | ERNIC didn't DMA | `phase_f2_ernic_counters --delta 5` — is INSRRPKTCNT moving? |
| BW ≪ 80 Gb/s and stable | CC fired | `cat /sys/kernel/debug/.../ernic0/cnpschd_count`; STATQPi CC bit |
| BW fluctuates wildly | MSI-X coalescing or CQ pressure | Check completion-interrupt rate |

### 3.2 Test 2 — `ib_write_bw`, FPGA → Mellanox

Same flags, roles swapped. Server runs on Mellanox, client on FPGA.
This is the path that matters for "can we *drive* RDMA traffic out of
the FPGA?" and is the one we expect to be slower — ERNIC's SQ scheduler
is the bottleneck, not its RX responder.

### 3.3 Test 3 — `ib_read_bw`, Mellanox → FPGA

```
# FPGA (server — exposes target buffer for READ)
ib_read_bw -d onic_0100 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F --report_gbits

# Mellanox (client — issues READs)
ib_read_bw -d mlx5_0 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F \
    --report_gbits 10.0.0.2
```

Extra failure mode: READ responder may deliver fewer in-flight responses
than requested. Expect `max_rd_atomic` to be clamped by libonic to
whatever ERNIC advertises (commonly 1–4). If perftest's default
(`--out-reads 16`) exceeds this, expect it to be negotiated down; if
negotiation fails, add `--out-reads 4` on the client.

### 3.4 Test 4 — `ib_send_bw`, two-sided

```
# FPGA server
ib_send_bw -d onic_0100 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F --report_gbits
# Mellanox client
ib_send_bw -d mlx5_0 -i 1 -x 0 -m 4096 -q 1 -s 65536 -n 1000000 -F \
    --report_gbits 10.0.0.2
```

This is the first test that requires working `ibv_post_recv` on the
FPGA side. If RQ descriptor posting is broken, this hangs before any
completion; WRITE tests will *not* surface that bug.

### 3.5 Test 5 — `ib_write_lat`

```
ib_write_lat -d onic_0100 -i 1 -x 0 -m 256 -s 8 -n 100000 -F
ib_write_lat -d mlx5_0   -i 1 -x 0 -m 256 -s 8 -n 100000 -F 10.0.0.2
```

Expect p50 2–5 µs, p99 under ~15 µs. If p99 spikes above 100 µs, we have
a completion-interrupt coalescing bug, not an RDMA bug.

### 3.6 Test 6 — `ib_send_lat`

Same as 3.5 with `ib_send_lat`. Slightly higher latency due to two-sided
completion, still expect p50 under ~6 µs.

### 3.7 Tests 7/8/9 — multi-QP scaling

Same as Test 1 with `-q 4`, `-q 16`, `-q 32`. Watch CNP scheduler
counters (`cnpschd_count`). One-shot CC is expected to kick in somewhere
between 16 and 32 QPs if fan-in ever congests; if it does, aggregate
throughput will visibly drop to roughly half and *not* recover within
the run. Document the exact QP count at which it fires.

---

## 4. Pre-flight checklist

Run this top-to-bottom before every session. Any `NO` aborts.

- [ ] Latest `onic.ko` loaded: `lsmod | grep onic`, `modinfo onic | grep srcversion`.
- [ ] libonic at `/usr/lib/x86_64-linux-gnu/libibverbs/libonic-rdmav59.so`.
  - `ls -l /usr/lib/x86_64-linux-gnu/libibverbs/libonic-rdmav59.so`
  - `strings .../libonic-rdmav59.so | grep BUILD_SHA`
- [ ] `/etc/libibverbs.d/onic.driver` contains `driver onic`.
- [ ] `ibv_devices` lists `onic_0100`.
- [ ] `ibv_devinfo -d onic_0100` shows 2 ports, both `PORT_ACTIVE`,
      `link_layer: Ethernet`, phys `4096`.
- [ ] `ibv_devinfo -v -d onic_0100` shows at least one RoCE v2 GID
      (type `RoCE v2`) per port.
- [ ] `ip link show enp1s0d1` UP, MTU matches the row under test
      (expect 1500 minimum; 4200+ if testing 4096 path MTU).
- [ ] `ip addr show enp1s0d1` has 10.0.0.2/24.
- [ ] `ip addr show enp2s0np0` (peer) has 10.0.0.1/24.
- [ ] `ping -c 3 10.0.0.1` (from FPGA host) succeeds < 1 ms.
- [ ] `ibv_rc_pingpong -d onic_0100 -g 0` works against Mellanox peer
      running `ibv_rc_pingpong -d mlx5_0 -g 0 10.0.0.2` — this is the
      smoke test; if it fails, stop, fix, come back.
- [ ] ERNIC quiescent: `phase_f2_ernic_counters --delta 5` shows all
      counters flat (no stray traffic, no stale QP activity).
- [ ] `dmesg -c` drained on both hosts (clean slate for kernel-log diff).
- [ ] `numactl --hardware` noted, perftest pinned with `numactl -C <core>
      -m <node>` on both ends for latency tests.

---

## 5. Capturing results

For each run, store under `results/b11/<test>_<YYYYMMDD_HHMM>/`:

| Artifact | How |
|----------|-----|
| `invocation.txt` | The exact command lines, both sides |
| `env.txt` | `uname -a`, `modinfo onic \| head`, libonic SHA, `perftest --version` |
| `devinfo.txt` | `ibv_devinfo -v -d onic_0100` at start |
| `stdout.txt` | perftest output (both sides, labeled) |
| `dmesg.diff` | FPGA `dmesg` after session minus before |
| `ernic_counters.before` / `.after` | `phase_f2_ernic_counters` snapshots |
| `ethtool.before` / `.after` | `ethtool -S enp1s0d1` snapshots |
| `cnp.txt` | `cat /sys/kernel/debug/onic*/ernic0/cnpschd_count` before/after |

Result table template (one row per test, fill in on the day):

```
| Test | Date | Kernel SHA | libonic SHA | BW (Gb/s) | p50 (µs) | p99 (µs) | CQE errs | CC hits | Pass? |
```

---

## 6. Regression guardrails

After each successful perftest, all of the following must hold. Any
single failure blocks promotion of the change under test:

- `grep -c EOPNOTSUPP` in `/sys/kernel/debug/onic*/verbs_stubs` or the
  equivalent counter exposed by B4 — must be 0 for the verbs perftest
  actually invokes.
- Zero CQEs with status ≠ `IBV_WC_SUCCESS`.
- Zero kernel WARN/BUG/OOPS in the `dmesg` diff.
- Link on `enp1s0d1` still UP (`ip link show`), carrier not flapped.
- `ibv_devinfo -d onic_0100` still lists both ports ACTIVE.
- ERNIC `ERRSTS` register reads zero (no latched fatal bits).

---

## 7. Known limitations — set expectations

Lab perftest is expected to **pass within**:

- Throughput 80–100 Gb/s on 100 GbE for single-QP WRITE; slightly lower
  for READ and two-sided SEND.
- Latency p50 2–8 µs for small ops. Tail p99 under ~15 µs in a clean
  run. Above that, suspect interrupt coalescing or CQ polling bug,
  not the wire.
- Scaling clean from 1 to ~16 QPs. 16 to 32 is a grey zone. Beyond 32
  QPs, behaviour is uncharacterised and results are informational only.

Do **not** expect:

- Fairness under severe fan-in. One-shot CC drops window from 16 to 8
  on first ECN and never recovers; so long-running many-to-one tests
  will show sustained degraded throughput, not a brief dip.
- NCCL, UCX, libfabric default transports, MPI over verbs to "just
  work" even if all perftest rows pass. Those stacks touch verbs the
  plan deliberately avoids (SRQ, atomics, multi-MR, UD).
- Strict fairness between QPs under load — ERNIC's SQ scheduler is
  round-robin with no explicit weighting.
- Ordering guarantees beyond standard RC semantics. No IB-style
  memory window relaxations, no `IBV_SEND_FENCE` semantics beyond what
  vanilla RC provides.

If a passing perftest row is taken to mean "app X will work", that is a
misread of this plan. Use the B10 conformance matrix for that judgement.

---

## 8. Integration with B10 (conformance matrix)

Each perftest result feeds exactly one row of the B10 capability matrix:

| perftest row | B10 capability it exercises |
|--------------|-----------------------------|
| 1, 2, 7, 8, 9 | `IBV_WR_RDMA_WRITE`, multi-QP scaling |
| 3 | `IBV_WR_RDMA_READ` + responder path |
| 4 | `IBV_WR_SEND` / `ibv_post_recv` two-sided |
| 5, 6 | Latency tail behaviour (feeds the "interactive workload suitability" bullet) |

For each B10 row we want three data points:

1. Verb reachable (returns `0` from the libonic call).
2. Verb completes (CQE with SUCCESS).
3. Verb performs within the band in §7.

Anything that fails at (1) is a hole in B4/B5. Anything that fails at
(2) is a B6/B7/B8 bug. Anything that fails only at (3) goes into the
"works, with caveats" column of the B10 matrix — not a blocker for
capability advertisement, but a documented quirk.

Failures translated to errno contract for B10:

- Unsupported verb → `EOPNOTSUPP` at creation time, never at post time.
- Exceeding a cap (MR count > 1, SGE > 1, etc) → `EINVAL` at
  `reg_mr` / `post_send` with a logged reason string.
- Transient CQE error (e.g. remote access) → `IBV_WC_REM_ACCESS_ERR`
  on the CQ, QP moves to ERR, app sees what the spec says it should.

---

## 9. Open questions to resolve before running

- Exact `max_rd_atomic` / `max_dest_rd_atomic` libonic will report —
  affects whether Test 3 needs `--out-reads` override.
- Whether we expose a device `inline_size` > 0 in the first libonic
  release — affects latency Test 5/6 tuning.
- Whether MTU 4096 requires jumbo (`mtu 4200`) on the Ethernet
  interface or ERNIC accepts path MTU 4096 under a 1500-byte Ethernet
  MTU via fragmentation. Needs a one-shot experiment once B7 lands.
- Whether perftest's RDMA-CM mode (`-R`) is needed for Mellanox peer
  interop, or the legacy sockets-exchange default is sufficient.
  Prefer the default; fall back to `-R` only if GID exchange fails.
