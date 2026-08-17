# Agent memory snapshot

Claude Code session-memory notes for this project, snapshotted here so they
travel with the repo (they normally live outside git under `~/.claude/`).

- `MEMORY.md` — the index (one line per note).
- `*.md` — one fact per file (frontmatter + body). Types: `user`, `feedback`,
  `project`, `reference`.

These span several efforts on this board (SG-TX, RDMA/ERNIC, PTP, RSS, WH FW),
not just the open-nic-shell RTL. They reflect what was true when written —
verify any file/flag/offset still exists before acting on it.

## Re-homing on another machine

To have Claude Code auto-load these as memory on a different host, copy them to
that machine's per-project memory dir (the path is derived from the project's
absolute path, so it differs per machine):

    ~/.claude/projects/<slugified-project-abs-path>/memory/

e.g. for `/home/alex/mpi-shfs/fpga/open-nic-shell` the slug is
`-home-alex-mpi-shfs-fpga-open-nic-shell`. If the checkout lives at a different
path there, the slug changes accordingly. Otherwise just read them here.

This is a manual snapshot — it is not kept in sync with the live `~/.claude`
memory automatically.
