# OW (Open With)

Manage macOS "Open With" defaults from the command line.

OW is a Swift CLI for changing the default app for a file type, setting per-file
Open With overrides, and applying filename-based rules across a directory tree.
It is built for the workflows where Finder's Get Info panel is too slow,
especially when you want repeatable defaults for project files, documents,
images, scripts, and extensionless files like `Makefile`.

## Features

- Set the default app for a file extension, such as `.pdf`, `.txt`, or `.jpg`.
- Set a per-file Open With override for one file or many piped files.
- Show the current default for an extension or file.
- List apps that can open a file type.
- Set defaults for built-in or custom groups like images, video, audio, code,
  documents, archives, or your own project-specific groups.
- Export and import portable `.owconfig` files for moving OW defaults and
  settings between Macs.
- Reset extension defaults or per-file overrides.
- Save rules for filename/glob patterns and apply them to a directory tree.
- Track OW-created per-file overrides so extension changes can warn about files
  that will not follow the new default.
- Warn about quarantined files, or opt in to clearing quarantine when setting
  per-file overrides.

## Requirements

- macOS 13 or newer
- Swift toolchain compatible with the package

## Install

Install with Homebrew:

```sh
brew tap marlonjames71/tap
brew install ow
```

Verify the install:

```sh
ow --version
ow --help
```

## Install From Source

Clone the repo and build with SwiftPM:

```sh
git clone https://github.com/marlonjames71/OW-CLI.git
cd OW-CLI
swift build -c release
```

Run the built binary:

```sh
.build/release/ow --help
```

For local use, copy or symlink `.build/release/ow` somewhere on your `PATH`.

## Release Automation

When a non-prerelease GitHub Release is published, OW runs a GitHub Actions
workflow that updates `marlonjames71/homebrew-tap` with the new release tarball
URL and SHA256.

The workflow requires a repository secret named `HOMEBREW_TAP_TOKEN` with write
access to the `marlonjames71/homebrew-tap` repository.

## Quick Start

Set the default app for a file type:

```sh
ow set .pdf Preview
ow set .txt CotEditor
ow set .jpg Preview
```

If you omit the app, OW opens an interactive picker:

```sh
ow set .pdf
```

Check a default:

```sh
ow get .pdf
ow get ~/Documents/report.pdf
```

List apps that can open a file type:

```sh
ow list .pdf
```

Set defaults for a group of related file types:

```sh
ow group images set Preview
ow group code set "Visual Studio Code"
```

Export your OW settings:

```sh
ow export
ow import ~/Downloads/ow_cli-20260426.owconfig --dry-run
```

Reset a default or remove a per-file override:

```sh
ow reset .pdf
ow reset ~/Documents/report.pdf
```

## Per-File Overrides

Pass a file path instead of an extension to set an override for only that file:

```sh
ow set ~/Documents/report.pdf Preview
```

Pipe files into `ow set` to apply the same override to many files:

```sh
find ~/Desktop -name "*.txt" | ow set TextEdit
find ~/projects -name Makefile | ow set "Visual Studio Code"
```

OW keeps a local index of overrides it creates at:

```text
~/.config/ow/file-overrides.json
```

That index lets OW warn you when a file-specific override will prevent a file
from following a newly changed extension default. OW also does a bounded scan of
common user folders to catch Finder-created or older unindexed overrides.

## Rules

Rules let you stamp per-file overrides based on filenames or glob patterns.

Add rules:

```sh
ow rule add Makefile "Visual Studio Code"
ow rule add "*.env" "Visual Studio Code"
```

Preview and apply rules:

```sh
ow rule apply ~/projects --dry-run
ow rule apply ~/projects
```

Manage rules:

```sh
ow rule list
ow rule remove Makefile
```

Rules are stored at:

```text
~/.config/ow/rules.json
```

## Groups

Groups apply one app to a set of related file extensions. They are a convenience
layer over `ow set .ext <app>` for each extension in the group.

List available groups:

```sh
ow group list
```

Show every group and its file types:

```sh
ow group show
```

Show the extensions in one group:

```sh
ow group images show
```

Set an app for a group:

```sh
ow group images set Preview
ow group video set IINA
ow group code set "Visual Studio Code"
```

Current built-in groups are `images`, `video`, `audio`, `code`, `documents`,
and `archives`.

Create an empty custom group, then add file types later:

```sh
ow group create design
ow group design append .psd .fig .sketch
```

You can also create a custom group with file types immediately:

```sh
ow group create design .psd .fig .sketch
```

Remove file types from a custom group:

