# Operon Skills

Agent skills for working with Operon through the Operon CLI and live Agent
Runtime.

These packages teach compatible agents how to safely read and modify Operon
tasks, use typed mutation routes, work with sealed plans, and recover from
Runtime errors without manually editing task Markdown.

## Requirements

- Obsidian with Operon 3.x installed and enabled
- Operon CLI available as the `operon` command
- Obsidian running with the target vault open for live Runtime operations
- Bash and Python 3 for the bundled `operon-tasks` helper scripts

## Skills

| Skill | Use it for |
| --- | --- |
| [operon-tasks](./operon-tasks) | Daily task creation, lookup, updates, transitions, scheduling, reminders, timers, pinning, moves, conversions, and deletion through dictation-first workflows. |
| [operon-cli](./operon-cli) | Complete CLI reference, typed JSON mutations, task graphs, sealed plan mechanics, operational limits, diagnostics, and error recovery. |

## Which Skill Should I Use?

Start with `operon-tasks` for normal task work. It provides concise workflows
and maintained helper scripts for common operations.

Use `operon-cli` when you need:

- An exact command or flag reference
- Typed mutation inputs
- Parent-child task graphs
- Plan inspection, application, or recovery
- Destructive-operation rules
- Runtime limits and error handling

The two skills are complementary and can be installed together.

## Installation

Choose the package matching your agent platform and copy it into the target
Obsidian vault.

### Codex

```text
<vault-root>/
├── .obsidian/
└── .codex/
    └── skills/
        ├── operon-tasks/
        └── operon-cli/
```

Copy:

- `operon-tasks/codex/` to `.codex/skills/operon-tasks/`
- `operon-cli/codex/` to `.codex/skills/operon-cli/`

### Claude

```text
<vault-root>/
├── .obsidian/
└── .claude/
    └── skills/
        ├── operon-tasks/
        └── operon-cli/
```

Copy:

- `operon-tasks/claude/` to `.claude/skills/operon-tasks/`
- `operon-cli/claude/` to `.claude/skills/operon-cli/`

The agent directory and `.obsidian/` must be siblings at the vault root. Do not
place `.claude/` or `.codex/` inside `.obsidian/`.

Run the agent with the vault root as its working directory so relative paths
resolve correctly.

## Verify The Runtime

With Obsidian running and the target vault open:

```bash
operon health
```

The Runtime must report:

```text
Phase: ready
Admission: reads yes, writes yes
```

If the command is unavailable or the Runtime is not ready, follow the
installation and troubleshooting documentation before attempting writes.

## Safety Model

Operon skills use the live Runtime instead of directly editing task Markdown.
Writes pass through Operon's mutation pipeline so indexes, recurrence,
parent-task aggregates, reminders, trackers, and timestamps remain consistent.

Destructive operations retain their explicit confirmation gates, and uncertain
mutation results are recovered through the existing plan rather than retried as
new writes.

## Repository Structure

```text
operon-skills/
├── operon-tasks/
│   ├── MANIFEST.md
│   ├── claude/
│   └── codex/
├── operon-cli/
│   ├── MANIFEST.md
│   ├── claude/
│   └── codex/
├── LICENSE
└── README.md
```

Each skill family has one shared manifest and separate platform packages.
Platform implementations may differ where agent conventions require it while
preserving the same purpose and safety rules.

## Documentation

- [Operon Agent Runtime overview](https://operon.cc/docs/docs-118-operon-agent-runtime-overview/)
- [Install and verify Operon CLI](https://operon.cc/docs/docs-119-install-and-verify-operon-cli/)

## License

MIT License. See [LICENSE](./LICENSE).
