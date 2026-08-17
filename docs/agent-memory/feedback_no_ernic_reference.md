---
name: dont-cite-ernic-as-good-architecture
description: "User has strong negative feelings about Xilinx ERNIC IP — don't hold it up as a production design model"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ed34fe36-50cb-41d4-bdaf-0045ca258750
---

Don't use ERNIC's architectural choices (descriptor model, AXI-MM bridge usage, BAR layout, etc.) as a positive reference when proposing solutions. The user characterizes it as "a shit IP" — strong language, prior frustration.

**Why:** The user has direct hands-on experience with ERNIC (see [[rdma-ernic-tier1b-in-progress]] — Tier 1b is currently paused on ERNIC's QDMA AXI-MM wiring with open design questions). They know its warts. Citing "ERNIC does X this way" lands as either condescending or wrong.

**How to apply:**
- When discussing open-nic-shell's QDMA/RDMA integration, refer to public production NIC architectures (Mellanox CX-6/7, NVIDIA BF, AMD Pensando, etc.) for *positive* references.
- ERNIC is fine to reference *neutrally* as "what's currently instantiated in this shell" — that's structural fact. Don't frame it as a model to emulate.
- If a design decision in our work ends up structurally similar to ERNIC's, that's coincidence, not endorsement — don't market it that way.
