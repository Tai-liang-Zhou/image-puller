# Spec: retag-push.sh — batch load / retag / push of docker image tars

Label: `ready-for-agent`

## Problem Statement

I receive directories full of docker image tar files (produced by `docker save`) whose images are named under a source registry path such as `registry.example.com/team/foo:1.2.3`. I need all of them in our Harbor under a single project, with a flat name (`harbor.example.com/myproject/foo:1.2.3`). Doing this by hand means running `docker load`, reading the printed name, typing a `docker tag`, and a `docker push` for every file, and it is easy to mistype a tag or lose track of which files already went through.

## Solution

A single bash script, `retag-push.sh`, run as:

```
./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
```

It scans the top level of `<tar_dir>` for `*.tar`, `*.tar.gz`, `*.tgz`; loads each into docker; reads the image name(s) the load produced; rewrites each to `<target_prefix>/<last path segment>:<tag>`; tags and pushes. Every tar is processed independently — a failure is recorded and the run continues. At the end a summary lists succeeded and failed tars, and the exit code is non-zero if anything failed. `--dry-run` prints the full mapping without touching docker. `--cleanup` removes the local tags after a successful push.

## User Stories

1. As an operator, I want to point the script at a directory and a target prefix, so that every image tar in it is loaded, retagged and pushed with one command.
2. As an operator, I want the script to scan only the top level of the directory, so that I control exactly which files are included by where I put them.
3. As an operator, I want `.tar`, `.tar.gz` and `.tgz` all picked up, so that I do not have to rename or decompress files first.
4. As an operator, I want tars processed in filename order, so that the run is predictable and reproducible.
5. As an operator, I want the image name taken from what `docker load` actually reports, so that the tar's filename does not have to follow any convention.
6. As an operator, I want a tar that contains several images to have every one of them retagged and pushed, so that nothing inside a tar is silently skipped.
7. As an operator, I want a tar whose image has no name (saved by image ID) to be reported as a failure, so that I know it needs manual attention instead of being pushed under a guessed name.
8. As an operator, I want the repo path flattened to its last segment, so that `any/nested/path/foo:1.2.3` lands at `<target_prefix>/foo:1.2.3`.
9. As an operator, I want to pass the Harbor host and project together as one prefix (e.g. `harbor.example.com/myproject`), so that the script does not need to know anything Harbor-specific.
10. As an operator, I want a trailing slash on the prefix to be tolerated, so that a copy-paste mistake does not produce a double slash in the tag.
11. As an operator, I want a warning when the target tag already exists locally before it is overwritten, so that I notice possible name collisions caused by flattening.
12. As an operator, I want a failed load, tag or push on one tar to be recorded and the run to continue with the next tar, so that one bad file does not force me to re-run everything.
13. As an operator, I want a final summary listing which tars succeeded and which failed, so that I can act on the failures without scrolling through the log.
14. As an operator, I want the exit code to be non-zero when any tar failed, so that a wrapping job or CI step can detect the problem.
15. As an operator, I want `--dry-run` to print every `source -> target` mapping without loading, tagging or pushing, so that I can verify the retag rule before the first real run.
16. As an operator, I want `--dry-run` to work without a running docker daemon, so that I can check mappings on any machine that has the tar files.
17. As an operator, I want local images left in place by default after a push, so that a failed or partial run can be retried or inspected.
18. As an operator, I want `--cleanup` to remove both the original and the new local tag only for images that were pushed successfully, so that disk is reclaimed without losing the evidence of what failed.
19. As an operator, I want the script to assume I have already run `docker login`, so that credentials are never handled by the script.
20. As an operator, I want the script to check that the docker daemon is reachable before it starts a real run, so that it fails fast with a clear message instead of failing on the first tar.
21. As an operator, I want missing or extra arguments to print a usage message and exit with a distinct code, so that mistakes in invocation are obvious.
22. As an operator, I want an empty directory (no matching tars) to be an error rather than a silent success, so that pointing at the wrong directory is caught.
23. As an operator, I want each tar's progress printed as it is processed, so that I can see what the script is doing on a long run.
24. As an operator, I want the script to run under bash on macOS and Linux with only `docker`, `tar`, `grep`, `sed` and `sort` available, so that it works on any workstation or CI box without extra installs.

## Implementation Decisions

