# OS Sandboxing (Security Layer 2)

cmagent runs every shell command and external-tool subprocess through an
**OS-level sandbox** -- the second of the four security layers (see
[security-model.md](security-model.md) for the full model). The sandbox is the
last line of defense if the application-policy layer (path rules, command
allowlist) is bypassed: even a command that slips past policy still executes
inside an isolated view of the filesystem.

Every filesystem-isolating backend enforces the same **contract**:

- the **workspace** (and any explicitly granted paths) is reachable at its
  **real absolute path**;
- **everything else is denied or hidden** -- your home directory, SSH keys,
  other users' files, the rest of the system;
- optionally, **network egress is blocked**.

A tool that bypasses the sandbox is a sandbox escape; all command execution is
routed through it.

## TL;DR -- which backend should I use?

- **Linux: do nothing.** The default `os_sandbox = "auto"` selects
  **Landlock**, which is built into the kernel (5.13+), needs no install, no
  daemon, and no special permissions. It is the recommended backend for almost
  everyone.
- **Need network blocking or a heavier boundary?** Use `bwrap` (bubblewrap) or
  a container runtime (`podman` preferred over `docker`).
- **macOS:** `bwrap` or a container runtime.
- **Windows:** no OS sandbox ships today; cmagent runs with application-policy
  isolation only (`noop`).

## Configuration

Set the backend in `~/.cmagent/config.toml`:

```toml
[security]
os_sandbox = "auto"   # auto | none | landlock | bwrap | firejail | podman | docker
```

| Value        | Meaning                                                            |
|--------------|-------------------------------------------------------------------|
| `auto`       | Detect and use the best **available** backend (default).          |
| `none`       | No OS sandbox (alias of `noop`). Application policy still applies. |
| `landlock`   | Force Linux Landlock LSM.                                          |
| `bwrap`      | Force bubblewrap.                                                  |
| `firejail`   | Force firejail.                                                    |
| `podman` / `docker` | Force that OCI container runtime.                          |

You can also set it interactively: **`cmagent config` -> `security`**. The
picker only offers backends that are **actually usable on this machine** (same
detection the runtime uses), so you can't pick one that won't work.

If you force a specific backend that isn't usable here, cmagent **falls back to
`noop`** (running WITHOUT OS isolation) and `cmagent doctor` warns you. Prefer
`auto` unless you have a reason to pin one.

### Auto-detect preference order

`auto` picks the first available backend, top to bottom:

- **Linux:** `landlock -> bwrap -> firejail -> OCI (podman > docker) -> noop`
- **macOS:** `bwrap -> OCI (podman > docker) -> noop`
- **Windows / other:** `noop`

"Available" is a **functional** check, not just "is the binary installed":
bwrap must actually create a user namespace, and a container runtime must answer
`info`. A backend that can't really sandbox is never auto-selected or offered in
the picker.

## Backend support matrix

| Backend          | Platform      | Isolation model                         | Default-deny FS | Needs on the host                                              | Can block network |
|------------------|---------------|-----------------------------------------|-----------------|---------------------------------------------------------------|-------------------|
| `landlock`       | Linux 5.13+   | Kernel LSM                              | yes             | nothing (in-kernel)                                           | no                |
| `bwrap`          | Linux / macOS | User-namespace (bubblewrap)            | yes             | `bubblewrap` pkg **and** unprivileged user namespaces allowed | yes               |
| `firejail`       | Linux         | Namespaces + seccomp (lighter)         | no (see below)  | `firejail` pkg (SUID)                                          | yes               |
| `podman`/`docker`| Linux / macOS | OCI container                          | yes             | a working runtime + a container image                         | yes               |
| `noop`           | all           | none (application policy only)         | n/a             | nothing                                                       | n/a               |

## Backends in detail

### Landlock (recommended on Linux)

A Linux Security Module built into the kernel since **5.13**. cmagent builds a
ruleset that grants read/exec on system directories and read-write on the
workspace, then `landlock_restrict_self` locks the process so any access outside
the ruleset is denied by the kernel.

- **Pros:** no install, no daemon, no elevated privileges, near-zero startup
  cost, deny-by-default. Best default for Linux.
- **Cons:** Linux 5.13+ only; filesystem isolation only (does **not** block
  network -- if you need that, use bwrap or a container).
- **Install:** none. Check your kernel: `uname -r` (>= 5.13) and that Landlock
  is enabled (`cmagent doctor` reports `Sandbox: landlock` when usable).
