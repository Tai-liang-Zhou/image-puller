# TODO

## 掃毒未通過就不推送

在 `docker push` 之前對 image 做病毒掃描；掃描未通過的 image **不推送**，
記為失敗，並在最後的摘要中單獨列出未通過的清單。

### 行為需求

- 掃描時機：`docker load` 之後、`docker tag` / `docker push` 之前。
- 未通過的 image 不執行 push，該 tar 記為失敗（沿用現有的 per-tar 失敗機制，
  不中斷整批執行）。
- 摘要除了現有的 Succeeded / Failed，另外獨立列出「掃毒未通過」清單，
  讓它和 load / tag / push 失敗區分開來。
- 只要有任何 image 掃毒未通過，exit code 非零。
- `--dry-run` 不執行掃描。

### 待決定

- 用哪個掃描器（trivy / grype / clamav / 公司既有工具？）——決定它是新增的
  必要相依，還是找不到時跳過並警告。
- 判定標準：以嚴重度分級（例如 CRITICAL 才擋）還是有任何發現就擋。
- 掃描目標：tar 檔本身，還是 load 之後的 image。
- 是否需要保留掃描報告（輸出到檔案）。
