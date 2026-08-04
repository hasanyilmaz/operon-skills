# Changelog

## 1.1.0 - 2026-08-04

### Changed

- Updated the Claude and Codex packages to distinguish desktop IPC isolation
  from an unavailable Obsidian or Operon Runtime.
- Added one unchanged host-access retry for eligible read-only transport
  failures.
- Required mutation-capable commands to use host access from their first
  invocation and prohibited replay after an uncertain result.

## 1.0.0 - 2026-08-03

### Added

- Initial Operon Tasks skill family with complete Claude and Codex packages.
