# Operon Skills

Agent skills for working with [Operon](https://github.com/hasanyilmaz/operon)
through the [Operon CLI](https://github.com/hasanyilmaz/operon-cli) and live
Agent Runtime.

These packages teach compatible agents how to safely read and modify Operon
tasks, use typed mutation routes, work with sealed plans, and recover from
Runtime errors without manually editing task Markdown.

## Operon Ecosystem

- [Operon](https://github.com/hasanyilmaz/operon) — Task management system for humans and agents in Obsidian.
- [Operon CLI](https://github.com/hasanyilmaz/operon-cli) — Official command-line client for the Operon Agent Runtime.
- [operon.cc](https://operon.cc) — Product website, installation guides, and documentation.

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

## Recommended Workspace Host Access Policy

Operon communicates with the running Obsidian desktop application through local
host IPC. In sandboxed agent environments, Obsidian and Operon Runtime may be
healthy even when a command cannot reach them.

The Operon skills include their own product-specific connection and recovery
rules, so this workspace-level policy is not a required dependency. Adding it
helps Codex or Claude choose the correct execution context before the first live
command and also benefits other skills that communicate with desktop
applications.

Add the following section to the vault-root `AGENTS.md` for Codex or
`CLAUDE.md` for Claude. If both agents are used, add it to both files. Merge the
section into an existing file; do not replace unrelated instructions.

```md
### Local Desktop Host And GUI IPC

Commands that communicate with a running desktop application through host
process discovery or OS-level IPC must run in a host-capable execution context.
This includes Unix sockets and application bridges on macOS/Linux, named pipes
and equivalent bridges on Windows, and wrapper scripts whose child process
performs the communication.

Grant host access to the outermost live command, including its wrapper. Keep
file-only, offline, configuration, schema, help, and cache-only operations
sandboxed when they do not require the running application.

For read-only operations:

- Run known live-desktop commands with host access from the start.
- A sandboxed command that returns a clear host-reachability or IPC-isolation
  error may be repeated once, unchanged, with host access.
- Treat a successful host retry as an execution-environment limitation. Diagnose
  the application, vault, plugin, or Runtime only if the host check also fails.
- Do not loop or repeatedly retry an unavailable transport.

For state-changing operations:

- Use host access from the first invocation; never use a sandbox mutation as a
  connectivity probe.
- Do not replay a command after an uncertain transport, timeout, or apply result.
  Follow the owning skill's recovery procedure.
- Host access does not authorize changes outside the user's request.

Use the narrowest permission for the required CLI or wrapper. Do not grant broad
host access to a shell or interpreter. Do not restart, reload, install,
reconfigure, or otherwise modify the host application solely because IPC is
unavailable without user authorization.
```

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
