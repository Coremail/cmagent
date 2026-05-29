# Auto-update

cmagent can update itself from GitHub Releases.

## Command

```sh
cmagent update
```

Checks for a newer release, downloads the correct binary for the current
platform, verifies the SHA-256 checksum, and replaces the running executable
in place. No restart is required — the new binary is active on the next run.

Add `--yes` to skip the confirmation prompt (useful in scripts):

```sh
cmagent update --yes
```

## Startup notice

On startup, cmagent checks a local cache and prints a one-line notice if a
newer version is available:

```
cmagent v0.2.0 is available. Run `cmagent update` to upgrade.
```

The cache is refreshed in the background at most once every 24 hours. There
is no network call on every startup.

## Platforms

Auto-update is supported on the three shipped platforms:

| Platform | Artifact |
|---|---|
| Linux x86\_64 | `cmagent-linux-x86_64.tar.gz` |
| macOS aarch64 | `cmagent-macos-aarch64.tar.gz` |
| Windows x86\_64 | `cmagent-windows-x86_64.zip` |

On unsupported platforms the command prints an error and links to the
[Releases](https://github.com/Coremail/cmagent/releases) page for manual
download.

## Windows note

Windows does not allow overwriting a running executable. cmagent handles this
by renaming the current binary before writing the new one. The replacement is
effective on the next invocation.
