---
name: operon-tasks
version: "1.1.0"
updated: "2026-08-04T17:33:02"
platforms:
  - claude
  - codex
---

# Operon Tasks

## Purpose

Platform-specific skill packages for daily Operon task creation, lookup,
updates, lifecycle actions, reminders, pinning, timers, moves, conversions,
and deletion through the live Runtime.

## Requirements

- Obsidian with Operon 3.x installed and enabled.
- A compatible Operon CLI installation, with the `operon` command available
  on the agent's shell `PATH`.
- For live Runtime operations, Obsidian must be running with the target vault
  open and Operon Runtime ready.
- Bash and Python 3 for the bundled helper scripts.

## Documentation

- Installation and verification:
  [Install and verify Operon CLI](https://operon.cc/docs/docs-119-install-and-verify-operon-cli/).

## Vault Installation Layout

Copy the contents of the selected platform package into the target Obsidian
vault. The platform directories and `.obsidian/` are siblings at the vault
root; do not place `.claude/` or `.codex/` inside `.obsidian/`:

```text
<vault-root>/
├── .obsidian/
├── .claude/skills/operon-tasks/
└── .codex/skills/operon-tasks/
```

Only the package for the platform being used is required. Run the agent with
the vault root as its working directory so the skill's relative paths resolve
correctly.

## Packages

- `claude/` — Complete Claude skill package.
- `codex/` — Complete Codex skill package.

## Maintenance

All available platform packages belong to this skill family and share this
family version. Platform-specific implementations may differ while preserving
the same user-facing purpose.

See [CHANGELOG.md](CHANGELOG.md) for version history.
