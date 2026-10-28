# 批量保真改写

```sh
moon run examples/rewrite --target js
moon run examples/rewrite --target wasm-gc
moon build --target js
node tools/dxf.mjs tags examples/rewrite/input.dxf
node tools/dxf.mjs patch-plan examples/rewrite/input.dxf examples/rewrite/plan.json
node tools/dxf.mjs patch examples/rewrite/input.dxf rewritten.dxf examples/rewrite/plan.json
```

示例将LINE图层从old改为cut，起点X从1.0改为2.5。MoonBit示例用公开tags()定位字段，计划文件按同一原文件的0起始tag索引定位。tags命令的tags数组每项为[组码, 类型, 值]，数组位置即索引；bits和int数值是十进制字符串。

需绑定整份原件时，可运行`node tools/dxf.mjs bind-plan examples/rewrite/input.dxf examples/rewrite/plan.json > bound-plan.json`，再把bound-plan.json交给上述预览/写出命令；该入口也适用于没有句柄的记录。[完整绑定例程](../bind_plan/README.md)。

每个计划项必须恰有index、code、expected、value四个字段。expected/value恰含一个有类型字符串字段：

| 字段 | 解释 |
| --- | --- |
| text | UTF8字符串，不执行代码页转换 |
| text_hex | 原始文本字节十六进制，适用于legacy代码页 |
| integer | 十进制Int64字符串，可精确表达超过2^53的值 |
| real | Double十进制/科学记数字符串 |
| bits | Double原始有符号64位模式的十进制字符串 |
| binary_hex | Binary数据块十六进制，沿用127字节上限 |
| opaque_hex | 未知ASCII组的原始值字节十六进制 |

patch-plan执行完整校验并显示原始offset/end_offset和before_hex/after_hex；不写文件。patch成功后才写到单独输出路径，并将同样记录打印到stderr。任何旧值/组码不符、重复索引、结构/版本或wire不合法都会拒绝整项计划。JSON大整数必须用字符串，重复JSON键、非整型索引和含多个类型键的值会被拒绝。

patch的输出也必须与计划文件分开；同路径、大小写或硬链接别名都会拒绝，避免把输入计划覆盖成DXF。

前置条件只覆盖所选tag的组码与有类型旧值，RealBits按位比较。所有索引/偏移属于原文件；未选span保持原字节，所选tag可被规范化编码。空计划原样复制，非空计划沿用支持版本及完整性边界。不插入/删除tag，不更新其它引用，不修复损坏，也不迁移版本。结果缓冲在内存中；库的整项成功语义不代表文件系统原子替换。
