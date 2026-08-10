# PetaLibrary Skill

Use this note before mounting, transferring to/from, or reasoning about quotas
and access methods for CU Boulder/Anschutz's PetaLibrary storage service, as
used from a local machine or from Alpine. See `.agents/skills/alpine.md` for
general Alpine/SSH/Slurm knowledge — this file covers PetaLibrary specifically
and cross-references that file rather than repeating it.

## Current Position

- PetaLibrary is a CU Boulder Research Computing service for storing,
  archiving, and sharing research data — separate from Alpine's own
  `/scratch/alpine` and `/projects` filesystems, but reachable from the same
  login node. See What PetaLibrary Is.
- `/pl/active` is a real, listable, top-level directory on
  `login.rc.colorado.edu` containing per-group/per-project subdirectories
  (confirmed via plain `ssh`: 255 entries, mixed ownership/permissions). Which
  specific subdirectory under it belongs to this project has not been
  identified yet — see Open Questions.
- sshfs-mounting `/pl/active` from a local Mac is validated up through the SSH
  layer (connects, authenticates, lists real directory contents) but the
  actual FUSE mount has not yet completed successfully — see sshfs Access for
  the exact blocker and the command to finish it interactively.
- Don't reuse the `ssh-alpine` zsh alias for sshfs or any non-shell tool. It's
  a shell alias, not an SSH config entry, so tools that exec `ssh` directly
  (sshfs, rsync, some Globus/rclone flows) can't resolve it. Use the
  `~/.ssh/config` `Host alpine` entry created for this project instead — see
  sshfs Access.
- Globus and rclone are both real, CURC-documented access paths for Alpine
  data generally, and PetaLibrary's own allocation-types documentation lists
  Globus, rsync, and sftp as supported access methods for both Active and
  Archive tiers (Active also adds SMB). Neither has been validated against a
  PetaLibrary path specifically in this project yet — the source workshop
  material demos Globus against `/projects/<user>` and rclone against a
  OneDrive remote, not `/pl`. Treat both sections below as documented-but-
  unverified-for-PetaLibrary until tested. See Globus Access and rclone
  Access.

## What PetaLibrary Is

*Source: colorado.edu/rc/resources/petalibrary, curc.readthedocs.io
allocation_types page.*

PetaLibrary is a University of Colorado Boulder Research Computing service
for storage, archival, and sharing of research data, available as an
allocation (not provisioned automatically with an Alpine account). Requesting
one is a three-step process: review the allocation-tier documentation, submit
a request via a DocuSign form, then consult the user documentation to start
using it. Support: the RC Support Request Form, or `rc-help@colorado.edu`.

**Important default:** a single PetaLibrary allocation is one unprotected copy
of data with no backup by default — protection/backup is a property of which
tier you choose, not automatic.

## Allocation Tiers

*Source: curc.readthedocs.io allocation_types page. Costs are CU System,
FY27 rates as published there; re-check the live page before quoting a price,
since rates change by fiscal year.*

| Tier | Cost (CU System, FY27) | Compute node access | Login node access | Object/file limit | Redundancy | Compression | Access methods |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Active | $48/TB/yr | Yes (Alpine, Blanca, Open OnDemand), interactive NFS | Yes | None | Double parity RAID | lz4 | Globus, rsync, sftp, SMB |
| Archive | $28/TB/yr | No | Yes, interactive | 10,000 files/dirs per TB | Triple parity RAID | zstd | Globus, rsync, sftp |
| Active+Archive | $76/TB/yr | Yes (via the Active side) | Yes | None | Both tiers' protections | Both | Both tiers' methods |
| Archive+DR | $44/TB/yr | No | Yes | Same as Archive | Triple parity RAID + monthly offsite backup | zstd | Globus, rsync, sftp |

Notes:

- Active+Archive replicates data between the two tiers automatically via
  ZFS-snapshot-based replication, on a 15-minute cycle — not something you
  manage yourself.
