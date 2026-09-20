# image-puller

Batch-load docker image tar files from a directory, retag them under a new
registry prefix (flattening the repo path), and push them.

```
registry.example.com/team/foo:1.2.3  ->  harbor.example.com/myproject/foo:1.2.3
```

## Usage

```sh
./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
```

| Argument | Meaning |
|---|---|
| `tar_dir` | Directory containing `*.tar`, `*.tar.gz`, `*.tgz` (top level only, processed in filename order) |
| `target_prefix` | Registry host plus optional project, e.g. `harbor.example.com/myproject` |
| `--dry-run` | Print every `source -> target` mapping without touching docker. Reads `manifest.json` from each tar, so no daemon is needed |
| `--cleanup` | After a successful push, remove both local tags (original and new) |

Run `docker login` yourself first; the script never handles credentials.

### Example

```sh
# check the mapping first
./retag-push.sh ./images harbor.example.com/myproject --dry-run

# do it
./retag-push.sh ./images harbor.example.com/myproject --cleanup
```

## Behaviour

- The image name comes from what `docker load` reports, not from the tar's filename. A tar with several images has every one of them retagged and pushed.
- Only the last path segment of the source name is kept. A name with no tag gets `:latest`; a digest reference (`name@sha256:…`) is refused.
- Each tar is processed independently. A failure (load, unnamed image, tag, push) is recorded and the run continues.
- A warning is printed if the target tag already exists locally before it is overwritten.
- The final summary lists succeeded and failed tars. Exit code is `1` if any tar failed, `2` on usage errors, `0` otherwise.

## Requirements

bash, docker CLI, `tar`, `grep`, `sed`, `sort`. Works on macOS and Linux.

## Design

See [SPEC.md](SPEC.md) for the full design and testing decisions.
