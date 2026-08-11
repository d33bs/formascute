# Storage Mount Benchmark: Directory Listing, Write, And Read Timing

A small, reproducible experiment comparing basic operation timing on two
network-mounted storage systems used by this project: DBMI Isilon (SMB) and
CURC PetaLibrary (sshfs). See `.agents/skills/isilon.md` and
`.agents/skills/petalibrary.md` for what these systems are and how to mount
them — this doc is just the benchmark methodology and results, kept separate
so the skills don't carry numbers that go stale.

**Data handling:** results below are aggregate timings only. No real share
name, allocation name, file name, or directory listing from either system
appears in this document — see the data handling rule in both skills for why.

**Location/network:** every number below was measured from one client
machine, physically in the greater Denver, Colorado area. Isilon access
requires CU Anschutz VPN when off-campus (confirmed reachable throughout);
whether VPN was active for the PetaLibrary/Alpine SSH leg specifically wasn't
independently confirmed. Neither figure generalizes to a different client
location, network path, on-campus/wired connection, or a different time of
day — re-run the script for a current number rather than trusting anything
here.

## Reproduce it yourself

```bash
./examples/benchmark_storage_mount.sh <mount-path> [size-mb]
```

The script:

1. Times listing the existing root of `<mount-path>`.
2. Creates a disposable, PID-suffixed test directory (`.benchmark-test-<pid>`)
   under it — never touches anything else.
3. Times listing that empty test dir.
4. Times a sequential write of a `[size-mb]`-sized (default `20`) zero-filled
   test file into it.
5. Times listing the dir again (now containing one file).
6. Times reading that file back immediately — labeled clearly as a
   cache-warm number, not a network read (see Known Limitation below).
7. Deletes the test file and directory and confirms removal, via a `trap` so
   cleanup runs even on failure.

It never unmounts anything and never touches content outside the test
directory it creates. Run it against any mounted path, e.g.:

```bash
./examples/benchmark_storage_mount.sh ~/mnt/<isilon-share> 20
./examples/benchmark_storage_mount.sh ~/mnt/alpine/active 20
```

## Known limitation: read timing isn't a real network number

Reading a file immediately after writing it is served from the local OS page
cache on both macOS SMB and sshfs, at multi-GB/s — this has nothing to do
with actual network/share read performance. The script still runs and
reports this step (so the timing loop stays simple and uniform across
storage systems), but the read number should not be cited as a real
performance figure without independently forcing a cold read.

**Do not try to force a cold read by unmounting and remounting the target on
the same client.** This was tried by hand once against a live Isilon mount
in this project (not via the script, which deliberately doesn't attempt it)
and caused a real incident:

- `umount` on the live share succeeded cleanly (no `Resource busy`).
- The immediate `mount_smbfs` remount — the exact same command, same
  login-keychain credential, that had mounted the share successfully minutes
  earlier — failed with `server rejected the connection: Authentication
  error`.
- Network/VPN reachability was independently confirmed fine via `ping`
  immediately after, and a second remount attempt failed the same way.
- This left the share **unmounted** for the rest of that session. Recovery
  required the human user to reconnect interactively (Finder → Connect to
  Server); no further non-interactive `mount_smbfs` retry succeeded, and
  retrying repeatedly was avoided to reduce account-lockout risk.
- Root cause unconfirmed. A plausible explanation: the original mount was
  established through a different flow (e.g. an interactive session at some
  point in the past) that isn't equivalent to a fresh non-interactive
  `mount_smbfs` call, even with a matching keychain entry present — not
  isolated further. Worth asking CU Anschutz IT/DBMI directly.

Because of this, the PetaLibrary side of this experiment (run in the same
session, minutes later) deliberately did not attempt the same unmount/remount
trick — not worth risking a second live mount the same way. If a genuinely
cold read number is needed, the safer approach is reading from a second,
independent client/host rather than disrupting a mount someone else may be
relying on.

## Results so far

Two runs against one live Isilon share, one run against one PetaLibrary
allocation subdirectory (via sshfs), same session unless noted.

| Step | Isilon (SMB), run 1 | Isilon (SMB), run 2 | PetaLibrary (sshfs) |
| --- | --- | --- | --- |
| List existing root | not measured | 3.55s | 1.44s |
| Create test dir | not measured | 0.32s | 0.75s |
| List empty test dir | not measured | 0.32s | 0.35s |
| Write 20MB | 0.81s (~26 MB/s) | 1.19s (~17.7 MB/s) | 1.25s (~16.8 MB/s) |
| Write 50MB | 1.98s (~26 MB/s) | not measured | not measured |
| List dir w/ 1 file | not measured | 0.36s | 0.65s |
| Read 20MB back | cache-inflated (multi-GB/s) | attempted forced cold read — broke the mount, see above | cache-inflated (~5 GB/s) |

Observations:

- Write throughput landed in a **~17-26 MB/s** range across both Isilon runs
  and the one PetaLibrary run — consistent enough to call
  low-tens-of-MB/s the right order of magnitude for this client/network path
  on both systems, but with enough spread (26 vs. 17.7 on Isilon alone,
  different times of day) that the exact number shouldn't be treated as
  fixed.
- Isilon's root-listing time (3.55s) was roughly 10x the empty-test-dir
  listing time (0.32s) in run 2, consistent with per-entry listing cost
  dominating fixed per-call overhead — but this is one measurement against
  one share with an unrecorded entry count, not a calibrated per-entry rate.
- PetaLibrary's root listing (1.44s) was faster than Isilon's (3.55s) in the
  same session, but the two roots almost certainly contain different numbers
  of entries, so this is not a valid protocol-level comparison — it would
  need matched entry counts (or listing the same-sized test dir on both,
  which the create/list-empty/list-with-1-file rows do give a cleaner
  comparison for: Isilon ~0.32-0.36s vs. PetaLibrary ~0.35-0.75s for
  directory-creation and small-listing operations).
- No valid read (network, cold-cache) number exists for either system yet.

## Open Questions

- What does a genuinely cold read look like on either system? Needs a second,
  independent client/host to avoid the unmount risk above.
- Why did the Isilon remount fail with `Authentication error` right after a
  clean `umount`, using the same command and keychain entry that worked
  moments before? Worth asking CU Anschutz IT/DBMI directly.
- What would these numbers look like from a client on-campus, off VPN
  entirely, or on VPN from a different geography? Everything so far is one
  client, one network path, one time window.
- A genuine second Isilon share (to compare against the one used here) and a
  larger/more representative directory-entry-count comparison across systems
  are both still open — repeat the script against each once available.
- Does this hold up under concurrent access, many-small-files patterns, or
  larger file sizes? This experiment only covers a single sequential
  20-50MB file against an otherwise-idle mount.