- Archive+DR adds a monthly offsite backup copy of the archive allocation to a
  separate data center, on top of Archive's triple-parity protection.
- All tiers include monthly checksum validation and snapshot capability.
- External (non-CU) customers pay materially more (e.g. $115/TB/yr for
  Active-only, vs. $48 for CU System).
- **Archive tiers are not mountable from Alpine compute nodes.** If a
  Nextflow/Slurm job on `acpu` needs to read or write PetaLibrary data
  directly, it needs an Active or Active+Archive allocation, or the data needs
  to be staged to `/scratch/alpine` or `/projects` first via a login-node-side
  transfer (Globus/rsync/sftp/sshfs).

## sshfs Access

*Scope: general — this is the access method validated furthest in this
project so far, from a local macOS machine.*

### Why the `ssh-alpine` alias doesn't work for sshfs

`ssh-alpine` (defined in `~/.zshrc`) is a zsh alias wrapping:

```bash
ssh -i ~/.ssh/alpine dabu57888@xsede.org@login.rc.colorado.edu
```

sshfs execs the `ssh` binary directly — it never goes through zsh, so it
can't resolve shell aliases. Worse, the username itself contains a literal
`@` (`dabu57888@xsede.org`), which breaks the plain `user@host:path` sshfs
argument syntax. Two things that do **not** work around this, both tested:

- `sshfs ... -o User='dabu57888@xsede.org' ...` — rejected outright by this
  system's sshfs/macFUSE build with `fuse: unknown option(s): -o
  User=dabu57888@xsede.org`. `User` isn't in its recognized ssh-option
  passthrough list; don't assume ssh_config option names pass through
  sshfs `-o` flags just because they're valid for `ssh` itself.
- Percent-encoding the `@` in the remote spec
  (`dabu57888%40xsede.org@login.rc.colorado.edu:/pl/active`) — sshfs (version
  `3.7.5`, Homebrew/macFUSE build) passes the string to `ssh` **without**
  decoding it, so `ssh` receives the literal username
  `dabu57888%40xsede.org` and authentication fails with `Permission denied`.
  Don't rely on percent-encoding for this sshfs build.

### What works: an SSH config Host entry

Add a `Host` block to `~/.ssh/config` (created fresh for this project — none
existed before):

```
Host alpine
    HostName login.rc.colorado.edu
    User dabu57888@xsede.org
    IdentityFile ~/.ssh/alpine
```

`chmod 600 ~/.ssh/config` afterward. This makes both `ssh alpine` and
`sshfs alpine:/path ...` resolve correctly with no escaping needed, since the
odd username and identity file live in config instead of the command line.
Validated: `ssh -o BatchMode=yes alpine "echo ok"` succeeds, and
`ssh alpine "ls -la /pl/active"` lists real content (255 entries, mixed
ownership — some world-readable directories like `acuna`, `AMC_GenomicsCore_seqdata1`;
some group-restricted like `Anschutz_BDC` at `drwxrws---.`).

### Mount command and local convention

This machine already uses a `~/mnt/<name>` convention for other remote
mounts (`~/mnt/bandicoot` is an active `smbfs` mount; `~/mnt/koala`,
`~/mnt/alpine`, etc. exist as prepared-but-empty mount points). Use
`~/mnt/alpine` for PetaLibrary rather than inventing a new location:

```bash
mkdir -p ~/mnt/alpine   # already exists on this machine
sshfs alpine:/pl/active ~/mnt/alpine \
  -o reconnect \
  -o ServerAliveInterval=15 \
  -o volname=PetaLibrary
