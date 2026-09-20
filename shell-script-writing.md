---
name: shell-script-writing
description: Use when writing a new shell script or editing an existing .sh/.bash file — deploy scripts, cron jobs, container entrypoints, CI helpers, backup and migration scripts. Not for one-off commands typed at an interactive prompt.
---

# Shell Script Writing

Correct-by-default shell idioms. Every pattern here exists because the obvious alternative fails silently on real input — a filename with a space, an empty variable, an HTTP 500, a stripped-down cron PATH.

## Start every script this way

Every script follows the four-section layout from [[Vendor 交付 Shell Script 品質管理]] §4.2 — Header, Constants, Functions, Main. Reviewers check for it (`STRUCT-xx` in shell-script-review), and bats-core tests depend on it.

```bash
#!/bin/bash
# === 1. File Header ===
# What this script does, in one or two lines.
# Dependencies: bash >= 4.0, curl >= 7.50, jq
# Tested on: Oracle Linux 8

set -euo pipefail

# === 2. Constants (readonly, UPPER_CASE) ===
readonly VERSION="1.2.0"
readonly CONFIG_DIR="$HOME/.config/myapp"
readonly DEFAULT_TIMEOUT=30

# === 3. Functions (snake_case, every variable local) ===
# Arguments: $1 = name (required), $2 = value (optional, default: "default")
# Returns:   0 on success, 1 if process fails
# Side effects: none
my_function() {
    local name="$1"
    local value="${2:-default}"
    local result

    result=$(process "$name" "$value") || return 1
    echo "$result"
}

# === 4. Main Logic ===
main() {
    validate_args "$@"
    do_work
    cleanup
}

main "$@"
```

Why each rule exists:

| Rule | Prevents |
| --- | --- |
| `set -euo pipefail` right after the header | `-e` exit on error, `-u` error on undefined variable, `-o pipefail` propagate failure through pipes. Without `pipefail`, `false \| true` exits **0** — the pipeline lies about having failed. |
| `readonly` + `UPPER_CASE` constants | A constant silently reassigned 200 lines later |
| `local` on every function variable | Functions clobbering each other's (and the caller's) variables through the global namespace |
| Docstring comment per function | The next reader guessing what `$2` means and whether the function touches disk |
| `main()` wrapper, `main "$@"` last | `source script.sh` in a test running the whole script — bats-core needs to source it without side effects |
| `Dependencies:` / `Tested on:` in the header | Reviewer discovering the bash 4 requirement in production on a bash 3.2 box |

For unattended scripts (cron, systemd, containers), also set PATH explicitly right after `set -euo pipefail`:

```bash
export PATH=/usr/local/bin:/usr/bin:/bin
```

## Idioms

### Use a variable

```bash
✅ rm -- "$FILE"
❌ rm $FILE
```

Unquoted expansion word-splits and glob-expands. With `FILE="my report.txt"` the second form deletes `my` and `report.txt`.

### Touch a destructive path

```bash
✅ rm -rf "${DIR:?DIR not set}/"
❌ rm -rf "$DIR/"
```

An empty `$DIR` turns the second form into `rm -rf /`. The `:?` expansion aborts instead.

### Iterate files in a directory

```bash
✅ for f in /path/*; do [ -e "$f" ] || continue; ...; done
❌ for f in $(ls /path); do
```

`ls` output splits on whitespace. And when a glob matches nothing, bash leaves the pattern literal — the loop body runs once with `f=/path/*`, which is why the `-e` guard is there.

### Iterate files recursively

```bash
✅ find . -name '*.log' -print0 | while IFS= read -r -d '' f; do ...; done
❌ for f in $(find . -name '*.log'); do
```

Only the null delimiter survives filenames containing spaces or newlines.

### Pass arguments through

```bash
✅ cmd "$@"
❌ cmd $@
```

`"$@"` preserves argument boundaries; `$@` re-splits arguments that were already correctly separated.

### Build a command dynamically

```bash
✅ args=(curl -fsS); args+=(-H "$HEADER"); "${args[@]}"
❌ CMD="curl -fsS -H '$HEADER'"; $CMD
```

String-splicing breaks on any embedded space and invites injection. An array keeps each element intact.

### Capture command output

```bash
✅ local out; out=$(cmd)
❌ local out=$(cmd)
```

`local` is itself a command and its exit status overwrites the substitution's. Verified: `local v=$(false)` leaves `$?` at **0** and `set -e` does not fire. Splitting the declaration yields `1`.

