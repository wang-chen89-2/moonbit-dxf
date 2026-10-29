# 开放旧式折线的线型生成标志

模块 `wang-chen89-2/dxf` 的 `GeometrySink` 可把主记录70为128的开放XY旧式 `POLYLINE/VERTEX/SEQEND` 投影为实际 moon-geometry Point2D 点列。128表示沿顶点连续生成线型，依据 [Autodesk POLYLINE 格式说明](https://help.autodesk.com/cloudhelp/2015/ENU/AutoCAD-DXF/files/GUID-ABF6B778-BE20-4B49-9B58-A94E64CEFFF3.htm)。这里消费的是点列坐标，不提供线型绘制。

在项目根执行：

```sh
moon run examples/classic_plinegen --target js --deny-warn --frozen
moon run examples/classic_plinegen --target wasm-gc --deny-warn --frozen
```

示例使用独立Python bytes/struct构造并嵌入的完整ASCII/Binary原件，分别通过公共DXF decoder、实际dxfkit多记录组装和moon-geometry对象核对三点 `(1.25,-2.5)`、`(4.5,8.75)`、`(9,3)`，以及后续LINE的完整坐标。输出两例 `upstream=2 projected=2 unprojected=0 coordinates_ok=true source_preserved=true`，最后为 `failed_cases=0`。任一条件不符会令程序失败。

主记录70允许0、128或缺省；顶点70与所有75保持0或缺省。顶点完整性、SEQEND、开放二维、零bulge/宽度/厚度/Z及默认法向条件保持。128不会授权闭合129、顶点128或非零宽度等其他profile；这些输入仍可由核心完整保存。未投影旧式候选计数与实际投影使用同一判定，重复查询不消费缓冲。

真实文件接收检查：

```sh
moon build --target js --deny-warn --frozen
python -B tools/test_classic_plinegen.py verification-output/classic-plinegen
```

输出目录须尚不存在。14份完整独立原件分别运行 `tags`、`adapters` 和 `save`，保留stdout/stderr和退出码，逐值接收全部有类型tag、核对实际上游实体数、检查完整保存字节以及输入和邻接文件未变。坐标断言来自原生真实对象；不把文件实体计数冒充完整几何验证，也不声称厂商CAD互操作或写出耐久性认证。原创模型数据采用CC0-1.0，代码MIT。
