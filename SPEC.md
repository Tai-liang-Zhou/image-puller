# 規格：retag-push.sh — 批次 load / retag / push docker image tar

標籤：`ready-for-agent`

## 問題描述

我會收到一整個目錄的 docker image tar 檔（由 `docker save` 產生），裡面的 image 名稱掛在來源 registry 的路徑下，例如 `registry.example.com/team/foo:1.2.3`。我需要把它們全部放進我們的 Harbor 同一個 project 底下，並使用扁平化的名稱（`harbor.example.com/myproject/foo:1.2.3`）。手動做的話，每個檔案都要跑 `docker load`、看印出來的名稱、打一次 `docker tag`、再 `docker push`，很容易打錯 tag，或搞不清楚哪些檔案已經處理過了。

## 解決方案

一支 bash 腳本 `retag-push.sh`，用法如下：

```
./retag-push.sh <tar_dir> <target_prefix> [--cleanup] [--dry-run]
```

它會掃描 `<tar_dir>` 的最上層，找出 `*.tar`、`*.tar.gz`、`*.tgz`；逐一 load 進 docker；讀取 load 產生的 image 名稱；把每個名稱改寫成 `<target_prefix>/<最後一段路徑>:<tag>`；然後 tag 並 push。每個 tar 各自獨立處理——失敗會被記錄下來，整個流程繼續執行。結束時會列出成功與失敗的 tar 清單，只要有任何失敗，exit code 就是非零。`--dry-run` 只印出完整的對應關係，完全不碰 docker。`--cleanup` 會在 push 成功後移除本機的 tag。

## 使用者故事

1. 身為操作者，我希望只要指定一個目錄和一個目標 prefix，就能用一道指令把裡面所有 image tar 都 load、retag 並 push。
2. 身為操作者，我希望腳本只掃描目錄的最上層，這樣我可以透過檔案放置的位置精確控制要包含哪些檔案。
3. 身為操作者，我希望 `.tar`、`.tar.gz`、`.tgz` 都能被抓到，這樣就不必先改名或解壓縮。
4. 身為操作者，我希望 tar 依檔名順序處理，讓執行結果可預測、可重現。
5. 身為操作者，我希望 image 名稱取自 `docker load` 實際回報的內容，這樣 tar 的檔名不需要遵循任何慣例。
6. 身為操作者，我希望一個含有多個 image 的 tar，裡面每個 image 都會被 retag 並 push，不會有任何一個被默默跳過。
7. 身為操作者，我希望 image 沒有名稱（以 image ID 儲存）的 tar 會被回報為失敗，讓我知道它需要人工處理，而不是用猜出來的名稱推上去。
8. 身為操作者，我希望 repo 路徑被扁平化成最後一段，讓 `any/nested/path/foo:1.2.3` 落在 `<target_prefix>/foo:1.2.3`。
9. 身為操作者，我希望 Harbor 主機和 project 合併成一個 prefix 傳入（例如 `harbor.example.com/myproject`），這樣腳本不需要知道任何 Harbor 特有的東西。
10. 身為操作者，我希望 prefix 結尾多打一個斜線也能被容忍，這樣複製貼上時的小失誤不會在 tag 裡產生雙斜線。
11. 身為操作者，我希望在覆寫本機已存在的目標 tag 之前收到警告，讓我注意到扁平化可能造成的名稱衝突。
12. 身為操作者，我希望某個 tar 的 load、tag 或 push 失敗時會被記錄下來，然後繼續處理下一個 tar，這樣一個壞檔案不會逼我整批重跑。
13. 身為操作者，我希望最後有一份摘要列出哪些 tar 成功、哪些失敗，這樣我可以直接針對失敗的處理，不必翻整份 log。
14. 身為操作者，我希望只要有任何 tar 失敗，exit code 就是非零，讓外層的 job 或 CI 步驟能偵測到問題。
15. 身為操作者，我希望 `--dry-run` 印出每一組 `來源 -> 目標` 的對應，而不做 load、tag 或 push，這樣我能在第一次正式執行前先驗證 retag 規則。
16. 身為操作者，我希望 `--dry-run` 不需要 docker daemon 也能運作，這樣在任何有 tar 檔的機器上都能檢查對應結果。
17. 身為操作者，我希望 push 之後本機 image 預設保留，這樣失敗或只跑一半的執行可以重試或檢查。
18. 身為操作者，我希望 `--cleanup` 只對 push 成功的 image 移除原始與新建的本機 tag，這樣能回收磁碟空間，又不會失去失敗的證據。
19. 身為操作者，我希望腳本假設我已經跑過 `docker login`，這樣腳本永遠不需要處理憑證。
20. 身為操作者，我希望正式執行前先檢查 docker daemon 是否可連線，這樣能用明確的訊息快速失敗，而不是在第一個 tar 才出錯。
21. 身為操作者，我希望缺少或多出參數時印出用法說明並以獨立的 exit code 結束，讓呼叫方式的錯誤一目瞭然。
22. 身為操作者，我希望空目錄（沒有符合的 tar）視為錯誤而不是默默成功，這樣指錯目錄時會被抓到。
23. 身為操作者，我希望處理每個 tar 時都印出進度，這樣長時間執行時能看到腳本在做什麼。
24. 身為操作者，我希望腳本在 macOS 和 Linux 的 bash 下只需要 `docker`、`tar`、`grep`、`sed`、`sort` 就能執行，這樣任何工作機或 CI 機器都不必額外安裝東西。

