# Changelog

All notable changes to OW will be documented in this file.

The format follows the spirit of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses semantic versioning once releases begin.

## [Unreleased]

No unreleased changes.

## [0.1.0] - 2026-04-25

### Added

- Initial Swift CLI package for managing macOS Open With defaults.
- `ow set` for changing extension-wide defaults and setting per-file overrides.
- `ow get` for inspecting extension defaults and file-specific overrides.
- `ow list` for listing apps that can open a file type.
- `ow reset` for restoring extension defaults or removing per-file overrides.
- `ow rule` commands for saving and applying filename/glob-based per-file rules.
- `ow config` commands for viewing and updating OW preferences.
- Quarantine policy support with `warn`, `clear`, and `ignore` modes.
- `--clear-quarantine` flag for one-off quarantine removal when setting
  per-file overrides.
- Local index of OW-created per-file overrides.
- Bounded scanner for Finder-created or unindexed per-file overrides.
- Hidden `ow wow` command.
- Swift Testing coverage for UTI normalization, Launch Services plist handling,
  file override tracking, and config persistence.

### Changed

- Extension default handling writes Finder-shaped Launch Services entries for
  content types and filename extensions.
- Common file extensions resolve to canonical UTIs where the system APIs can
  otherwise return dynamic identifiers.

### Security

- Quarantine removal is explicit. OW warns by default and only removes
  quarantine metadata when requested by flag or persistent config.
