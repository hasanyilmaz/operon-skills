# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0 - 2026-08-04

### Changed

- Updated the Claude and Codex packages to distinguish desktop IPC isolation
  from an unavailable Obsidian or Operon Runtime.
- Added one unchanged host-access retry for eligible read-only transport
  failures.
- Required mutation-capable commands to use host access from their first
  invocation and prohibited replay after an uncertain result.
- Aligned the canonical exit-code and error-registry guidance with the new
  execution-context policy.

## 1.0.0 - 2026-08-03

### Added

- Initial Operon CLI skill family with complete Claude and Codex packages.