- **Language / runtime:** bash (`#!/usr/bin/env bash`), `set -uo pipefail` without `-e`, because per-tar failure must not abort the run. Each docker call is checked explicitly and sets a per-tar failure flag.
- **Argument handling:** two required positional arguments (`tar_dir`, `target_prefix`) and two optional flags (`--cleanup`, `--dry-run`). Any other `-` prefixed argument, a missing positional, or a third positional prints usage and exits 2. A trailing `/` on `target_prefix` is stripped.
- **File discovery:** top-level glob over the three extensions using `nullglob`, then sorted by full path. No recursion.
- **Source ref discovery (real run):** parse the stdout of `docker load -i`. Lines beginning `Loaded image: ` yield source refs; any line beginning `Loaded image ID: ` marks the tar as failed (unnamed image) while still processing any named refs in the same tar.
- **Source ref discovery (dry run):** read `manifest.json` straight out of the archive with `tar -xOf` and extract the `RepoTags` array with `grep`. No `jq` dependency. A tar with no `RepoTags` is reported as a failure in dry-run too.
- **Retag rule:** implemented in a single function `to_target_ref` mapping a source ref to a target ref. The last `/`-separated segment of the source ref is kept and prefixed with `target_prefix`. The function returns non-zero when it refuses a ref, and the caller records that image as a failure. Edge cases (decided):
  - a ref with no `:tag` defaults to `:latest`;
  - a digest ref (`name@sha256:…`) is refused — it cannot be tagged as a digest and the script will not invent a tag.
- **Collision check:** before `docker tag`, `docker image inspect <target>` is used to detect an existing local tag; if present a warning is emitted and the tag proceeds (overwriting).
- **Cleanup:** only when `--cleanup` is given and only after a successful `docker push`; removes the target tag and the source tag. A cleanup failure is a warning, not a tar failure.
- **Daemon check:** `docker info` is run once before the loop in real-run mode only; failure exits 1 immediately.
- **Reporting:** progress lines per tar and per image on stdout; warnings and errors prefixed `WARN:` / `ERROR:` on stderr; final summary with counts and basenames; exit 0 only if the failed list is empty.
- **Authentication:** none. The script never calls `docker login` and never handles credentials.

## Testing Decisions

- **What a good test looks like:** run the script as a black box from the command line and assert only on observable behavior — stdout, stderr, exit code, and the sequence of `docker` subcommands invoked. Internal function names and structure are not tested.
- **Single seam:** a fake `docker` executable placed ahead of the real one on `PATH`. The shim records every invocation (arguments) to a log file and returns scripted responses keyed on the tar filename or ref — e.g. print `Loaded image: …` lines for a load, print `Loaded image ID: …` for an unnamed tar, exit non-zero on `push` for a specific ref, succeed or fail on `image inspect` to simulate a local collision, fail on `info` to simulate no daemon.
- **Fixtures:** real archives created with `tar` containing a hand-written `manifest.json` with the desired `RepoTags`, including: single image, multiple images, empty `RepoTags`, a `.tar.gz` variant, and a `.tgz` variant. These serve both dry-run tests (which read the manifest) and real-run tests (where the shim ignores the file content).
- **Scenarios to cover:** usage errors (missing arg, extra arg, unknown flag, non-directory); empty directory; happy path single tar; multi-image tar; unnamed image tar; load failure; tag failure; push failure with continuation and correct summary/exit code; collision warning; `--cleanup` removes exactly the two tags and only on success; `--dry-run` prints mappings, never calls `docker`, and works with the shim absent; trailing-slash prefix; filename ordering; both compressed extensions; `to_target_ref` edge cases (no tag, digest ref) behave as the operator decided.
- **Prior art:** none in this repository — it currently contains only the script. A plain bash test runner (one function per scenario, temp dir per test, `diff` against expected shim log) is sufficient; no test framework is required.

## Out of Scope

- `docker login` or any credential handling.
- Recursive directory scanning.
- Creating Harbor projects or checking that the target project exists.
- Any retag rule other than "flatten to last path segment under a fixed prefix" (no per-image mapping file, no regex rewriting).
- Skipping images that already exist in the remote registry.
- Parallel loads/pushes.
- Support for `skopeo`, `crane`, or pushing without a docker daemon.
- POSIX `sh` compatibility.
- A global two-phase "load everything, detect collisions, then push" mode.

## Further Notes

- Environment observed at design time: macOS with docker client 20.10.12; `skopeo` and `crane` not installed.
- Flattening can cause two source images with the same last segment and tag to map to the same target; the local collision warning is the only guard. If this happens in practice, the retag rule (not the script structure) is the thing to revisit.
- The `to_target_ref` function is the one place the operator is expected to edit; everything else should stay generic.
