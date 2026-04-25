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
- Reset extension defaults or per-file overrides.
- Save rules for filename/glob patterns and apply them to a directory tree.
- Track OW-created per-file overrides so extension changes can warn about files
  that will not follow the new default.
- Warn about quarantined files, or opt in to clearing quarantine when setting
  per-file overrides.

## Requirements

- macOS 13 or newer
- Swift toolchain compatible with the package

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

Homebrew installation is planned.

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
~/Library/Application Support/ow/file-overrides.json
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
~/Library/Application Support/ow/rules.json
```

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

Config is stored at:

```text
~/Library/Application Support/ow/config.json
```

## Commands

```text
ow get <extension-or-file>
ow set [--clear-quarantine] <extension-or-file> [app]
ow list <extension>
ow reset [--all] [-y] <extensions-or-files...>
ow rule <add|list|remove|apply>
ow config [quarantine [warn|clear|ignore]]
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

## License

MIT
