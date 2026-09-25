# image-puller

[English](#english) | [繁體中文](#繁體中文)

---

<a name="english"></a>
## English

A single Bash script that batch-loads Docker image tar files from a directory,
retags every image under a new registry prefix (flattening the original repo
path), and pushes it. Typical use: moving images exported from one registry
into a Harbor project or an air-gapped registry.

```text
registry.example.com/team/foo:1.2.3  ->  harbor.example.com/myproject/foo:1.2.3
```

### Quick start

```sh
docker login harbor.example.com

# 1. preview the mapping — no daemon needed, nothing is loaded or pushed
./retag-push.sh ./images harbor.example.com/myproject --dry-run

# 2. run for real, removing local tags after each successful push
./retag-push.sh ./images harbor.example.com/myproject --cleanup
```

### Usage

```sh
./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
```

| Argument | Meaning |
| --- | --- |
| `tar_dir` | Directory containing `*.tar`, `*.tar.gz`, `*.tgz`. Top level only; processed in filename order |
| `target_prefix` | Registry host plus optional project, e.g. `harbor.example.com/myproject`. A trailing `/` is tolerated |
| `--dry-run` | Print every `source -> target` mapping without touching Docker. Reads `manifest.json` straight from each tar, so no daemon is needed |
| `--cleanup` | After a successful push, remove both local tags (the original and the new one) |
| `-h`, `--help` | Print usage and exit |

The script never handles credentials — run `docker login` yourself first.

### How it works

1. Lists `*.tar` / `*.tar.gz` / `*.tgz` in `tar_dir` (top level only) and sorts them by name.
2. For each tar:
   - normal run: `docker load -i` and takes the image names from what `docker load` reports;
   - dry run: reads `RepoTags` from the tar's `manifest.json` instead.
3. For each image name, keeps only the last path segment and prepends `target_prefix`.
4. `docker tag` + `docker push`, then optionally `docker rmi` both tags (`--cleanup`).
5. Prints a summary of succeeded and failed tars.

### Behaviour

- The image name comes from the tar's contents, not from its filename. A tar holding several images has every one of them retagged and pushed.
- Only the last path segment of the source name is kept (`team/foo` -> `foo`). A name with no tag (or tagged `latest`) whose last segment contains an underscore is split at the last underscore into name and tag (`team/foo_bar` -> `foo:bar`, `foo_bar_baz` -> `foo_bar:baz`); an explicit tag is kept as-is (`foo_bar:1.2.3` stays `foo_bar:1.2.3`). Any hyphen remaining in the name is then normalised to an underscore (`kd-table-purge_1.0` -> `kd_table_purge:1.0`); hyphens in the tag are kept, so `foo-bar:v1-rc1` becomes `foo_bar:v1-rc1`. A five-segment numeric tag ending in `.0` is shortened to four segments (`5.1.0.19.0` -> `5.1.0.19`); any other tag, including upstream three-segment versions such as `12.2.0`, is left untouched. Otherwise a name with no tag gets `:latest`. A digest reference (`name@sha256:…`) cannot be retagged and is reported as a failure.
- A tar that contains an unnamed image (saved by ID) is reported as a failure; any named images in the same tar are still processed.
- Each tar is processed independently. A failure (load, tag, push, unmappable name) is recorded and the run continues with the next tar.
- A warning is printed if the target tag already exists locally before it is overwritten.
- Filenames with spaces or other unusual characters are handled safely.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Every tar succeeded |
| `1` | At least one tar failed, or the Docker daemon is unreachable |
| `2` | Usage error (missing/extra arguments, unknown option, `tar_dir` not a directory) |
| `127` | A required command (`tar`, `sort`, `docker`) is missing |

### Requirements

- bash >= 3.2 (works with the stock macOS bash)
- `tar`, `grep`, `sed`, `tr`, `sort` (with `-z` support)
- Docker CLI with a reachable daemon — not needed for `--dry-run`

Works on macOS and Linux. Safe to run from cron: the script appends the usual
system paths to `PATH` so `docker` is still found under a minimal environment.

### Design

See [SPEC.md](SPEC.md) for the full design and testing decisions.

---

<a name="繁體中文"></a>
## 繁體中文

一支 Bash 腳本，批次載入目錄下的 Docker image tar 檔，把每個 image 重新打上新的
registry 前綴（並攤平原本的 repo 路徑），然後推送出去。典型用途：把從某個 registry
匯出的 image 搬到 Harbor 專案或離線環境的 registry。

```text
registry.example.com/team/foo:1.2.3  ->  harbor.example.com/myproject/foo:1.2.3
```

### 快速開始

```sh
docker login harbor.example.com

# 1. 先預覽對應關係 — 不需要 daemon，也不會 load 或 push 任何東西
./retag-push.sh ./images harbor.example.com/myproject --dry-run

# 2. 正式執行，每個 push 成功後順便清掉本地 tag
./retag-push.sh ./images harbor.example.com/myproject --cleanup
```

### 用法

```sh
./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
```

| 參數 | 說明 |
| --- | --- |
| `tar_dir` | 存放 `*.tar`、`*.tar.gz`、`*.tgz` 的目錄。只看第一層，依檔名排序處理 |
| `target_prefix` | Registry 主機名加上選填的專案名，例如 `harbor.example.com/myproject`。結尾多打 `/` 也沒關係 |
| `--dry-run` | 只印出每一組 `來源 -> 目標` 對應，完全不碰 Docker。直接從 tar 內的 `manifest.json` 讀取，所以不需要 daemon |
| `--cleanup` | push 成功後刪掉本地的兩個 tag（原始的與新的） |
| `-h`、`--help` | 顯示用法後結束 |

腳本完全不處理帳密，請先自行執行 `docker login`。

### 運作方式

1. 列出 `tar_dir` 第一層的 `*.tar` / `*.tar.gz` / `*.tgz`，依檔名排序。
2. 對每個 tar：
   - 正常模式：`docker load -i`，並從 `docker load` 的輸出取得 image 名稱；
   - dry-run 模式：改讀 tar 內 `manifest.json` 的 `RepoTags`。
3. 對每個 image 名稱只保留最後一段路徑，前面接上 `target_prefix`。
4. `docker tag` + `docker push`，若指定 `--cleanup` 則再 `docker rmi` 兩個 tag。
5. 最後印出成功與失敗的 tar 清單。

### 行為說明

- Image 名稱來自 tar 的內容，而不是 tar 的檔名。一個 tar 裡有多個 image 時，每一個都會被重新打 tag 並推送。
- 來源名稱只保留最後一段路徑（`team/foo` -> `foo`）。沒有 tag（或 tag 為 `latest`）且最後一段含底線的名稱，會以最後一個底線切成名稱與 tag（`team/foo_bar` -> `foo:bar`、`foo_bar_baz` -> `foo_bar:baz`）；有明確 tag 的則原樣保留（`foo_bar:1.2.3` 不變）。名稱中剩下的連字號會統一改成底線（`kd-table-purge_1.0` -> `kd_table_purge:1.0`）；tag 中的連字號保留，所以 `foo-bar:v1-rc1` 會變成 `foo_bar:v1-rc1`。五段純數字且結尾為 `.0` 的 tag 會縮短為四段（`5.1.0.19.0` -> `5.1.0.19`）；其餘 tag，包含上游的三段版號如 `12.2.0`，一律不動。其餘沒有 tag 的名稱會補上 `:latest`。Digest 形式（`name@sha256:…`）無法重新打 tag，會被記為失敗。
- tar 內若有未命名的 image（以 ID 儲存），該 tar 記為失敗，但同一個 tar 裡有名稱的 image 仍會照常處理。
- 每個 tar 各自獨立。任何一步失敗（load、tag、push、名稱無法對應）都會被記錄下來，然後繼續處理下一個 tar。
- 若目標 tag 在本地已存在，覆蓋前會先印出警告。
- 檔名含空白或其他特殊字元也能正確處理。

### 結束碼

| 結束碼 | 意義 |
| --- | --- |
| `0` | 所有 tar 都成功 |
| `1` | 至少一個 tar 失敗，或連不上 Docker daemon |
| `2` | 用法錯誤（參數缺少或過多、未知選項、`tar_dir` 不是目錄） |
| `127` | 缺少必要指令（`tar`、`sort`、`docker`） |

### 需求

- bash >= 3.2（macOS 內建的 bash 即可）
- `tar`、`grep`、`sed`、`tr`、`sort`（需支援 `-z`）
- Docker CLI 且 daemon 可連線 — `--dry-run` 不需要

macOS 與 Linux 皆可使用。可放心排進 cron：腳本會把常見的系統路徑補到 `PATH`，
在精簡環境下仍找得到 `docker`。

### 設計文件

完整的設計與測試決策請見 [SPEC.md](SPEC.md)。
