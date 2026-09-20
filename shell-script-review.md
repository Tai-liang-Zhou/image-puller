---
name: shell-script-review
description: Review shell scripts (.sh, .bash) for critical defects — unsafe expansions, missing error modes, command injection, credential exposure, and destructive file operations. Use when asked to review, audit, check, or lint a shell script, especially vendor-delivered or untrusted code that touches production data. Triggers on "review this .sh", "check this bash script", "shellcheck this", "audit bash code", "vendor script review".
---

# Shell Script Review

Review shell scripts for defects that cause production incidents. Tuned for vendor-delivered or untrusted code, where one unquoted variable or a missing `set -e` is a single bad input away from an outage.

## Workflow

1. Confirm which files to review. Review each file separately.
2. Run every check below against the script.
3. For each finding record: line number, severity, rule ID, what is wrong, why it is dangerous, and a before/after fix.
4. Produce the report in the output format below.

## Severity

| Severity | Meaning |
| --- | --- |
| 🚨 Blocker | Causes a production incident — data loss, security hole, or silent failure. Must fix before accepting. |
| ⚠️ Warning | High chance of a bug in edge cases. Should fix. |

When uncertain, pick the stricter severity. You cannot control how badly someone writes a script; you can control how far a bad one travels before someone stops it.

## Blockers

**SAFE-01 — Missing error mode.** No `set -euo pipefail`, so every failed command continues silently. Add it directly after the shebang.

**SC2086 — Unquoted variable expansion.** `rm $FILE` word-splits and glob-expands; a filename with a space deletes the wrong thing.
→ `rm -- "$FILE"`

**SC2046 — Unquoted command substitution.** `chmod 600 $(find . -name '*.key')` has the same splitting hazard.
→ Quote it, or iterate with `find … -print0 | while IFS= read -r -d ''`.

**SC2115 — `rm -rf` without an empty-variable guard.** `rm -rf "$DIR/"` becomes `rm -rf /` when `$DIR` is empty.
→ `rm -rf "${DIR:?DIR not set}/"`

**SC2164 — `cd` without failure handling.** If `cd` fails, every later command runs in the wrong directory — including destructive ones.
→ `cd "$DIR" || exit 1` (or rely on `set -e`).

**SC2068 — Unquoted `$@`.** `cmd $@` re-splits arguments that were already correctly separated.
→ `cmd "$@"`

**SEC-01 — `eval` on untrusted input.** `eval "ls $USER_INPUT"` is arbitrary command execution.
→ Drop `eval`; build an array instead: `cmd=(ls -- "$USER_INPUT"); "${cmd[@]}"`

**SEC-02 — Secret on the command line.** `mysql -p"$PASSWORD"` is visible to every user on the box via `ps -ef`.
→ `mysql --defaults-file=<(printf '[client]\npassword=%s\n' "$PASSWORD")`

**SEC-03 — Hardcoded credentials.** Passwords, tokens, or API keys written literally in the script.
→ Read from an environment variable or a secret store.

**SEC-04 — Format string injection.** `printf "$user_input"` interprets `%s` / `%n` inside the input.
→ `printf '%s\n' "$user_input"`

**EXT-01 — `curl` without `-f`.** An HTTP 500 exits 0 with the error page as the body, and the script treats it as success.
→ `curl -fsS --max-time 30 …`

**SC2039 / SC3xxx — Bash features under `#!/bin/sh`.** `[[ ]]`, arrays, and `==` are undefined behavior in POSIX `sh` and silently misbehave on dash.
→ Change the shebang to `#!/bin/bash`, or rewrite POSIX-clean.

## Warnings