- **Permissions:** none required.

### Bubblewrap (`bwrap`)

The unprivileged user-namespace sandbox used by Flatpak. cmagent builds a fresh
mount namespace that bind-mounts only `/usr`, `/bin`, `/sbin`, the system
libraries, `/proc`, `/dev`, a private `/tmp`, and your workspace -- nothing else
exists inside.

- **Pros:** strong deny-by-default isolation; **can block network**
  (`sandbox_network = true` adds `--unshare-net`); no root/daemon when
  unprivileged user namespaces are allowed.
- **Cons:** depends on **unprivileged user namespaces**, which many hardened
  hosts disable. Because only a minimal system tree is mounted, tools that need
  files outside the workspace (e.g. custom certs in `/etc`) may not find them --
  grant them via `extra_dirs` (see [security-model.md](security-model.md)).
- **Install:**
  - Debian/Ubuntu: `sudo apt install bubblewrap`
  - Fedora: `sudo dnf install bubblewrap`
  - Arch: `sudo pacman -S bubblewrap`
- **Permissions:** the host must allow **unprivileged user namespaces**. On
  Ubuntu 23.10+/24.04 they are restricted by default
  (`kernel.apparmor_restrict_unprivileged_userns = 1`), and the shipped bwrap is
  not SUID, so every command fails with `setting up uid map: Permission denied`.
  See [Troubleshooting](#troubleshooting-bwrap-cant-create-a-user-namespace).

### Firejail

A SUID-root sandbox using namespaces + seccomp. cmagent keeps your workspace at
its real path and isolates `$HOME`: when the workspace is under `$HOME` it uses
`--whitelist=<workspace>` (a tmpfs covers home, the workspace is mounted back);
otherwise it uses a private empty home.

- **Pros:** easy to install; isolates your home directory; **can block network**
  (`--net=none`); works where unprivileged user namespaces are disabled (it is
  SUID).
- **Cons:** a **lighter** model -- it is **not** deny-by-default for the whole
  filesystem. It hides `$HOME` but leaves system paths like `/etc` readable, so
  it is weaker than Landlock/bwrap/containers for protecting non-home secrets.
  SUID-root sandboxes have a history of CVEs.
- **Install:**
  - Debian/Ubuntu: `sudo apt install firejail`
  - Fedora: `sudo dnf install firejail`
  - Arch: `sudo pacman -S firejail`
- **Permissions:** none beyond the package (it installs SUID-root).

### OCI containers (`podman` / `docker`)

Runs each command inside a throwaway container (`--rm`) built from a small image
(default `alpine:latest`), bind-mounting only the workspace. The container has
its own root filesystem, so the host is invisible by construction. cmagent also
applies memory / CPU / PID limits.

- **Pros:** strongest, most familiar isolation; deny-by-default; **can block
  network** (`--network=none`); resource limits.
- **Cons:** heaviest -- each command pays container start-up latency; needs a
  runtime and a pulled image; commands run inside the **image's** userland (e.g.
  Alpine/busybox), not your host's, so tools you rely on must exist in the
  image.
- **podman vs docker:** prefer **podman** -- it is rootless and daemonless, so
  it needs no background service and no privileged group. **docker** needs a
  running daemon and socket access (see permissions below).
- **Install:**
  - podman -- Debian/Ubuntu: `sudo apt install podman` (Fedora: `dnf install
    podman`; Arch: `pacman -S podman`)
  - docker -- Debian/Ubuntu: `sudo apt install docker.io` then
    `sudo systemctl enable --now docker`
- **Pull the image first** (avoids a slow first run; note podman and docker have
  separate image stores):
  - `podman pull alpine:latest` / `docker pull alpine:latest`
- **Permissions:**
  - **podman:** rootless, usually nothing extra.
  - **docker:** the user running cmagent must reach the docker socket -- add
    yourself to the `docker` group and **re-login**:
    `sudo usermod -aG docker $USER`. Note that docker-group membership is
    effectively root on the host; podman avoids this.

### Noop

No OS-level isolation -- only the application-policy layer (path rwx rules,
command allowlist, rate limits) applies. This is the Windows default and the
fallback when nothing else is available. Commands run with your normal user
access to the filesystem.

## Network isolation

By default the sandbox does **not** block network access
(`sandbox_network = false`). To cut off network egress inside the sandbox:

```toml
[security]
sandbox_network = true
```

