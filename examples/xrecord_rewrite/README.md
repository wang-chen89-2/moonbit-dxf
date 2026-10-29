# 公开 XRECORD 文本的安全改值与接收

XRECORD 的 `AcDbXrecord` 载荷可以使用普通 code9 存储文本，它不是 HEADER 变量名。本例通过既有公共拥有者选择、single/batch 改值和完整读回，验证该载荷无需整图迁移。

```sh
moon run examples/xrecord_rewrite --target js --frozen
moon run examples/xrecord_rewrite --target wasm-gc --frozen
moon build bridge --target js --frozen
python3 -B tools/test_xrecord_rewrite.py /tmp/dxf-xrecord-rewrite
```

最后的目录须不存在。文件消费者用独立 bytes/struct 模型生成完整 ASCII/Binary 原件和预期结果，实际运行 `make-bound-plan → patch-plan → patch → tags`，核对完整计划、收据、类型序列及每个输出字节。请求还是原有形状：

```json
[{"handle":"B1","code":9,"value":{"text":"reviewed-key"}}]
```

只对公开 XRECORD 在公开 `100/AcDbXrecord` 标记之后、下一个 code0 之前的普通 code9 放行。先前的公共 5 句柄、重复字段 occurrence 和 typed 旧值语义不变；不需要新 API、计划/绑定容器或收据格式。未确认载荷上下文、前置9、私有伪标记和下一记录不会继承权限。

真实 HEADER 键、版本值、code0 和 SECTION/TABLE 名称仍保护；同批夹带这些字段会整体拒绝。过期旧值、错误类型、原件摘要和 wire 分隔符检查保持。ASCII 不能注入 LF/CR/NUL；Binary 文本仍允许 LF，禁止 NUL，不把合法 Binary 载荷缩成 ASCII 限制。

样本原件包含 HEADER、LINE、字典和 XRECORD；只改 B1 的目标文本，原件、邻字段、引用和所有未选字节保持。额外样本覆盖重复9与内容恰为 `$ACADVER` 的载荷，内容拼写不改变字段角色。保留原始格式和数据不代表认证任意 XRECORD 的应用模式、字典引用或第三方 CAD 语义。本项目自编接收方不是外部采用证明。
