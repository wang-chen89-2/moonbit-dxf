# 无句柄图纸的物理记录清单与索引编辑

导入 `wang-chen89-2/dxf` 后可调用 `doc.record_spans()`，无需预先知道记录句柄。每条 `RecordSpan` 的 `start_tag`/`end_tag` 可直接索引同一原件的 `doc.tags()`，`offset`/`end_offset` 可切取 `doc.original_bytes()`；两种结束位置均排他。返回新数组，改变数组不改变文档。

```sh
moon run examples/record_inventory --target js --deny-warn --frozen
moon run examples/record_inventory --target wasm-gc --deny-warn --frozen
```

该公共消费者使用独立手写的完整R12 ASCII/Binary输入，找到无句柄LINE范围内的code10，把2.25改为4.25，使用既有 `rewrite_values`。它逐字节对照独立构造的完整输出，核对原件不变，并通过公共decoder和新清单接收改后字段。两个后端均输出ascii/binary两条成功报告。

文件宿主可分步查看同一原件：

```sh
moon build --target js --deny-warn --frozen
node tools/dxf.mjs records drawing.dxf
node tools/dxf.mjs tags drawing.dxf
node tools/dxf.mjs bind-plan drawing.dxf plan.json > bound.json
node tools/dxf.mjs patch-plan drawing.dxf bound.json
node tools/dxf.mjs patch drawing.dxf changed.dxf bound.json
node tools/dxf.mjs tags changed.dxf
node tools/dxf.mjs records changed.dxf
```

先从清单找到目标记录，再在其标签范围内选定组码/有类型旧值，用既有索引计划格式写 `plan.json`。例如原标签确为code10且值为2.25时，expected bits为字符串 `4612248968380809216`，4.25的新bits为 `4616471093031469056`；index必须取实际同一原件中的索引，不能套用其他图纸。`bind-plan`核验计划并绑定原件SHA-256，随后预览和写出复用原有协议。输出需单独路径。

完整真实进程接收可运行：

```sh
python -B tools/test_record_inventory.py verification-output/record-inventory
```

目录须不存在。该程序以76个真实文件进程保留实际输入、输出、逐进程stdout/stderr，核对完整JSON、全部typed tags、来源摘要、已有标签/计划协议、逐字节输出和读回，涵盖两种格式、未知种类、原始编码、重复候选、原件/计划目的路径保护及来源拒绝。显式AC1009零实体文档有5条物理记录；零字节输入按旧解码器的截断签名规则拒绝。ASCII保留999注释，合法Binary用普通Text载荷；原Binary999与复合非法字节仍作为拒绝对照，另有合法Binary基底的单独wire/截断对照。

清单按每个解码code0分段，含结构控制记录；不组装POLYLINE链、嵌入对象或引用闭包。code0前标签及末尾非标签空白留在原件中。kind和候选handle保存原始Bytes，JSON以hex表达。拥有者规则与旧句柄查找共用，候选缺失、非法或重复仍如实列出，旧句柄编辑/导出仍拒绝歧义。

新入口只接受完整typed、支持版本、wire一致的非repair来源，拒绝不会收紧旧tags/save。`records`只读且恰需一个输入路径；退出0表示生成清单，2表示参数、读取或来源保护失败。ordinal和标签索引只属于该原件，应使用文件返回的source_sha256绑定后续计划；清单不替代lint或厂商CAD验收。