### Write a conditional

```bash
✅ if [[ -n "$VAR" ]]; then
❌ if [ $VAR == "yes" ]; then
```

`[[ ]]` does not word-split, so an empty variable cannot produce a syntax error. `==` is not POSIX `[`.

### Call an HTTP API

```bash
✅ curl -fsS --connect-timeout 5 --max-time 30 --retry 3 "$URL"
❌ curl "$URL"
```

Without `-f` an HTTP 500 exits 0 and the error page becomes your data. Without timeouts a hung server hangs the script indefinitely.

### Handle a secret

```bash
✅ mysql --defaults-file=<(printf '[client]\npassword=%s\n' "$PASSWORD")
❌ mysql -p"$PASSWORD"
```

Anything in argv is world-readable through `ps -ef`. Read the value from the environment or a secret store — never a literal in the file.

### Create a temp file

```bash
✅ TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
❌ TMP=/tmp/myscript.$$
```

Predictable names collide and are a symlink-attack vector. `trap ... EXIT` cleans up even when the script fails.

### Quote a trap

```bash
✅ trap 'rm -f "$TMP"' EXIT
❌ trap "rm -f $TMP" EXIT
```

Double quotes expand at trap-definition time, capturing whatever `$TMP` held then. Verified: after reassignment the double-quoted form still fires with the old value; the single-quoted form sees the current one.

### Write a file

```bash
✅ cmd > "$f.tmp" && mv "$f.tmp" "$f"
❌ cmd > "$f"
```

`mv` within one filesystem is atomic. Direct redirection truncates first, so a concurrent reader — or a crash — catches a half-written file.

### Change directory

```bash
✅ (cd "$DIR" && cmd)
✅ cd "$DIR" || exit 1
❌ cd "$DIR"
```

If `cd` fails, every later command runs in the wrong directory. The subshell form avoids changing the script's own directory at all.

### Check a dependency

```bash
✅ command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 127; }
❌ which jq
```

`command -v` is a POSIX builtin; `which` is an external binary with inconsistent exit codes across distros.

### Parse JSON

```bash
✅ jq -r '.items[].name' <<<"$JSON"
❌ grep -o '"name":"[^"]*"' <<<"$JSON"
```

Regex breaks on escaped quotes, nested objects, and reordered keys.

### Read input line by line

```bash
✅ while IFS= read -r line; do ...; done < "$FILE"
❌ while read line; do
```

Without `-r` backslashes are consumed. Without `IFS=` leading and trailing whitespace is stripped.

## Environment traps

**cron** — PATH is minimal, often just `/usr/bin:/bin`, so `docker`, `kubectl`, and everything in `/usr/local/bin` disappear. Use absolute paths or export PATH at the top. There is no TTY, so anything expecting one fails. Log to stdout/stderr and let cron capture it.

**Containers and PID 1** — a shell script running as PID 1 does not forward signals to its children, so `SIGTERM` at shutdown is ignored and the runtime SIGKILLs the container after the grace period. End an entrypoint with `exec "$@"` so the real process replaces the shell and inherits signal handling.

**Non-interactive shells** — `~/.bashrc` is not sourced. Aliases, PATH additions, and tool shims (nvm, pyenv, rbenv) do not exist. Declare everything the script needs inside the script.

**bash version** — macOS ships bash **3.2** at `/bin/bash`; Linux targets normally run 4.x or 5.x. `mapfile`/`readarray`, associative arrays (`declare -A`), and `${var^^}` do not exist in 3.2, so a script that works on the server fails when tested locally. Require the version you depend on:

```bash
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || { echo "bash 4+ required" >&2; exit 127; }
```

## Before calling it done

- Run `shellcheck script.sh` — it catches most of the above mechanically.
- Check the four sections are present and the file ends with `main "$@"` — `shellcheck` does not check structure.
- Test with a filename containing a space.
- Test the failure path, not just the happy one: missing dependency, API returning 500, directory that does not exist.
- Confirm the exit code is non-zero on failure: `./script.sh; echo $?`
- For a full audit against critical-defect criteria, use the shell-script-review skill.

## Related

- [[ShellCheck 常見錯誤對照]] — full SC-code reference table
- [[Vendor 交付 Shell Script 品質管理]] — four-section structure standard, CI gates, vendor SOP
- [[Shell Script 測試與 Coverage]] — bats-core tests and kcov coverage thresholds