```

### Known blocker: FUSE mount doesn't register when launched non-interactively

Running the command above from a non-interactive/sandboxed subprocess (e.g. a
coding agent's shell tool) connects and authenticates successfully — `ps`
shows the `sshfs` process alive and sleeping — but the mount never appears in
`mount`/`df -h`, even with the sandbox disabled for that one call. The
macFUSE kernel extension was already loaded
(`io.macfuse.filesystems.macfuse.25 (5.1.3)` per `kmutil showloaded`), so
it's not a totally-missing-extension problem. This matches the known macFUSE
behavior of requiring a one-time interactive approval (System Settings →
Privacy & Security system-extension prompt, and/or Full Disk Access for the
terminal app actually running the command) that can only be granted from a
real interactive terminal session, not a tool-invoked subprocess.

**Fix:** run the `sshfs` command directly in an interactive terminal
(not through an agent/subprocess) so any macOS permission dialog reaches the
user, approve it if prompted, then re-run the same command. Once granted,
subsequent mounts from either context should succeed without re-prompting.

### To unmount

```bash
umount ~/mnt/alpine
# or, if that fails:
diskutil unmount ~/mnt/alpine
```

## Globus Access

*Scope: general Alpine data transfer. Documented from CU Anschutz's
"Globus and rclone data transfer on Alpine" workshop deck (Kevin Fotso,
2025-09-08) — not yet validated against a PetaLibrary path in this project;
the deck's own demo transfers into `/projects/<user>@xsede.org`, not `/pl`.*

Globus is a managed data-transfer platform (GridFTP for bulk transfer, HTTPS
for small downloads) that works "directly from your own storage system,"
including a laptop.

Setup flow from the deck:

1. Confirm Alpine access via Open OnDemand
   (`https://ondemand-rmacc.rc.colorado.edu`) → CILogon → identity provider
   **"ACCESS CI (XSEDE)"** → log in with **ACCESS-CI credentials, not CU
   Anschutz SSO** → DUO push.
2. Log into `https://www.globus.org/` → "Use your existing organizational
   login" → **"ACCESS CI (formerly XSEDE)"** → same ACCESS-CI credentials →
   DUO push recommended. Verify under Settings that the linked identity ends
   in `@access-ci.org`.
3. Install Globus Connect Personal locally
   (`https://docs.globus.org/globus-connect-personal/install/mac/` for
   macOS), log in, then create your own personal collection/endpoint (owner
   identity, collection name, description; optional "High Assurance" toggle
   for PHI/CUI data).
4. From the personal endpoint's "Open in File Manager" view: pick the local
   folder, "Transfer or Sync to...", then in the destination panel search
   Collection for **"CU Boulder Research Computing"** — the CURC-managed
   Globus collection (GCS, backed by `DTN23`, owner `colorado@globusid.org`).
   There is also a **"CU Boulder Research Computing ACCESS (Legacy - Do Not
   Use)"** collection — don't use it. Enter the destination path (the deck
   uses `/projects/<alpine-username>@xsede.org`; for PetaLibrary this would
   presumably be a `/pl/active/<allocation>` or `/pl/archive/<allocation>`
   path — unconfirmed, see Open Questions) and click Start.
5. To share with a collaborator who has no Alpine account, they install
   Globus locally and you set up a Globus guest collection (referenced by the
   deck, not walked through step by step).

**Recommendation from the deck, general Alpine guidance:** never use Open
OnDemand's web-based Upload/Download for files over 11GB — use Globus or
rclone instead.

## rclone Access

*Scope: general Alpine data transfer. Same source deck as Globus above — the
deck's rclone demo configures a `onedrive` remote type and never targets
`/pl`, so nothing here is PetaLibrary-specific yet. CURC's own rclone
reference (linked from the deck, not itself fetched for this skill):
`https://curc.readthedocs.io/en/latest/compute/data-transfer.html#rclone`.*

rclone is a CLI tool for managing files on cloud storage (transfer, backup,
restore), usable against many storage backends via `rclone config` remotes.

