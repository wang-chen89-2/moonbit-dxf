# 从句柄形成批量计划

```sh
moon run examples/handle_plan --target js
moon run examples/handle_plan --target wasm-gc
moon build --target js
node tools/dxf.mjs make-plan examples/handle_plan/input.dxf examples/handle_plan/requests.json > generated-plan.json
node tools/dxf.mjs patch-plan examples/handle_plan/input.dxf generated-plan.json
node tools/dxf.mjs patch examples/handle_plan/input.dxf handle-patched.dxf generated-plan.json
```

请求把AB记录的普通图层改成cut，并把AC点列第二个X改成9。102应用组里的metadata字段保持原样。示例是记录层输入，不宣称完整CAD图纸合规性。

请求项包含handle（1–16个十六进制字符）、code、value，可选occurrence（默认0，按匹配组码的出现次序从0计数）。value格式与[第08轮批量改写](../rewrite/README.md)相同。句柄忽略ASCII大小写及前导零；查找记录自身的公共5句柄，DIMSTYLE使用105；HEADER的HANDSEED和102载荷不定义目标句柄。未给appdata选项时，目标字段跳过102应用组，XDATA可按其实际组码和次序选择；显式命名102组见[新例程](../appdata_plan/README.md)。

make-plan只读原件并完整校验拟改值，输出可直接给patch-plan/patch的第08轮计划。原tag索引、预期组码和有类型旧值自动捕获：文本写成text_hex，Double写成bits，整数写成十进制字符串，因此无需从tags的有损UTF8显示还原legacy字节。输入数字按精确整数校验，不截断小数。

MoonBit可调用`doc.value_edit_by_handle(handle, code, value, occurrence?)`捕获ValueEdit，再交给`rewrite_values`校验/写回。该定位方法本身不等于批准wire/结构改写。

找不到句柄/字段、重复目标句柄或超出出现次序会报错，不挑一个猜测。多个请求落到同一个tag由原批量校验拒绝。它只对公共句柄在首个subclass/XDATA前的正常记录定位，不提供几何区域、APPID或子类语义查询，不插入缺失字段、不修复引用或迁移版本。前置条件仍只覆盖所选tag。
