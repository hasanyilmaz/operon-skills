---
name: operon-cli
version: "1.1.0"
updated: "2026-08-04T17:44:34"
platforms:
  - claude
  - codex
---

# Operon CLI

## Purpose

Platform-specific reference skill packages for Operon CLI commands, typed
mutation routes, sealed plan lifecycle, operational limits, diagnostics, and
error recovery.

## Requirements

- Obsidian with Operon 3.x installed and enabled.
- A compatible Operon CLI installation, with the `operon` command available
  on the agent's shell `PATH`.
- For live Runtime operations, Obsidian must be running with the target vault
  open and Operon Runtime ready.

## Documentation

- Runtime model and public surfaces:
  [Operon Agent Runtime overview](https://operon.cc/docs/docs-118-operon-agent-runtime-overview/).
- Installation and verification:
  [Install and verify Operon CLI](https://operon.cc/docs/docs-119-install-and-verify-operon-cli/).

## Vault Installation Layout

Copy the contents of the selected platform package into the target Obsidian
vault. The platform directories and `.obsidian/` are siblings at the vault
root; do not place `.claude/` or `.codex/` inside `.obsidian/`:

```text
<vault-root>/
├── .obsidian/
├── .claude/skills/operon-cli/
└── .codex/skills/operon-cli/
```

Only the package for the platform being used is required. Run the agent with
the vault root as its working directory so vault-relative references resolve
correctly.

## Packages

- `claude/` — Complete Claude skill package.
- `codex/` — Complete Codex skill package.

## Maintenance

All available platform packages belong to this skill family and share this
family version. Platform-specific implementations may differ while preserving
the same user-facing purpose.

See [CHANGELOG.md](CHANGELOG.md) for version history.