## 實作決策

- **語言／執行環境：** bash（`#!/usr/bin/env bash`），使用 `set -uo pipefail` 但不加 `-e`，因為單一 tar 的失敗不能中止整個流程。每個 docker 呼叫都明確檢查，並設定該 tar 的失敗旗標。
- **參數處理：** 兩個必要的位置參數（`tar_dir`、`target_prefix`）與兩個選用旗標（`--cleanup`、`--dry-run`）。其他以 `-` 開頭的參數、缺少位置參數、或出現第三個位置參數，都會印出用法並以 2 結束。`target_prefix` 結尾的 `/` 會被去掉。
- **檔案搜尋：** 以 `nullglob` 對三種副檔名做最上層 glob，再依完整路徑排序。不遞迴。
- **來源 ref 取得（正式執行）：** 解析 `docker load -i` 的 stdout。以 `Loaded image: ` 開頭的行產生來源 ref；任何以 `Loaded image ID: ` 開頭的行會把該 tar 標記為失敗（未命名 image），但同一個 tar 裡有名稱的 ref 仍會繼續處理。
- **來源 ref 取得（dry run）：** 用 `tar -xOf` 直接從壓縮檔讀出 `manifest.json`，再用 `grep` 抽出 `RepoTags` 陣列。不依賴 `jq`。沒有 `RepoTags` 的 tar 在 dry-run 也會被回報為失敗。
- **Retag 規則：** 由單一函式 `to_target_ref` 實作，把來源 ref 對應到目標 ref。保留來源 ref 以 `/` 分隔的最後一段，前面接上 `target_prefix`。函式拒絕某個 ref 時回傳非零，呼叫端會把該 image 記為失敗。邊界情況（已決定）：
  - 沒有 `:tag`（或 tag 為 `latest`）且名稱含 `_` 的 ref，以最後一個底線切成 `name:tag`（`foo_bar` -> `foo:bar`、`foo_bar_baz` -> `foo_bar:baz`）；明確指定且非 `latest` 的 tag 永遠不會被改寫；
  - 其餘沒有 `:tag` 的 ref 預設補上 `:latest`；
  - digest 形式的 ref（`name@sha256:…`）會被拒絕——digest 無法被 tag，腳本也不會憑空捏造一個 tag。
