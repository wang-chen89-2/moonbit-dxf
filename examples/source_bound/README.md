# 可选原件绑定计划

```sh
moon build --target js
node examples/source_bound/run.mjs NEW_OUTPUT_DIRECTORY
```

目录须为尚不存在的新路径。程序复制既有handle_plan样例，生成绑定计划、预览并写出；再修改副本的一处未选metadata，验证同一绑定计划被拒绝且不创建输出。

也可逐步运行：

```sh
node tools/dxf.mjs make-bound-plan examples/handle_plan/input.dxf examples/handle_plan/requests.json > bound-plan.json
node tools/dxf.mjs patch-plan examples/handle_plan/input.dxf bound-plan.json
node tools/dxf.mjs patch examples/handle_plan/input.dxf bound-patched.dxf bound-plan.json
```

格式为`{"format":"dxf-source-plan-v1","source_sha256":"64位hex","edits":[原批量计划项]}`。Node文件宿主对实际输入Buffer计算SHA256；预览和写出都会核对，再调用原有有类型前置条件/结构/wire校验。成功记录含已核对的source_sha256。未选字节也属于绑定范围，任何原件字节变化都会使旧绑定失配。

旧make-plan仍输出数组，旧数组计划仍按所选tag条件工作。JSON拆封由MoonBit执行并保留数字词法，宿主不会把用户edits数组经过JS Number重写。make-bound-plan封装的是MoonBit生成的规范计划：索引/组码为Int32，数值payload为字符串。

已有索引数组计划可用`bind-plan INPUT PLAN.json`完整校验后绑定，原数组数字词法保留，无需转换成句柄请求；没有句柄的记录也可使用。输入若已是绑定容器，先核对原摘要，失配时拒绝重新绑定。该命令只输出计划JSON，不改输入或写DXF；见[可运行既有计划例程](../bind_plan/README.md)。

绑定核对当前读取的文件字节，签名、身份认证和文件系统原子替换不在范围内。核心记录API仍保持原来的所选值合同；bridge.unwrap_source_plan只解析结构与提取metadata，其他宿主须自行核对摘要后才调用apply_edits_hex。目录/文件预算、未知格式和记录修改边界沿用原工具。
