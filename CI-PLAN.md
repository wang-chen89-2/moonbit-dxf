# DXF CI

`check.yml` 在 Ubuntu 24.04 上运行 JS、Wasm-GC 两个必要 job；固定 MoonBit `0.10.17+d971670cd` 和 Node.js `24.11.0`。使用项目 manifest 的既有依赖，不在本机修改全局 SDK 或 Git 配置。

两个后端均执行实际 check、build、test、fmt、公开接口一致性和公共 MoonBit 消费者。JS 文件宿主门包括独立 golden/几何对照、计划/绑定/102 消费者、严格 UTF8、输入文件身份、修复预览、物理记录接收、APPID 接收及六文件 ezdxf audit。宿主门在 Wasm-GC job 条件跳过，不表示在该后端运行了 Node 文件流程。

重复句柄入口门 `Test canonical duplicate-handle lint intake` 在 JS job 实际执行：

```sh
python3 -B tools/test_handle_lint.py "$RUNNER_TEMP/dxf-handle-lint"
```

七份小型独立完整输入覆盖前导零别名、ASCII/Binary、后续每个重复偏移、不同值/私有字段、DIMSTYLE105、16位十六进制和原有畸形字符串比较。真实 CLI 的退出状态与完整 JSON 对照冻结预期；保留 stdout/stderr，检查原件和目录内容不变。畸形字符串对照不代表合法 CAD 数据。

本地只运行受改动影响的测试及此文件门；CI 保留全部既有必要步骤。推送后须核对最终同一提交的两个必要 job 和本门实际成功，metadata 不冒充 runner 二进制或原始日志字节证明。源码 ZIP 和本地实际执行输出分别记录身份并封存，独立根 ACCEPT 后才计轮。