- **衝突檢查：** 在 `docker tag` 之前，用 `docker image inspect <target>` 偵測本機是否已有該 tag；若存在則發出警告，然後照樣 tag（覆寫）。
- **Cleanup：** 只在指定 `--cleanup` 且 `docker push` 成功後執行；移除目標 tag 與來源 tag。cleanup 失敗只是警告，不算該 tar 失敗。
- **Daemon 檢查：** 僅在正式執行模式下，於迴圈前執行一次 `docker info`；失敗立即以 1 結束。
- **回報：** 每個 tar 與每個 image 的進度行輸出到 stdout；警告與錯誤分別以 `WARN:`／`ERROR:` 為前綴輸出到 stderr；最後的摘要包含數量與檔名；只有失敗清單為空時才以 0 結束。
- **認證：** 無。腳本永遠不呼叫 `docker login`，也不處理任何憑證。

## 測試決策

- **好的測試長什麼樣：** 把腳本當黑盒子從命令列執行，只針對可觀察的行為做斷言——stdout、stderr、exit code，以及被呼叫的 `docker` 子命令序列。不測試內部函式名稱與結構。
- **單一接縫：** 在 `PATH` 中放一個假的 `docker` 可執行檔，排在真正的 docker 之前。這個 shim 把每次呼叫（含參數）記錄到 log 檔，並依 tar 檔名或 ref 回傳預先安排好的回應——例如 load 時印出 `Loaded image: …`、未命名的 tar 印出 `Loaded image ID: …`、對特定 ref 的 `push` 回傳非零、`image inspect` 成功或失敗以模擬本機衝突、`info` 失敗以模擬沒有 daemon。
- **測試資料：** 用 `tar` 建立真正的壓縮檔，內含手寫的 `manifest.json` 與想要的 `RepoTags`，包括：單一 image、多個 image、空的 `RepoTags`、`.tar.gz` 版本、`.tgz` 版本。這些同時用於 dry-run 測試（讀 manifest）與正式執行測試（shim 忽略檔案內容）。
- **要涵蓋的情境：** 用法錯誤（缺參數、多參數、未知旗標、非目錄）；空目錄；單一 tar 的正常路徑；多 image 的 tar；未命名 image 的 tar；load 失敗；tag 失敗；push 失敗後繼續執行且摘要／exit code 正確；衝突警告；`--cleanup` 只移除那兩個 tag 且僅在成功時；`--dry-run` 印出對應、絕不呼叫 `docker`、且 shim 不存在時也能運作；prefix 結尾斜線；檔名排序；兩種壓縮副檔名；`to_target_ref` 的邊界情況（沒有 tag、digest ref）行為符合操作者的決定。
- **既有做法：** 此 repo 裡沒有——目前只有腳本本身。一個純 bash 的測試執行器（每個情境一個函式、每個測試一個暫存目錄、用 `diff` 比對預期的 shim log）就足夠了；不需要測試框架。

## 不在範圍內

- `docker login` 或任何憑證處理。
- 遞迴掃描目錄。
- 建立 Harbor project 或檢查目標 project 是否存在。
- 「扁平化到最後一段路徑並接上固定 prefix」以外的 retag 規則（不支援逐 image 的對應檔、不支援 regex 改寫）。
- 跳過遠端 registry 已存在的 image。
- 平行 load／push。
- 支援 `skopeo`、`crane`，或不透過 docker daemon 推送。
- POSIX `sh` 相容。
- 全域兩階段的「先全部 load、偵測衝突、再 push」模式。

## 補充說明

- 設計時觀察到的環境：macOS、docker client 20.10.12；未安裝 `skopeo` 與 `crane`。
- 扁平化可能導致兩個來源 image 的最後一段與 tag 相同，因而對應到同一個目標；本機衝突警告是唯一的防線。若實務上發生，該重新檢視的是 retag 規則，而不是腳本結構。
- `to_target_ref` 是操作者預期會修改的唯一地方；其餘部分都應維持通用。