```sh
ow group design remove .fig
```

Delete a custom group:

```sh
ow group delete design
```

Built-in groups can be customized locally:

```sh
ow group images append .psd .ai
ow group images remove .raw
```

For built-in groups, `append` and `remove` do not edit OW's shipped group
definitions. OW stores local additions and exclusions, then resolves the
effective group as:

```text
built-in extensions + appended extensions - removed extensions
```

Custom groups and built-in group customizations are stored at:

```text
~/.config/ow/groups.json
```

## Export And Import

OW can export portable settings to a JSON-backed `.owconfig` file:

```sh
ow export
```

If no path is provided and no default export path is configured, OW writes to
`~/Downloads` with an eight-digit date filename:

```text
ow_cli-20260426.owconfig
ow_cli-20260426-2.owconfig
```

Export to a directory or exact file path:

```sh
ow export -p ~/Desktop
ow export -p ~/Desktop/my-settings.owconfig
```

Choose export sections with names or aliases:

```sh
ow export --only defaults,groups
ow export --only d,g
ow export --exclude rules
ow export --exclude r
```

Sections:

```text
defaults            d
groups              g
rules               r
config              c
fileOverrideNotes   fon
```

`fileOverrideNotes` are included by default. OW filters out stale notes for
files that no longer exist before exporting. These notes are a checklist only;
they are not applied during import because per-file overrides are tied to local
file paths.

Import a config:

```sh
ow import ~/Downloads/ow_cli-20260426.owconfig
ow import ~/Downloads/ow_cli-20260426.owconfig --dry-run
```

Import applies extension defaults, groups, rules, and config when those
sections are present. After import, OW prints a summary of what was applied,
what could not be resolved, and any per-file override notes that were skipped.

## Quarantine Handling

macOS may attach quarantine metadata to files downloaded from browsers, Mail,
Messages, AirDrop, and other apps. Changing a file's Open With app can cause
macOS to reassess that quarantined file when you open it.

By default, OW warns when setting a per-file override on a quarantined file.

Clear quarantine for a single run:

```sh
find ~/Desktop -name "*.txt" | ow set --clear-quarantine TextEdit
```

Configure the default quarantine policy:

```sh
ow config quarantine warn
ow config quarantine clear
ow config quarantine ignore
```

Show the current config:

```sh
ow config
ow config quarantine
```

Set a default export path:

```sh
ow config export-path ~/Downloads
ow config export-path
```

Config is stored at:

```text
~/.config/ow/config.json
```

## Commands

```text
ow get <extension-or-file>
ow set [--clear-quarantine] <extension-or-file> [app]
ow list <extension>
ow reset [--all] [-y] <extensions-or-files...>
ow rule <add|list|remove|apply>
ow group list
ow group show
ow group create <name> [extensions...]
ow group delete <name>
ow group <name> <show|set|append|remove>
ow export [-p path] [--only sections] [--exclude sections]
ow import <path> [--dry-run]
ow config [quarantine [warn|clear|ignore]]
ow config export-path [path]
```

Run `ow --help` or `ow help <subcommand>` for command-specific help.

## Notes And Limitations

- Extension defaults are system-wide Launch Services settings.
- Per-file overrides are stored as `com.apple.LaunchServices.OpenWith`
  extended attributes on the file itself.
- Finder-created per-file overrides are not centrally indexed by macOS. OW can
  only index overrides it creates, plus perform a bounded scan for common cases.
- Some Launch Services changes may require Finder or Launch Services to refresh
  before every UI surface reflects the new default.
- OW stores user-managed state in `~/.config/ow`. Existing files from older
  releases in `~/Library/Application Support/ow` are still read as a fallback.

## How OW Compares To [duti](https://github.com/moretension/duti)

duti is a mature lower-level tool for setting Launch Services handlers by UTI
and URL scheme. It is powerful and scriptable, especially if you already know
the bundle IDs, UTIs, and roles you want to configure.

OW focuses on the Finder-style Open With workflow:

- use file extensions instead of requiring UTIs
- resolve apps by name or bundle ID
- set per-file Open With overrides
- track OW-created overrides
- warn when overrides prevent files from following a new default
- handle macOS quarantine behavior
- apply filename/glob rules across folders

If you need URL scheme handling or raw UTI-based bulk configuration, duti may be
a better fit. If you want an ergonomic CLI for file defaults and per-file Open
With behavior, OW is built for that.


## License

MIT

## Credit

[Claude Desktop](https://claude.com/download) and [Codex](https://openai.com/codex/) were used to help create this CLI.
