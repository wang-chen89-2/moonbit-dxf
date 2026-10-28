# 为既有索引计划绑定原件

适用于已经有ValueEdit数组、或原件记录没有句柄的场景。示例沿用examples/rewrite/input.dxf和plan.json，将LINE图层old改成cut、起点X从1.0改成2.5。

```sh
moon build --target js
node examples/bind_plan/run.mjs NEW_OUTPUT_DIRECTORY
```

输出目录须尚不存在。程序复制原件和计划，执行bind-plan、patch-plan、patch；保留bound-plan.json、preview.json、write-receipt.json和patched.dxf，检查原件/原计划未变。可选第二个参数为适用于同一示例原件的自定义PLAN.json路径。

手工执行：

```sh
node tools/dxf.mjs bind-plan examples/rewrite/input.dxf examples/rewrite/plan.json > bound-plan.json
node tools/dxf.mjs patch-plan examples/rewrite/input.dxf bound-plan.json
node tools/dxf.mjs patch examples/rewrite/input.dxf patched.dxf bound-plan.json
```

bind-plan先执行现有原生计划拆封及完整的旧值/类型/结构/wire校验，成功才输出既有dxf-source-plan-v1容器。输入可以是旧数组或已绑定容器；已绑定计划必须与当前原件摘要匹配，不会把失配容器静默重新绑定。它只读原件/计划，不写DXF。

原数组中的编辑数字词法保留，例如3e0与8.0不会经JS Number重写；已有绑定容器的外层及空白可规范化，编辑数字词法仍保留。非法近整数索引、旧值不符或摘要失配均失败且无计划stdout。旧命令、数组/绑定格式及核心API不变；没有新增签名、代码页猜测、结构迁移或文件系统原子替换能力。
