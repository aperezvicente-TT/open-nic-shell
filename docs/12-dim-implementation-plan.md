# Chapter 12 — Implementation Plan: Adaptive Interrupt Moderation (DIM)

A plan to replace the static C2H completion-coalescing setting with the kernel's
Dynamic Interrupt Moderation library, so the driver picks thresholds from observed
traffic instead of requiring an operator to choose. Read Ch. 8 §8.8 for the
measurements that motivate it and the driver commits `f33fed9` / `48d6b68` for what
already exists.

> **Status: PLAN ONLY — nothing implemented.** Step 1 is a blocking investigation
> whose outcome decides the design; do not start Step 3 before it resolves.

## 12.1 Why

Coalescing turned out to be the single biggest performance factor in the RX path,
and the shipped default was pathological — an interrupt every 2 completions:

| `rx-frames` / `rx-usecs` | RX throughput |
|--------------------------|---------------|
| 2 / 0 (historical default) | 34.4 Gbit/s |
| 64 / 3 | **98.8 Gbit/s** |
| 128 / 5 | 98.2 Gbit/s |
| back to 2 / 0 | 37.1 Gbit/s |

But no static value is correct for every workload. High thresholds add latency and
raise the drop count under bursty load (11k-30k `DESC_RSP_DROP` per 10 s run at
`cnt_th` 64-192, versus ~1 at the default); low thresholds cost 3x throughput. The
ConnectX-7s in this bench sidestep the choice: `rx-frames 128 / rx-usecs 8` **with
`Adaptive RX: on`**. That is what DIM provides, and it is why `mlx5` and `bnxt_en`
use it rather than shipping a constant.

## 12.2 What already exists

| Piece | State |
|-------|-------|
| Threshold plumbing (`cnt_th`/`tmr_cnt` pool indices) | done — `cmpl_cnt_idx`/`cmpl_tmr_idx`, `onic_qdma_{get,set}_coalesce()` |
| `ethtool -c/-C` | done — `48d6b68`, rounds to pools and reads back post-rounding |
| Timer time-base | known — `C2H_INT_TIMER_TICK` = 25 user-clock cycles = **100 ns/tick** at 250 MHz, so the pool spans 0.1-20 µs |
| Kernel DIM | available — `CONFIG_DIMLIB=y`, `net_dim()` exported, `include/linux/dim.h` present |
| Measurement method | established — QDMA C2H counters in BAR0 (`0xA88`/`0xB10`/`0xB14`), NUMA-pinned iperf3, `ethtool -X` for queue count |

So this is not a from-scratch effort: the apply path and the measurement harness
are in place.

## 12.3 The blocking problem

`set_coalesce` currently applies a change by **bouncing the queues**
(`onic_stop_netdev` + `onic_open_netdev`), because the thresholds that govern
interrupt generation live in the per-queue completion **context**, written at queue
init. Measured with identical values: set live 35.0 Gbit/s, same values after a
re-init 98.5 Gbit/s.

**DIM changes profiles every few milliseconds. Bouncing the queues per change is
not an option** — it would flap the link continuously. So DIM cannot ship until
there is a way to apply a new threshold to a live queue.

## 12.4 Step 1 — resolve the apply mechanism (BLOCKING, S-M)

Three candidates, in order of preference:

**(a) The CMPT CIDX-carried fields.** `QDMA_OFFSET_DMAP_SEL_CMPL_CIDX` already
carries `counter_idx`, `timer_idx`, `trig_mode` on every update, and
`onic_set_completion_tail()` writes it on every NAPI completion. PG302 describes
these as updating the queue's configuration, which would make live application
free. My live test showed no throughput effect, but that test changed the module
variables mid-run without isolating other factors — **it is not conclusive**.
Retest deliberately:

- hold traffic at a fixed rate, toggle only the indices, and watch `irq/s` per
  queue (`/proc/interrupts`) rather than throughput, which is noisy;
