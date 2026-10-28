# 查看旧式折线投影的遗漏候选

```sh
moon run examples/projection_status --target js
moon run examples/projection_status --target wasm-gc
```

已知输入有三条实体：闭合旧式折线、开放XY旧式折线和LINE。目标模型保持原来的有限投影规则，程序输出`projected=2`、`unprojected_classic=1`，并断言原件保存字节不变。示例和测试的参数数据为本项目原创，按CC0-1.0提供；代码沿用根MIT许可。

`GeometrySink::unprojected_classic_count()`只读当前缓冲快照，统计未被现有策略投影的ENTITIES旧式POLYLINE候选。未完整到达SEQEND的序列暂计为1，完成合法开放序列后可变为0；查询不消费或清空输入。

此计数不含ARC/TEXT等其他未支持种类，不统计BLOCKS中的局部图元，也不把102私有字段当几何标志。0不代表整图投影完整或已通过CAD审计。查询扫描缓冲数据并复用现有dxfkit组装过程，可能分配对象；没有零开销或低内存承诺。