Local install (macOS, as shown in the deck):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install rclone
which rclone
```

On Alpine (compute node, not login node — get one via `acompile`):

```bash
acompile --ntasks=4 --time=12:00:00
module load rclone
rclone config
```

Interactive wizard (values shown are for the deck's OneDrive example; the
remote name/type would differ for a PetaLibrary-facing remote, e.g. `sftp` or
`webdav` against the PetaLibrary host — not yet determined for this project):

- `n` for new remote, give it a name
- storage type (deck used `onedrive`)
- leave `client_id`/`client_secret` blank unless required
- region `global` (backend-specific)
- **`n` for "Use auto config?"** — required since Alpine is headless; this
  prints an `rclone authorize "<remote>"` command to run locally instead
- on the local machine: `rclone authorize <remote>` opens a browser, log in,
  get a success page, then copy the full JSON token it prints back into
  Alpine's `config_token>` prompt
- finish any remote-specific prompts (e.g. `config_type`, drive selection)

Verify and use:

```bash
rclone listremotes
rclone ls <remote>:
rclone sync --progress <remote>:<source-path> <local-folder>
```

Can be wrapped in a batch job, e.g.:

```bash
#!/bin/bash
#SBATCH --job-name=rclone
#SBATCH --time=00:30:00
#SBATCH --output=rclone.out
#SBATCH --error=rclone.err
#SBATCH --qos=normal
#SBATCH --partition=amilan
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mail-type=BEGIN,FAIL,END
#SBATCH --mail-user=<user>@cuanschutz.edu

module load rclone
rclone sync --progress <remote>:<source-path> <local-folder>
```

Note the deck's example partition (`amilan`) is a predecessor/sibling
partition name, not `acpu` — see `.agents/skills/alpine.md` Slurm Defaults for
this project's current CPU partition/QOS naming and the note that Alpine
partition names have changed before.

**Security hygiene called out in the deck:** delete the rclone remote config
when done (`rclone config` → `d` → select remote → confirm) rather than
leaving a stored access token around.

## Important Failure Modes

- Do not use the `ssh-alpine` zsh alias as a host argument for sshfs, rsync,
  or any tool that execs `ssh` directly rather than going through a shell —
  it will not resolve. Use the `~/.ssh/config` `Host alpine` entry.
- Do not pass `-o User=...` to this system's sshfs build expecting it to
  reach `ssh` — it's rejected as an unrecognized FUSE option. Put `User` in
  `~/.ssh/config` instead.
- Do not percent-encode an `@`-containing username directly in an sshfs
  `user@host:path` argument and assume it will be decoded — this sshfs build
  (`3.7.5`) passes it through literally, causing a silent-looking
  `Permission denied` that has nothing to do with the SSH key itself.
- Do not run the actual `sshfs` mount command from a non-interactive
  agent/subprocess and expect it to succeed on first use — macFUSE's
  interactive approval step (system-extension prompt / Full Disk Access) can
  only be satisfied in a real interactive terminal session. A process that
  connects and authenticates but never shows up in `mount`/`df` is this
  failure mode, not an auth or config problem.
- Do not assume an Archive or Archive+DR PetaLibrary allocation can be
  mounted or read directly from an Alpine compute node (`acpu`) — those tiers
  are login-node-only. Stage data to `/scratch/alpine` or `/projects` first
  if a Slurm/Nextflow job needs it.
- Do not use Open OnDemand's web Upload/Download for anything over ~11GB —
  use Globus or rclone.

## Open Questions

- Which specific subdirectory under `/pl/active` (or `/pl/archive`) is this
  project's actual allocation? Not yet identified — `/pl/active` was mounted
  at its top level per explicit request, not a specific project path.
- Which PetaLibrary tier does this project actually hold (Active, Archive,
  Active+Archive, Archive+DR)? Determines whether direct compute-node access
  is possible at all, or whether every real run needs a staging step.
- What's the correct Globus destination path and rclone remote type/host for
  this project's specific PetaLibrary allocation? The source deck never
  targets `/pl` directly — both need a real test against this project's
  actual allocation before being treated as validated.
- Does CURC publish a PetaLibrary-specific rclone remote type (sftp? webdav?
  s3-compatible?) anywhere, as opposed to the generic cloud-storage examples
  in the workshop deck?
