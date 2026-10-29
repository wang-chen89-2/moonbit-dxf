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
node tools/dxf.mjs verify-patch examples/handle_plan/input.dxf bound-patched.dxf bound-plan.json
```

格式为`{"format":"dxf-source-plan-v1","source_sha256":"64位hex","edits":[原批量计划项]}`。Node文件宿主对实际输入Buffer计算SHA256；预览和写出都会核对，再调用原有有类型前置条件/结构/wire校验。成功记录含已核对的source_sha256。未选字节也属于绑定范围，任何原件字节变化都会使旧绑定失配。

旧make-plan仍输出数组，旧数组计划仍按所选tag条件工作。JSON拆封由MoonBit执行并保留数字词法，宿主不会把用户edits数组经过JS Number重写。make-bound-plan封装的是MoonBit生成的规范计划：索引/组码为Int32，数值payload为字符串。

已有索引数组计划可用`bind-plan INPUT PLAN.json`完整校验后绑定，原数组数字词法保留，无需转换成句柄请求；没有句柄的记录也可使用。输入若已是绑定容器，先核对原摘要，失配时拒绝重新绑定。该命令只输出计划JSON，不改输入或写DXF；见[可运行既有计划例程](../bind_plan/README.md)。

绑定核对当前读取的文件字节，签名、身份认证和文件系统原子替换不在范围内。核心记录API仍保持原来的所选值合同；bridge.unwrap_source_plan只解析结构与提取metadata，其他宿主须自行核对摘要后才调用apply_edits_hex。目录/文件预算、未知格式和记录修改边界沿用原工具。

`verify-patch SOURCE RECEIVED BOUND_PLAN.json`供整文件接收方使用，恰需三个输入路径，全部只读。它先核对绑定源摘要，复用原生计划的全部既有审批，再比较完整实际接收Buffer与预期改写Buffer。成功JSON含原`source_bytes`、`output_bytes`、`changes`、`source_sha256`，另加`verified:true`与实际读到文件的`output_sha256`；失败退出2且没有成功stdout。即便接收文件可解析、数值相同或只是多一个空白字节，若不等于该计划的完整结果也拒绝。它不接收旧数组作为核验计划；旧数组预览和写出合同保持。

空计划继续沿用原生`rewrite_values([])`的原字节身份合同，不触发非空编辑的完整性/版本/wire审批；即使来源只供身份检查，也不意味着该DXF语义有效。只读空计划核验可以让RECEIVED与SOURCE为同一文件或真实硬链接，不改任何文件。非空计划仍按原来的保护顺序拒绝不完整、超支持版本、wire冲突、旧值不匹配或结构改值。

JS构建后可运行 `python -B tools/test_patch_receiving.py verification-output/patch-receiving`，输出目录须不存在。77个实际文件进程用独立bytes/struct模型核对R12/R2000/R2018两种wire的完整源/输出/typed tags、未排序多项计划和原收据，随后真实接收整份文件；还覆盖选中/未选字节篡改、词法等值变化、截断/追加、空计划身份、原数组兼容、源/计划目的保护、真实只读硬链接，以及绑定/原生审批/UTF8/IO/用法拒绝无写入。期望字节和摘要由独立声明生成，不由产品writer倒填。该接收核验本身复用产品writer，因此不声称它是writer算法的独立证明。