- **SC2045** — `for f in $(ls)` breaks on spaces and newlines. Use a glob: `for f in /path/*`
- **SC2181** — `if [ $? -eq 0 ]` is fragile and breaks under refactoring. Test the command directly: `if cmd; then`
- **SC2162** — `read` without `-r` mangles backslashes. Use `while IFS= read -r line`
- **SC2155** — `local var=$(cmd)` masks the command's exit code. Split the declaration: `local var; var=$(cmd)`
- **SC2064** — `trap "rm $TMP" EXIT` expands at trap-definition time. Single-quote it: `trap 'rm -f "$TMP"' EXIT`
- **SC2154** — Referenced but never assigned, usually a typo. Under `set -u` this aborts at runtime.
- **SC1090 / SC1091** — Dynamic `source` path the linter cannot follow. Annotate: `# shellcheck source=./lib.sh`
- **SEC-05** — Temp files not created with `mktemp`, or created without cleanup: `TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT`
- **EXT-02** — External binary used without a pre-flight check: `command -v jq >/dev/null 2>&1 || exit 127`
- **RES-01** — External call (DB query, HTTP request) with no timeout: `timeout 30 cmd`, or `curl --max-time`
- **FILE-01** — Non-atomic write; readers can observe a half-written file: `cmd > "$f.tmp" && mv "$f.tmp" "$f"`
- **FILE-02** — `find` iteration that breaks on unusual filenames: `find … -print0 | while IFS= read -r -d '' f`

## Structure (Warnings)

Vendor-delivered scripts must follow the four-section layout from [[Vendor 交付 Shell Script 品質管理]] §4.2. These are ⚠️ Warnings: they rarely cause an outage on their own, but they are the difference between a script that can be tested and one that cannot.

```bash
#!/bin/bash
# === 1. File Header ===        description, Dependencies:, Tested on:
set -euo pipefail
# === 2. Constants ===          readonly UPPER_CASE
# === 3. Functions ===          snake_case, every variable `local`, docstring comment
# === 4. Main Logic ===         main() { … }; main "$@"
```

- **STRUCT-01** — Missing or incomplete four-section layout (Header / Constants / Functions / Main). Top-level logic scattered between function definitions is the usual symptom.
- **STRUCT-02** — Header does not declare `Dependencies:` (with minimum versions) and `Tested on:` platform. A reviewer cannot judge environment fit without it.
- **STRUCT-03** — Constant not `readonly` or not `UPPER_CASE`. `VERSION="1.2.0"` can be silently overwritten later.
  → `readonly VERSION="1.2.0"`
- **STRUCT-04** — Function variable without `local`. Leaks into the global namespace and overwrites a caller's variable of the same name; also masks bugs in recursion and loops.
  → `local name="$1"; local result; result=$(cmd)` (see SC2155 for why the declaration is split)
- **STRUCT-05** — Function not `snake_case`, or missing a docstring comment stating arguments, return value, and side effects.
- **STRUCT-06** — No `main()` wrapper, or the file does not end with `main "$@"`. Without it, `source`-ing the script for testing executes it, which blocks bats-core unit tests.

## Output format

````markdown
# Shell Script Review: `<filename>`

| Metric | Count |
| --- | --- |
| Files reviewed | N |
| 🚨 Blockers | X |
| ⚠️ Warnings | Y |

**Verdict:** ✅ Accept / ⚠️ Conditional Accept (fix blockers) / ❌ Reject

**Fix these first:**
1. <highest-priority blocker>
2. …
3. …

## 🚨 Blockers

### B1 — <rule ID>: <short title>
- **Line:** `script.sh:42`
- **Issue:** `rm -rf "$DIR/"` wipes the disk when `$DIR` is empty.
- **Fix:**
  ```bash
  # Before
  rm -rf "$DIR/"
  # After
  rm -rf "${DIR:?DIR not set}/"
  ```

## ⚠️ Warnings

### W1 — <rule ID>: <short title>
- **Line:** `script.sh:18`
- **Issue:** …
- **Fix:** …

## ✅ Strengths
- <what the script does well>
````

## Review rules

- Be specific. Not "improve error handling" — "line 18, add `|| exit 1` after the `cd`."
- Always show before/after code. Never describe a fix in prose alone.
- Report every finding. A script with 30 problems gets 30 findings; severity guides attention, it does not suppress output.
- Cite the SC-ID where one exists, so the team knows which findings `shellcheck` would have caught in CI and which needed a human.
- Note real strengths. A balanced review gets acted on; a pile-on gets ignored.