This maps to `--unshare-net` (bwrap), `--net=none` (firejail), or
`--network=none` (containers). **Landlock cannot block network** -- if you need
network isolation, choose bwrap, firejail, or a container. A per-agent profile
can override this with its own `sandbox_network`.

## Container tuning

For `podman` / `docker`, these `[security]` keys control the container:

```toml
[security]
sandbox_container_runtime  = "auto"          # auto (podman > docker) | podman | docker
sandbox_container_image    = "alpine:latest" # any image with the tools you need
sandbox_container_memory_mb = 512
sandbox_container_cpu_limit  = 1.0           # cores
sandbox_container_pids_limit = 256
```

If your tasks need tools missing from Alpine, point `sandbox_container_image` at
a richer image (and pre-pull it).

## Verifying it works

`cmagent doctor` reports the active backend, the backends available on this
machine, and -- for every real backend -- runs a **live enforcement self-test**:
it writes a secret file in your home directory and confirms a sandboxed command
**cannot** read it.

```
Security
  + Sandbox: landlock - Linux Landlock LSM sandbox (kernel >= 5.13)
  i Sandbox available here: landlock, firejail, podman, noop (config: os_sandbox = "auto")
  + Sandbox enforcement: verified (blocked a read of a canary file outside the sandbox)
```

- `enforcement: verified` -- the sandbox blocked the out-of-sandbox read.
- (no enforcement line) -- `noop`, or the probe was inconclusive.
- A warning that your configured backend "is not usable here -- running WITHOUT
  OS-level isolation" means it fell back to `noop`; pick another backend.

To test a specific backend, set `os_sandbox` to it (or `cmagent config ->
security`) and run `cmagent doctor`. The container self-test starts a real
container, so that line is only slow when the active backend is podman/docker.

## Troubleshooting

### bwrap: "can't create a user namespace"

Symptom: `setting up uid map: Permission denied`, or `cmagent doctor` doesn't
list bwrap even though it's installed.

Cause: the host restricts **unprivileged user namespaces**. On Ubuntu
23.10+/24.04 this is on by default
(`kernel.apparmor_restrict_unprivileged_userns = 1`) and the packaged bwrap
isn't SUID.

Options:

1. **Use Landlock instead** (recommended) -- it needs no namespaces and is the
   Linux default.
2. **Per-binary AppArmor profile** (recommended if you specifically need bwrap
   in production) -- grant `userns` to just bwrap (or the cmagent binary) rather
   than relaxing the control globally.
3. **Relax the global control** (testing only -- weakens host hardening for
   *all* unprivileged processes; reverts on reboot):
   ```bash
   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0   # enable
   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=1   # revert
   ```
4. SUID bwrap -- possible but **discouraged** (SUID sandbox CVE history).

### docker: cmagent doesn't see it

Symptom: docker is installed but not in "Sandbox available here", and
`cmagent doctor` prints `docker is installed but 'docker info' failed ...`.

Causes and fixes:

- **Daemon not running:** `sudo systemctl enable --now docker`.
- **No socket permission:** the process running cmagent must be in the `docker`
  group. `sudo usermod -aG docker $USER`, then **log out and back in** (group
  membership only applies to new login sessions -- `newgrp`/`sg docker` work for
  a single shell). Reminder: the `docker` group grants root-equivalent access;
  podman avoids this.

### A forced backend silently became noop

If `os_sandbox` names a specific backend that isn't usable here, cmagent falls
back to `noop` and `cmagent doctor` warns:
`Configured os_sandbox = "..." is not usable here -- running WITHOUT OS-level
isolation`. Switch to a backend in the "available here" list, or use `auto`.

## Platform support

| Platform | Backends                                  | Default (`auto`) |
|----------|-------------------------------------------|------------------|
| Linux    | landlock, bwrap, firejail, podman, docker | landlock         |
| macOS    | bwrap, podman, docker                     | bwrap, else OCI  |
| Windows  | noop                                      | noop             |

Windows has no OS sandbox cmagent ships; it relies on the application-policy
layer. The deny-by-default `never`/unattended profiles still apply their path
and command rules everywhere, sandbox or not.

## See also

- [security-model.md](security-model.md) -- the full four-layer model, risk
  levels, permission prompts, and `extra_dirs` (granting extra paths into the
  sandbox).
- `cmagent doctor` -- live backend detection and the enforcement self-test.
- `cmagent config` -> `security` -- interactive backend picker.
