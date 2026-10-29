# APPID 范围的读取、改值与文件接收

当同一记录含多个应用的 XDATA 时，应用可按公共拥有者句柄和精确 APPID 选择已有值。它与默认的全记录组码/次序选择各自保持原有范围；不需要调用方先计算其他应用占用的 occurrence。

```sh
moon run examples/xdata_plan --target js --frozen
moon run examples/xdata_plan --target wasm-gc --frozen
moon build bridge --target js --frozen
python3 -B tools/test_xdata_workflow.py /tmp/dxf-xdata-example
```

最后一条命令从独立 bytes/struct 模型生成真实文件，运行六条完整链：R12、R2000、R2018，各含 ASCII/Binary。输出目录必须不存在；保留输入、计划、实际输出、逐个进程原始 stdout/stderr 和接收数据。预期输入/输出、tag 索引及类型值在实现前独立构造，输出逐字节核对。

应用的请求仍使用现有数组，只增加显式 `xdata` 选项，与 `appdata` 互斥：

```json
[
  {"handle":"F1","xdata":"APP_B","code":1000,"occurrence":1,"value":{"text":"reviewed-beta"}},
  {"handle":"F1","xdata":"APP_B","code":1071,"value":{"integer":"2000000001"}}
]
```

```sh
node tools/dxf.mjs make-plan source.dxf requests.json > plan.json
node tools/dxf.mjs patch-plan source.dxf plan.json
node tools/dxf.mjs patch source.dxf patched.dxf plan.json
node examples/xdata_plan/receive.mjs patched.dxf F1 APP_B
```

也可用既有 `make-bound-plan` 形成原件绑定容器。计划及原有收据格式不变，替换仍由整批旧值/类型/wire 校验批准。真实接收方从改写后的 DXF 读取 APP_B，输出 `{handle,application,data}`；每项含 `code` 及现有 typed-value 形状，如 `text_hex`、`integer`、`binary_hex`。原始文本和二进制值不会经过通用 tags 的 UTF8 显示转换。这个接收方属于本项目，并不代表第三方 CAD 验收。

MoonBit 用户可调用 `doc.xdata_by_appid(handle, application)` 取得新的 `Array[Tag]`，包含原有类型值及绝对字节区间；调用 `doc.value_edit_in_xdata(handle, application, code, value, occurrence?)` 形成现有 `ValueEdit`，再交给 `rewrite_values`。示例同时核对原件、APP_A、相邻记录的 APP_B 均未改变。

范围由一条公共 `1001` marker 开始，至下一条公共 `1001` 或物理记录结束；读取结果不含 marker 和私有 102 组，包含 1002 列表控制符。名字按 UTF8 字节精确比较，须非空、最多 31 字节且不含 NUL/CR/LF；不做大小写折叠或旧代码页推断。公共拥有者查找复用既有句柄、完整性及版本/wire 规则，私有伪 marker 不建立应用范围。

同一应用内 occurrence 按指定组码的源码次序计数，包含嵌套且平衡的 1002 列表；不按列表名称或路径搜索。返回任何值之前，检查完整目标范围：重复目标 APPID、无效/不平衡的 1002、公共非 XDATA 字段、未关闭的私有组都拒绝。空应用可读取为 `[]`，但不存在的字段无法改写；选择器只接受 1000..1071，排除 1001/1002。其他应用不会并入目标，也不对它们作新的模式验证。

本接口不新增/删除应用块、不注册 APPID、不认证应用载荷模式或注册表/引用关系，也不提供完整逻辑实体闭包。原有默认请求、102 选择、记录导出、JSON 输入及文件保护继续使用既有合同。
