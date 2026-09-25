# Dry-run 對應表（範例）

由 `retag-push.sh <tar_dir> harbor.example.com/myproject --dry-run` 產生，
共 56 個 tar，全部成功、無目標名稱衝突。

> 來源名稱取自各 tar 內 `manifest.json` 的 `RepoTags`；此表假設其內容與檔名
> （去掉 `.tar`）相同。實際批次請先自行跑一次 `--dry-run` 核對。

## 對應規則摘錄

- 只保留來源名稱的最後一段路徑。
- 沒有 tag（或 tag 為 `latest`）時，以**最後一個**底線切成名稱與 tag。
- 有明確 tag 時原樣保留。
- 名稱中剩餘的連字號一律改成底線；tag 中的連字號保留。
- 五段純數字且結尾為 `.0` 的 tag 縮短為四段（`5.1.0.19.0` -> `5.1.0.19`）；上游三段版號不動。

## 分類依據

以版號體系判斷：帶 `5.1.0.19` 的是 vendor 自家建置，帶各自上游版號的是第三方。
注意 `httpd`、`rabbitmq`、`spark`、`oracledb-exporter`、`sftp` 雖然是開源軟體，
但都掛 vendor 的建置版號，因此歸在 vendor 建置。

## 第三方上游元件（7）

| 來源 image | 目標 image | 上游專案 |
| --- | --- | --- |
| `configmap-reload_v0.5.0` | `harbor.example.com/myproject/configmap_reload:v0.5.0` | jimmidyson/configmap-reload |
| `grafana_12.2.0` | `harbor.example.com/myproject/grafana:12.2.0` | Grafana |
| `kube-state-metrics_v2.5.0` | `harbor.example.com/myproject/kube_state_metrics:v2.5.0` | kube-state-metrics |
| `loki_3.5.0` | `harbor.example.com/myproject/loki:3.5.0` | Grafana Loki |
| `otel_0.147.0` | `harbor.example.com/myproject/otel:0.147.0` | OpenTelemetry Collector |
| `prometheus_v2.36.2` | `harbor.example.com/myproject/prometheus:v2.36.2` | Prometheus |
| `tempo_2.8.2` | `harbor.example.com/myproject/tempo:2.8.2` | Grafana Tempo |

## 需人工確認（1）

| 來源 image | 目標 image | 說明 |
| --- | --- | --- |
| `rabbitmq_readiness_v2.0` | `harbor.example.com/myproject/rabbitmq_readiness:v2.0` | 版號自成體系（`v2.0`），但看名稱像是 rabbitmq 的 readiness probe 輔助工具，無法從檔名判斷是上游元件還是 vendor 自製 |

## Vendor 建置（48）

