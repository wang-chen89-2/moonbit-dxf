# 精确物理记录的文件交接

公共 API：`doc.record_by_handle(handle)` 返回既有 `RawChunk {offset, bytes}`。它读取原件，按公共 owning handle 定位一个物理记录，返回从其 code0 到下个 code0 前的原始字节；最后一条记录结束于其最后已解析 tag 的 end_offset。不会重编码数值、换行或文本，也不消费/修改 document。

```sh
moon run examples/record_handoff --target js --deny-warn --frozen
moon run examples/record_handoff --target wasm-gc --deny-warn --frozen
moon build bridge --target js --deny-warn --frozen
node tools/dxf.mjs record original.dxf chosen.record AB 2> chosen.receipt.json
node examples/record_handoff/receive.mjs original.dxf chosen.record chosen.receipt.json
```

替换原件路径和句柄即可处理自己的输入；不依赖fixture路径。生产者要求完整有类型、受支持版本、wire一致的非repair源。句柄采用已有规则：1–16位hex、忽略大小写/前导零、普通5/DIMSTYLE105；102私有字段及HEADER HANDSEED不定义拥有者，缺失/歧义拒绝。新入口允许LosslessRoundTrip/ReadOnlyLint，拒绝PermissiveRepair及未解析尾部，旧操作合同不变。

OUTPUT是原wire的记录片段，不含额外Binary文件头。stderr收据恰含`requested_handle,source_sha256,record_sha256,version,binary,offset,end_offset`。完整原始记录包括102私有载荷、subclass和embedded字段，不作脱敏。POLYLINE/VERTEX/SEQEND及INSERT/ATTRIB仍是独立物理记录；片段不声称是完整逻辑实体、独立图纸或引用闭包。

接收程序读取三个实际文件，检查两个真实摘要、区间/长度及原件slice相等，再使用原公共选择器确认拥有者和原始span。它依据实际源profile加入临时控制framing，把不变payload交给公共MoonBit decoder，确认只收到一条物理记录。stdout给出已验证来源索引和typed tags；text值沿用现有tags的UTF8显示，原字节以附件和摘要为准。临时缓冲的offset不作原件offset，也不被当作独立CAD图纸输出。需提供原件才能验证来源成员关系；摘要字符串本身不证明采用者或真实性。

生产者成功退出0，参数/读取/源/句柄/别名/写出失败退出2。源/查询/别名在写前完整校验，使用已有文件身份保护；独立既有目标仍可写出。晚期I/O错误可能已截断或部分写入目标，没有原子替换或回滚保证。接收方只读，失败退出2且不输出成功索引；过期源、损坏片段/收据、错误区间/profile/拥有者都会拒绝。

独立模型/原始byte期待与真实进程回归：

```sh
python -B tools/test_record_handoff.py NEW_EVIDENCE_DIRECTORY
```

目录须尚不存在。覆盖现代ASCII/Binary、合法R12双wire、CRLF/非规范数值词法、DIMSTYLE105、未知记录、POLYLINE物理头及最后完整tag边界，并用实际硬链接确认新动作的源保护。最后tag样本刻意是有类型但缺结构结束标记的记录流，证明API不把typed complete冒充图纸完整。输入/期待由手写bytes/tag与Python struct构造，数据CC0-1.0，代码保留MIT；无第三方采用、厂商CAD或全图语义认证声明。