- read back the completion context (via `libqdma`'s context dump) before and after
  to see whether the hardware copy actually changed;
- if `irq/s` moves but throughput does not, the mechanism works and something else
  (NAPI budget, refill) limits the gain.

If (a) works, DIM integration is straightforward and Step 2 is unnecessary.

**(b) Context update without teardown.** Check whether `libqdma` can rewrite just
the CMPT context of a live queue (`qdma_descq_context_write`-style), rather than the
full stop/start. Riskier: an in-flight completion during a context write is exactly
the kind of thing that produces the `CMPT_INV_Q_ERR` the code already warns about
(`onic_hardware.c`, prefetch/context ordering comment).

**(c) Software-side moderation.** Leave the hardware thresholds fixed at a
throughput-friendly value and have DIM modulate *when the driver re-arms* the
interrupt — the `irq_arm` argument to `onic_set_completion_tail()`, optionally with
an `hrtimer` deferral. Entirely in driver control, so it always works, at the cost
of not using the hardware's own moderation. Note the error path already does
something similar (`ERROR_REARM_DELAY_MS`), so the pattern exists in-tree.

**Deliverable:** a one-page note recording which mechanism applies a live change,
with the `irq/s` evidence. Everything below assumes one of them works.

## 12.5 Step 2 — per-queue thresholds (S)

DIM state is per queue; the current indices are **module-global**. Required:

- move the active indices into `struct onic_rx_queue` (`onic.h:151`), keeping the
  module parameters as the *initial* value only;
- make `onic_set_completion_tail()` take the queue's own indices;
- keep `ethtool -C` semantics as "set all queues", which is what `-C` means without
  `-Q`.

## 12.6 Step 3 — DIM integration (M)

Per RX queue, add:

```c
struct dim      dim;            /* kernel DIM state */
u16             dim_event_ctr;  /* interrupt counter for dim_update_sample() */
u64             dim_packets;    /* cumulative, for the sample */
u64             dim_bytes;
bool            dim_enabled;    /* ethtool adaptive-rx */
```

In `onic_rx_poll()` (`onic_netdev.c:370`), after `napi_complete_done()` at `:591`
and before/with the existing `onic_set_completion_tail()` at `:592`:

```c
if (q->dim_enabled && work < budget) {
        struct dim_sample sample;

        dim_update_sample(q->dim_event_ctr, q->dim_packets, q->dim_bytes, &sample);
        net_dim(&q->dim, sample);
}
```

Apply new profiles from a work item (DIM's contract is that the consumer applies
asynchronously and then resets the state):

```c
static void onic_dim_work(struct work_struct *w)
{
        struct dim *dim = container_of(w, struct dim, work);
        struct onic_rx_queue *q = container_of(dim, struct onic_rx_queue, dim);
        struct dim_cq_moder moder =
                net_dim_get_rx_moderation(dim->mode, dim->profile_ix);

        onic_queue_set_coalesce(q, moder.pkts, moder.usec);   /* Step 1 mechanism */
        dim->state = DIM_START_MEASURE;
}
```

Notes on the translation:

- `struct dim_cq_moder` gives `usec` and `pkts`; both must be rounded to the QDMA
  pools with the existing `onic_pool_nearest()`. DIM's default RX profiles use
  periods of roughly 1-256 µs, and our timer pool tops out at **20 µs**
  (200 ticks × 100 ns) — so the upper profiles will clamp. Worth stating in the
  commit rather than discovering later; if the clamp hurts, raising
  `C2H_INT_TIMER_TICK` extends the range at the cost of resolution.
- Use `DIM_CQ_PERIOD_MODE_START_FROM_CQE` unless measurement says otherwise: our
  timer threshold is evaluated against pending completions, which matches
  CQE-start semantics more closely than EQE.
- `dim_packets`/`dim_bytes` need to be the queue's cumulative counters; the per-queue
  stats block in `struct onic_rx_queue` already exists (`onic.h:165`) — reuse it
  rather than adding parallel counters.

## 12.7 Step 4 — ethtool surface (S)

- advertise `ETHTOOL_COALESCE_USE_ADAPTIVE_RX` in `supported_coalesce_params`;
- `get_coalesce`: report `ec->use_adaptive_rx_coalesce` plus the currently active
  (DIM-chosen) values, so `ethtool -c` shows what the hardware is doing right now;
- `set_coalesce`: `adaptive-rx on` enables DIM; `adaptive-rx off` freezes the
  current profile and honours explicit `rx-frames`/`rx-usecs`;
- an explicit `rx-frames`/`rx-usecs` while adaptive is on should either turn
  adaptive off (mlx5 behaviour) or be rejected — pick one and document it.

## 12.8 Step 5 — verification (M)

DIM's whole point is that both regimes work, so **both must be measured**; the
existing harness only covers throughput.

| Test | Instrument | Expectation |
|------|-----------|-------------|
| Saturating RX, 14 queues | iperf3 `-P 8`, NUMA-pinned, MTU 9000 | ≥ 95 Gbit/s, i.e. matches static 64/3 |
| Idle/sparse latency | `ping -c 2000 -i 0.005`, and a TCP_RR-style round-trip | ≈ the 0.097-0.118 ms measured at the *default* coalescing, not the high-threshold latency |
| Ramp | step offered load 1 → 100 Gbit/s | profile index moves; no oscillation |
| Drops | `DESC_RSP_DROP_ACCEPTED` (BAR0 `0xB10`) | ≤ static-64/3 numbers |
| Errors | `DESC_RSP_ERR_ACCEPTED` (`0xB14`) | stays 0 |
| Profile churn | count `onic_dim_work` invocations | bounded; thrash is a bug |

Regression guard: with `adaptive-rx off` the static path must still reproduce
34.4 / 98.8 Gbit/s at 2/0 and 64/3.

## 12.9 Risks

- **Apply cost.** If Step 1 lands on (b) or (c), every profile change has a cost;
  DIM assumes it is cheap. Rate-limit profile application if so.
- **Pool coarseness.** 16 counter values and 16 timer values, timer capped at
  20 µs. DIM may ask for values we cannot express; rounding could make adjacent
  profiles identical and confuse the algorithm's feedback.
- **Interaction with the error re-arm work.** `ERROR_REARM_DELAY_MS` already defers
  re-arming after a C2H error; if Step 1 chooses (c), the two mechanisms both
  control `irq_arm` and must not fight.
- **Latency regression risk on the sparse side** is the one users notice. Measure it
  before claiming success, and keep §12.8's idle-latency row as a gate.

## 12.10 Effort

| Step | Effort |
|------|--------|
| 1 — resolve apply mechanism (blocking) | S-M |
| 2 — per-queue thresholds | S |
| 3 — DIM integration | M |
| 4 — ethtool surface | S |
| 5 — verification both regimes | M |

**Overall ≈ M**, dominated by Step 1's unknown and Step 5's latency work. If Step 1
resolves to (a), the whole thing is comfortably M; if it resolves to (c), reconsider
whether static defaults plus a documented `ethtool -C` recommendation is the better
value for this driver.

## 12.11 Interim recommendation, independent of DIM

Whatever happens above, the shipped default should not stay at 2 frames / 0 µs.
Choosing e.g. **64 / 3** (a 2.9x throughput change) is a one-line default with the
data in §12.1 behind it — worth doing before, and regardless of, DIM. That decision
is deliberately left open: it trades a few microseconds of latency and a higher drop
count under bursty load for near-line-rate throughput.
