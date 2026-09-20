#!/usr/bin/env bash
#
# retag-push.sh - load every docker image tar in a directory, retag it under a
# new registry prefix (flattening the repo path), and push it.
#
# Usage:
#   ./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
#
#   tar_dir        directory containing *.tar / *.tar.gz / *.tgz (top level only)
#   target_prefix  e.g. harbor.example.com/myproject  ->  harbor.example.com/myproject/<name>:<tag>
#   --cleanup      after a successful push, remove both local tags
#   --dry-run      show what would happen; reads manifest.json instead of loading
#
# Exit code is 1 if any tar failed. Assumes `docker login` was already done.

set -uo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# ---------- args ----------
TAR_DIR=""
TARGET_PREFIX=""
CLEANUP=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --cleanup) CLEANUP=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $arg" >&2; usage ;;
    *)
      if [[ -z "$TAR_DIR" ]]; then TAR_DIR="$arg"
      elif [[ -z "$TARGET_PREFIX" ]]; then TARGET_PREFIX="$arg"
      else echo "too many arguments" >&2; usage
      fi
      ;;
  esac
done

[[ -n "$TAR_DIR" && -n "$TARGET_PREFIX" ]] || usage
[[ -d "$TAR_DIR" ]] || { echo "not a directory: $TAR_DIR" >&2; exit 2; }
TARGET_PREFIX="${TARGET_PREFIX%/}"   # tolerate trailing slash

# ---------- helpers ----------
log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

# Compute the target reference for a source image reference by keeping only
# the last path segment:
#   registry.example.com/team/foo:1.2.3 -> $TARGET_PREFIX/foo:1.2.3
#   team/foo                        -> $TARGET_PREFIX/foo:latest
#   foo@sha256:abcd...                -> refused (return 1); digests can't be retagged
to_target_ref() {
  local src="$1"
  local last="${src##*/}"
  case "$last" in
    *@*) return 1 ;;
    *:*) ;;
    *)   last="$last:latest" ;;
  esac
  printf '%s/%s\n' "$TARGET_PREFIX" "$last"
}

# Print source refs contained in a tar without loading it (dry-run only).
refs_from_manifest() {
  local tar_file="$1"
  tar -xOf "$tar_file" manifest.json 2>/dev/null \
    | grep -o '"RepoTags":\[[^]]*\]' \
    | grep -o '"[^"]*"' \
    | grep -v '"RepoTags"' \
    | tr -d '"'
}

# Print source refs produced by `docker load`; returns 1 if any were unnamed.
refs_from_load() {
  local tar_file="$1" out rc=0
  out="$(docker load -i "$tar_file")" || return 1
  if grep -q '^Loaded image ID:' <<<"$out"; then
    err "  tar contains unnamed image(s), cannot retag"
    rc=1
  fi
  sed -n 's/^Loaded image: //p' <<<"$out"
  return $rc
}

# ---------- main ----------
if (( ! DRY_RUN )); then
  docker info >/dev/null 2>&1 || { err "docker daemon not reachable"; exit 1; }
fi

shopt -s nullglob
tar_files=("$TAR_DIR"/*.tar "$TAR_DIR"/*.tar.gz "$TAR_DIR"/*.tgz)
shopt -u nullglob
(( ${#tar_files[@]} )) || { err "no tar files found in $TAR_DIR"; exit 1; }
IFS=$'\n' tar_files=($(sort <<<"${tar_files[*]}")); unset IFS

succeeded=()
failed=()

for tar_file in "${tar_files[@]}"; do
  log "==> $(basename "$tar_file")"
  tar_ok=1

  if (( DRY_RUN )); then
    refs="$(refs_from_manifest "$tar_file")"
    [[ -n "$refs" ]] || { err "  no RepoTags in manifest.json"; tar_ok=0; }
  else
    refs="$(refs_from_load "$tar_file")" || tar_ok=0
  fi

  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    if ! dst="$(to_target_ref "$src")"; then
      err "  cannot map $src"; tar_ok=0; continue
    fi
    log "  $src -> $dst"

    if (( DRY_RUN )); then continue; fi

    if docker image inspect "$dst" >/dev/null 2>&1; then
      warn "  $dst already exists locally, will be overwritten"
    fi
    if ! docker tag "$src" "$dst"; then
      err "  tag failed"; tar_ok=0; continue
    fi
    if ! docker push "$dst"; then
      err "  push failed: $dst"; tar_ok=0; continue
    fi
    if (( CLEANUP )); then
      docker rmi "$dst" "$src" >/dev/null || warn "  cleanup failed for $src"
    fi
  done <<<"$refs"

  if (( tar_ok )); then succeeded+=("$tar_file"); else failed+=("$tar_file"); fi
done

# ---------- summary ----------
log
log "Succeeded: ${#succeeded[@]}"
for f in "${succeeded[@]}"; do log "  $(basename "$f")"; done
log "Failed:    ${#failed[@]}"
for f in "${failed[@]}"; do log "  $(basename "$f")"; done

(( ${#failed[@]} == 0 ))
