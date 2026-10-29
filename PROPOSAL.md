# moonbit-dxf：DXF记录保真、诊断与可控重写

`wang-chen89/dxf`是MoonBit原生ASCII/Binary DXF格式层，把原件保存、语义转换和显式修复分开，供下游几何库及文件工具复用。
面向CAD导入开发者、CAM/GIS数据处理脚本和图纸批处理工具：先检查来源文件，再准确修改指定属性，保留未理解的数据并报告处理边界。

1. 分块输入ASCII或Binary，输出有类型tag及原始字节区间；支持R10–R12与R14–R2018配置，独立完整模型实测R12/R2000/R2018，R13只保原件并诊断。
2. 整数使用Int64精确处理；Double保存IEEE754位模式，保留负零及NaN载荷。非有限值告警并拒绝转ASCII；旧代码页保存原字节，不猜测转码。
3. 保真及只读模式逐字节保存原件，含未知实体、XDATA和损坏尾部；未知Binary组码停止解码并保留RawChunk，不猜测值长，转换须明确报错。
4. 只读lint返回规则、严重度、消息和字节偏移，检查缺EOF、未闭合段/表、按十六进制值判重句柄、悬空块引用及XDATA括号；解码完整不等于图纸语义合法。
5. 显式repair输出新文件、诊断及丢弃字节数，文件CLI可先只读预览同一损失报告；ASCII处理有边界的坏行，Binary仅保留尾部之前已完整关闭的段，不承诺找回丢失内容。
6. 可按公共句柄导出精确物理记录及来源回执供文件接收方核验；提供单项改值，批量计划校验原tag索引、组码和有类型旧值，全部通过才生成结果。未选字节不变，结构及版本受保护；可选SHA256容器绑定原件，支持既有索引计划绑定。
7. 按公共句柄、组码、次序、命名102组或XDATA APPID形成计划；APPID提供有类型读取及文件接收，嵌套列表按源码次序计数，歧义/目标坏结构拒绝猜测。JSON须严格UTF8，文件写出保护原件与计划的路径及硬链接别名。
8. tag回调连接dxfkit与moon-geometry；投影ENTITIES的LINE/CIRCLE、LWPOLYLINE和受限开放XY旧式POLYLINE，隔离BLOCKS/102私有字段，并只读统计未投影旧式候选。

核心编解码、诊断、修复、选择与计划校验由MoonBit实现；Node负责文件、摘要和输入保护，ezdxf仅作独立验证。适配器复用上游组装及几何对象。
最短例程：安装MoonBit（moonc v0.10.17或兼容版）并解析依赖，在项目根执行：

```sh
moon run examples/classic_polyline --target wasm-gc
```
产出`vertices=3`及三点(1.25,-2.5)、(4.5,8.75)、(9,3)，程序同时断言Binary原件保存不变；文件CLI用法见README。
独立贡献是可保留未知内容的Binary记录层、可定位诊断及带前置条件的局部改写，与dxfkit的实体组装、moon-geometry的几何模型形成分工。
完成度由JS/Wasm-GC回归、真实上游对象断言及独立ezdxf回读支持；三版本模型共3,719个有序tag完成对照，六份转码输出audit无错误/修复。字节保真与语义验收分别验证。
关键边界：不支持全实体语义、ACIS/SAT、任意坏Binary重同步、结构插删、版本迁移或引用自动更新；闭合/空间/曲线旧式折线不投影。完整缓冲占O(输入)内存，无性能或厂商CAD认证承诺。
源码仓库：[wang-chen89-2/moonbit-dxf](https://github.com/wang-chen89-2/moonbit-dxf)；模块仍为wang-chen89/dxf，当前版本0.1.0，未发布Mooncakes；GitHub源码发布不代表赛事验收。
根LICENSE为MIT；dxfkit 0.1.1为Apache-2.0，moon-geometry 0.251.0及验证用ezdxf 1.4.3为MIT。自建模型数据CC0-1.0；厂商文档不改许可、不捆绑未获授权图纸，详见THIRD_PARTY_NOTICES。