| 來源 image | 目標 image |
| --- | --- |
| `adbmonitor_5.1.0.19.0` | `harbor.example.com/myproject/adbmonitor:5.1.0.19` |
| `archivedelete_5.1.0.19.0` | `harbor.example.com/myproject/archivedelete:5.1.0.19` |
| `copysharedfiles_5.1.0.19.0` | `harbor.example.com/myproject/copysharedfiles:5.1.0.19` |
| `datasetpodcleaner_5.1.0.19` | `harbor.example.com/myproject/datasetpodcleaner:5.1.0.19` |
| `dbdataset_5.1.0.19` | `harbor.example.com/myproject/dbdataset:5.1.0.19` |
| `dbsyncparllel_5.1.0.19.0` | `harbor.example.com/myproject/dbsyncparllel:5.1.0.19` |
| `defectloader_5.1.0.19.0` | `harbor.example.com/myproject/defectloader:5.1.0.19` |
| `disposer_5.1.0.19.0` | `harbor.example.com/myproject/disposer:5.1.0.19` |
| `emailnotifier_5.1.0.19.0` | `harbor.example.com/myproject/emailnotifier:5.1.0.19` |
| `error-truncate_5.1.0.19.0` | `harbor.example.com/myproject/error_truncate:5.1.0.19` |
| `gen3dloader_5.1.0.19.0` | `harbor.example.com/myproject/gen3dloader:5.1.0.19` |
| `httpd_5.1.0.19.0` | `harbor.example.com/myproject/httpd:5.1.0.19` |
| `idsrv_5.1.0.19` | `harbor.example.com/myproject/idsrv:5.1.0.19` |
| `imagedelete_5.1.0.19.0` | `harbor.example.com/myproject/imagedelete:5.1.0.19` |
| `imageqmgr_5.1.0.19.0` | `harbor.example.com/myproject/imageqmgr:5.1.0.19` |
| `imagesweeper_5.1.0.19.0` | `harbor.example.com/myproject/imagesweeper:5.1.0.19` |
| `intransporter_5.1.0.19.0` | `harbor.example.com/myproject/intransporter:5.1.0.19` |
| `kd-table-purge_5.1.0.19.0` | `harbor.example.com/myproject/kd_table_purge:5.1.0.19` |
| `kla-customexporter_5.1.0.19.0` | `harbor.example.com/myproject/kla_customexporter:5.1.0.19` |
| `klarfqmgr_5.1.0.19.0` | `harbor.example.com/myproject/klarfqmgr:5.1.0.19` |
| `loadtimeexecutor_5.1.0.19` | `harbor.example.com/myproject/loadtimeexecutor:5.1.0.19` |
| `log_truncate_5.1.0.19` | `harbor.example.com/myproject/log_truncate:5.1.0.19` |
| `lte_5.1.0.19` | `harbor.example.com/myproject/lte:5.1.0.19` |
| `machapi_5.1.0.19.0` | `harbor.example.com/myproject/machapi:5.1.0.19` |
| `machui_5.1.0.19.0` | `harbor.example.com/myproject/machui:5.1.0.19` |
| `monitor-files_5.1.0.19.0` | `harbor.example.com/myproject/monitor_files:5.1.0.19` |
| `oracledb-exporter_5.1.0.19.0` | `harbor.example.com/myproject/oracledb_exporter:5.1.0.19` |
| `patchimageconsumer_5.1.0.19.0` | `harbor.example.com/myproject/patchimageconsumer:5.1.0.19` |
| `podcleanup_5.1.0.19` | `harbor.example.com/myproject/podcleanup:5.1.0.19` |
| `psmonitor_5.1.0.19.0` | `harbor.example.com/myproject/psmonitor:5.1.0.19` |
| `queuepublisher_5.1.0.19.0` | `harbor.example.com/myproject/queuepublisher:5.1.0.19` |
| `rabbitmq_5.1.0.19.0` | `harbor.example.com/myproject/rabbitmq:5.1.0.19` |
| `recipeexecutor_5.1.0.19` | `harbor.example.com/myproject/recipeexecutor:5.1.0.19` |
| `rsapi_5.1.0.19.0` | `harbor.example.com/myproject/rsapi:5.1.0.19` |
| `rsprbdb_5.1.0.19` | `harbor.example.com/myproject/rsprbdb:5.1.0.19` |
| `rsui_5.1.0.19.0` | `harbor.example.com/myproject/rsui:5.1.0.19` |
| `scheduler_5.1.0.19` | `harbor.example.com/myproject/scheduler:5.1.0.19` |
| `serverdataapi_5.1.0.19` | `harbor.example.com/myproject/serverdataapi:5.1.0.19` |
| `servicefactory_5.1.0.19` | `harbor.example.com/myproject/servicefactory:5.1.0.19` |
| `sftp_5.1.0.19` | `harbor.example.com/myproject/sftp:5.1.0.19` |
| `spark_5.1.0.19.0` | `harbor.example.com/myproject/spark:5.1.0.19` |
| `spotmonitor_5.1.0.19.0` | `harbor.example.com/myproject/spotmonitor:5.1.0.19` |
| `spotsummary_5.1.0.19.0` | `harbor.example.com/myproject/spotsummary:5.1.0.19` |
| `tffloader_5.1.0.19.0` | `harbor.example.com/myproject/tffloader:5.1.0.19` |
| `udbnotifier_5.1.0.19.0` | `harbor.example.com/myproject/udbnotifier:5.1.0.19` |
| `udn_5.1.0.19.0` | `harbor.example.com/myproject/udn:5.1.0.19` |
| `udngpu_5.1.0.19.0` | `harbor.example.com/myproject/udngpu:5.1.0.19` |
| `utilityexecutor_5.1.0.19` | `harbor.example.com/myproject/utilityexecutor:5.1.0.19` |
