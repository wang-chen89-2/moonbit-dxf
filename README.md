# moonbit-dxf

源码仓库：[wang-chen89-2/moonbit-dxf](https://github.com/wang-chen89-2/moonbit-dxf)。模块与原作者标识保持 `wang-chen89/dxf`。

原生 MoonBit ASCII/Binary DXF 有类型记录流、原字节保留、显式修复与记录级诊断。模块名 `wang-chen89/dxf`，版本 0.1.0，尚未发布到 Mooncakes。它为 DXF 导入、检查、脚本重写与既有几何库提供格式层；不重复实现 OCS、bulge 或块拍平。

需要 MoonBit **v0.10.17** 或兼容新版、Node.js 20+（文件 CLI）；CI 固定 MoonBit `0.10.17+d971670cd` 和 Node.js 24.11.0，并记录实际工具版本。核心包只引用 MoonBit core；`adapters` 使用已发布的 `mik1e80/dxfkit@0.1.1` 和 `walkzzz/moon-geometry@0.251.0`。依赖按模块 manifest 下载，几何代码不计为本库自研。

```sh
moon check --target js --deny-warn
moon build --target js --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon run examples/inspect --target wasm-gc
node tools/dxf.mjs lint fixtures/r2018-binary.dxf
node tools/dxf.mjs ascii fixtures/r2018-binary.dxf drawing-ascii.dxf
node tools/dxf.mjs binary fixtures/r2018-ascii.dxf drawing-binary.dxf
node tools/dxf.mjs adapters fixtures/r2018-binary.dxf
```

CLI 转换/修复需单独输出路径，按文件身份拒绝覆盖输入，包括Windows大小写别名和硬链接。`lint` 退出0表示没有当前退出规则的问题，1表示检出缺陷/不完整，2表示参数、文件或转换失败；不是 AutoCAD 合规认证。`repair` 将损失字节数和诊断打印到stderr，原件不变。

`patch`写出同时保护DXF原件和计划文件两个输入，输出不能指向任一输入或其文件别名；旧数组计划和原件绑定容器均适用。单独的既有目标仍按原行为允许写出。

CLI请求/计划JSON文件须为有效UTF-8；非法字节会退出2，不生成计划或写出DXF，不再静默替换成`�`。合法Unicode及显式U+FFFD照常保留；`text_hex`等ASCII十六进制载荷继续表达原始DXF字节，此检查不对DXF原件猜测转码。

该文件宿主合同有独立的进程级回归，可在JS构建后运行（需Python 3）：

```sh
moon build --target js --deny-warn
python -B tools/test_cli_utf8.py verification-output/cli-utf8
```

输出目录须尚不存在，保留逐进程结果与输入/输出证据。Python严格解码独立确认单个非法字节、过长编码和截断多字节反例；回归覆盖请求、数组/原件绑定计划的拒绝路径、无计划stdout、输入/既有目标保留和不创建新DXF。合法Unicode链的完整输出另与已知单处原始字节替换预期比较，包含显式U+FFFD。GitHub Actions的JS任务执行此回归；它验证既有JSON入口合同，不扩展DXF编码处理。

## 三种模式与明确改写

| 操作 | 行为与保真终点 |
| --- | --- |
| `LosslessRoundTrip` | `save()` / `original_bytes()` 与完整原输入逐字节相等，包括未知实体、XDATA、字典和损坏尾部；这不表示未知语义已解析 |
| `ReadOnlyLint` | 原输入只读，`lint()` 返回含 code/severity/message/字节offset 的诊断；`save()` 原样输出 |
| `PermissiveRepair` | `repair()` / `save()` 显式生成新文件；返回修复前诊断、修复警告和discarded_bytes，保留`original_bytes()` |
| `to_binary()` / `to_ascii_bytes()` | 语义格式转换，按组码类型重编码；未知类型或未解析尾部报错，不能用这两个函数证明原始文本词法/格式相等 |
| `rewrite_value(index, value)` | 在原格式替换一个已知值；其他输入span保持原字节，结构/版本编辑被拒绝，不自动修复引用 |
| `rewrite_values(edits)` | 校验同一原件的多处tag组码/旧值前置条件，全部成功后一次拼接新Bytes及逐处before/after字节记录 |

`is_complete()`指整个字节流已分解为有类型tag，不代表语义或段结构合法；仍须检查`lint()`。解析异常、未知Binary组码和截断以诊断与`raw_tail()`保留；资源超限通过`DxfError`返回。未覆盖记录不能被当成“检查通过”。

公共调用示例（在消费者moon.pkg中导入`"wang-chen89/dxf"`）：

```mbt
let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
let exact_original = doc.original_bytes()
let diagnostics = doc.lint()
let binary = doc.to_binary() // raises DxfError for unsupported conversion
```

批量改写的`ValueEdit`包含`index/expected_code/expected/value`；`RewriteResult`含`bytes/changes`，每个`ValueChange`记录原始索引、组码、字节区间和before/after。输入计划可乱序，重复/越界/前置条件不符会整体拒绝；原document不变。空计划返回原件，非空计划保持现有结构/版本/wire保护。实现排序计划、扫描结构保护并一次拼接源字节；需要缓冲完整输入/输出，没有低内存承诺。

结构保护按102应用组作用域区分私有载荷：按原tag索引的计划可改其中已知类型元数据（如code9文本），不再误当HEADER变量名。真实SECTION/TABLE名称、HEADER键和版本仍锁定；默认句柄请求继续跳过应用私有字段。

可运行的MoonBit及JSON计划见[examples/rewrite](examples/rewrite/README.md)。CLI新增`tags INPUT`、`patch-plan INPUT PLAN.json`（只显示校验记录）和`patch INPUT OUTPUT PLAN.json`；旧CLI/API继续保留。未选范围逐字节保持，所选tag可规范化编码；不插入/删除tag或自动更新引用，文件宿主不提供原子替换承诺。

按记录句柄形成计划可用`value_edit_by_handle(handle, code, value, occurrence?)`与CLI `make-plan INPUT REQUESTS.json`。默认请求查找公共5句柄（DIMSTYLE为105），按组码/出现次序捕获原始有类型旧值，跳过102应用数据；输出兼容现有批量计划，文本用原始hex、Double用bits，避免把tags的有损显示当作旧字节。缺失/重复句柄或字段超界会拒绝。[普通字段示例](examples/handle_plan/README.md)。

需准确选择既有102私有字段时，请求可显式增加`"appdata":"应用名"`，或调用`value_edit_in_appdata(handle, application, code, value, occurrence?)`。只匹配唯一同名顶层组的直属字段，名称按UTF8字节精确比较，子组字段不计数；重名/未闭合目标组拒绝猜测。旧默认请求、计划数组和绑定容器不变；不提供XDATA APPID、子类/几何查询或完整应用语义认证。[命名应用组运行示例](examples/appdata_plan/README.md)。

需要确认整份原件时，文件CLI可用`make-bound-plan INPUT REQUESTS.json`生成含SHA256的可选容器；`patch-plan/patch`先核对当前输入字节，再做原有值/结构校验，成功记录摘要。旧make-plan默认数组及其所选tag合同保持不变。JSON拆封/数值词法由MoonBit处理，实际摘要由Node文件宿主计算；未增加核心依赖。[可运行原件绑定示例](examples/source_bound/README.md)。

已有按索引编写的计划（包括没有句柄的记录）可用`bind-plan INPUT PLAN.json`先完整校验，再向stdout输出同一原件绑定容器；不改原件/计划，不写DXF。编辑数字词法保留；若输入已绑定，须先匹配当前原件，失配不会被重新绑定。[既有计划绑定示例](examples/bind_plan/README.md)。

`DxfDecoder::new(mode?, max_bytes?, max_tags?, max_tag_bytes?)`的`feed(Bytes)`逐次发出完整tag，`finish()`处理尾部。默认上限64MiB输入、100万tag、1MiB单tag；有原件保真需求，解码器保留O(input)内存。不要无限制复用同一decoder；finish后feed/finish均报错。`write_to(binary~, callback)`逐tag写出，消费者异常向上传播。

## 格式与版本边界

支持组码定义的文本原字节、带符号Int16/32/64、布尔、IEEE754原始Int64位模式及二进制块。Int64不经Double/JS Number；无编辑保留signed zero及NaN payload，非有限值lint警告，转换为ASCII时拒绝。字符串按原编码字节保存；2007+ UTF8会被检查，旧代码页不猜测转码。Unicode escape词法原样保留；`to_ascii()`是严格UTF8 String便利入口，旧代码页请使用`to_ascii_bytes()`。

整型ASCII字段也接受数学上为整数的十进制科学记数法（包括Autodesk的1071示例`1.95059E+06`），按十进制数字精确归一化后再检查位宽；不会经Double舍入Int64。非整数、越界或缺失指数仍返回诊断并保留原件。

组码和整数值明确按十进制读取，不将`0x/0o/0b`前缀默认为其它进制；这些原始坏值仍可原样保存。文本字段中的同样字符不受影响。日期/编辑时长HEADER字段按DXF规定的Double记录值保留，不擅自转换成Unix秒或UTC时间。

| ACADVER | Binary组码配置 | 实测范围 |
| --- | --- | --- |
| AC1006 / AC1009（R10–R12） | 单字节普通码，255 + LE16 XDATA码 | R12有ezdxf独立完整模型；R10为配置回归 |
| AC1014 / 1015 / 1018 / 1021 / 1024 / 1027 / 1032 | LE16组码 | R2000/R2018有ezdxf独立完整模型；其他为配置回归 |
| AC1012（R13）及其他版本 | 只保留原件并诊断，拒绝语义转换 | R13历史宽度资料分歧尚未裁决 |

22字节标识为`AutoCAD Binary DXF\r\n\x1a\x00`。ACADVER只从HEADER中读取，忽略其间的999注释；其他记录的同名字段不声明版本。无ACADVER时按wire推断R12/R2018并告警，推断不是版本认证。未知实体名称和已知类型组码按有序tag保存；未知Binary组码的值长度不可猜测，保留从该码起的RawChunk，停止解码。ASCII未知码保留两行原值，不能转为Binary；Binary不接受组999注释，跨格式遇到999明确报错。

此版本没有ACIS/SAT、代理内部类语义、字体、图形重建或全版本全实体合规认证。`CLASSES`、`OBJECTS`、XRECORD、字典和代理的已知类型tag原序保存，但不替调用者证明它们的引用约束；不会修改不透明payload内的句柄。

## Lint与有限修复

五类主要规则：未闭合段、缺EOF、重复句柄（含DIMSTYLE 105例外）、悬空INSERT块名、XDATA列表不平衡；另有未闭合TABLE、非法文本、未知尾部、版本/宽度不一致等诊断。重复句柄与缺块只诊断，不擅自更名或删除对象。

TABLE缺少ENDTAB时，即使后续TABLE正常闭合，也会在下一TABLE的原始字节offset报告`UnclosedTable`；不会用后表的结束标记掩盖前表缺失。只读保存仍保持原字节，显式repair保留该诊断，不擅自补表边界。

块名按原字节进行ASCII大小写匹配；旧代码页名不再因UTF8失败合并为空名，无法显示为UTF8的缺块诊断给出原始十六进制名，不猜测代码页转换。

102应用定义组内的值不冒充记录自己的句柄、块名或XDATA控制符；原始载荷及通用值诊断仍保留。此处不宣称完整应用数据结构验证。

ASCII repair可跳过有物理边界的坏行对、替换UTF8非法字节及NUL/CR、补ENDSEC/EOF；不会声称找回被丢弃的数据。Binary repair仅在截断/未知尾部时保留最后一个完整关闭section之前的tag，附丢弃字节数并加EOF；没有可用section则报错。不做任意Binary字节滑窗重同步。repair不保证消除所有lint缺陷，更不保证ezdxf会接受任意坏图。

Binary即使恰好截在tag边界，只要section未闭合，也只保留此前完整section；单独的ENDSEC不算完整section。repair拒绝wire/version冲突及EOF后额外完整记录，避免隐式版本迁移或静默丢字段。`rewrite_value`保护SECTION/TABLE的第一个code2名称和版本声明，普通INSERT块名、HEADER的UCS名称仍可编辑；Opaque值也不能注入换行/NUL边界。

## 真实几何消费路径

`DxfGeometrySink`是本项目的同步ASCII tag回调trait，非上游预先提供的API。`doc.pump_geometry(sink)`提供完整单tag块；两种现成sink为`@adapters.DxfkitSink::new()`和`@adapters.GeometrySink::new()`，再取`.drawing()`得到真实上游对象。

dxfkit适配走发布版`scan_tags/build_drawing`，保留整图记录；moon-geometry适配只投递ENTITIES，避免其简单读取器将BLOCKS局部图元计入。后者投影LINE/CIRCLE、LWPOLYLINE和受限旧式POLYLINE点列，不能替代dxfkit的实体覆盖或块展开。两者都需要缓冲/分配；没有零开销声明，也没有把上游几何算法算作本库成果。

旧式`POLYLINE/VERTEX/SEQEND`投影复用dxfkit的多记录组装，再映射到真实Point2D点列。只接收至少2个完整顶点的开放XY普通二维折线：主/顶点70及75标志为0或缺省，bulge/宽度/厚度/Z为0，法向缺省或(0,0,1)，序列须有SEQEND。闭合、曲线、空间/拟合/网格、非默认法向等变体继续不投影，原tag和save保持完整，不补点或猜测几何。[可运行旧式折线示例](examples/classic_polyline/README.md)。

moon-geometry适配仅投递其模型可表示的几何字段，忽略其本就不支持的TEXT/图层元数据；旧代码页的这些字段不会再妨碍提取受支持LINE/CIRCLE。原始字段仍完整保留在核心document中，没有对原件做有损文本替换。

该几何投影也跳过102应用定义组的私有字段，避免其中的10/20等组码形成额外顶点或替换真实坐标；嵌套组及命名结束标记按记录作用域跟踪。原document、save和完整tag sink仍保留应用载荷；这里不新增完整APPDATA合法性认证。

该适配器逐记录使用上游解析器，防止LINE省略Z时继承前一条坐标，并使用上游输入结束刷新路径保留LWPOLYLINE点数组；999注释不改变段状态。重复取drawing或继续投递不会清空/重复已有结果。

上游简单数值读取器会忽略指数；适配层使用已发布dxfkit的typed-tag数值及moon-geometry公开对象构造器准确传递标量。实体种类、默认值和点数仍来自上游解析器，不重复实现几何算法；科学记数坐标、最小次正规数、最大有限Double和负零有实际对象断言。

## 验证与来源

`fixtures/`包含本项目用独立ezdxf 1.4.3创建并导出的6份R12/R2000/R2018文件，原始模型与数据采用CC0-1.0；文件身份和来源见`fixtures/MANIFEST.json`。是独立生产工具生成的真实格式输入，不是手写parser镜像；没有冒称AutoCAD/国产CAD原生导出实测。厂商样例因未核清逐文件授权而没有捆绑。

implementation-03基线验证：18项JS及Wasm-GC测试；3,719个有序tag与独立ezdxf真值比较；六份本库转码输出由ezdxf回读，audit errors/fixes均0；双sink的实体数与坐标经过断言。五类坏图都由本库检出，ezdxf在加载或audit阶段对其中四类给出独立信号；XDATA括号缺失在该ezdxf流程未报告，不能宣称两库任意缺陷检出完全一致。详细可复现说明见`VERIFICATION.md`。

deep-repair-05新增12项针对性回归，修复8条已复现缺陷；本轮在JS/Wasm-GC各运行新增回归和15项受影响既有测试，未重复3项未变的历史模型测试。另用Python struct与ezdxf独立检查142种有限Double位模式、两种wire、9个Int64边界值，并枚举CRLF/UTF8与Binary的切分/截断边界。

deep-repair-06新增8项回归，覆盖版本作用域/注释/改写保护、ASCII块名大小写、坏行单tag预算、LINE默认Z及混合图元状态；双端各运行35项相关测试。CLI大小写/硬链接保护与独立ezdxf回读另有执行证据。历史大型模型及142位模式结果沿用原报告，不计入本轮执行数；详见`VERIFICATION.md`。

deep-repair-07修复几何指数值、非十进制整数/组码及旧代码页块名身份4个原因，新增6项回归；双端各32项相关测试，另有ezdxf时间字段、legacy块名与错误路径的小型独立消费证据。未变的大型模型/精度扫描及无关修复检查不重复。

deep-repair-12修复后续TABLE掩盖缺ENDTAB的漏报，JS/Wasm-GC各通过6项相关测试（3项新增、3项受影响既有回归）。独立R2018 ASCII/Binary模型的CLI退出码、诊断原始偏移、精确保真保存及repair保留未解决诊断均已核对。ezdxf高层加载/audit容忍该ASCII缺边界样本；本轮依据格式定义及独立原始tag边界核验，不宣称其audit也检出该问题。

deep-repair-13修复moon-geometry投影将102私有坐标当作额外顶点/实体标量的原因，最终JS/Wasm-GC各9项相关适配测试通过（3项新增、6项既有）。合法两顶点独立模型曾实际消费为三顶点；修复后导出实体的双格式真实消费者点数/坐标正确，完整模型CLI实体数与精确保真保存也已核对。公开接口、核心tag流和私有载荷保留，详见`VERIFICATION.md`。

deep-repair-14修复JSON文件有损UTF8解码导致的静默改写：8个非法编码场景安全拒绝，旧数组及原件绑定两条Unicode请求→预览→写出链通过，独立回读及完整输出字节预期一致。共15条相关命令（含1条Node语法检查）；MoonBit源码/接口未变，原生编译产物复用，未重复原生套件。

deep-repair-15恢复102私有code9元数据的合法按索引改写，真实结构/版本保护保留。JS/Wasm-GC各11项相关回归通过；双wire×双计划4次写出匹配独立单span字节预期，4个混合结构计划整项拒绝且既有输出不变，2份不同输出独立回读/audit均0/0。公共接口未变，未重复UTF8或几何旧场景；交付报告附生态对照与可运行外部计划例程。

deep-repair-16新增显式命名102组的计划选择，核心仅增加`value_edit_in_appdata`，旧方法/签名和计划格式保留。JS/Wasm-GC各7项相关测试（5新、2既有请求兼容）通过，双端MoonBit及Node例程实跑；四条双格式文件链准确捕获目标索引/旧值，2份不同输出独立回读/audit均0/0。缺失/重名目标拒绝猜测，未重跑旧UTF8、结构保护或整批拒绝场景。

自己的源码MIT，依赖和参考资料各按原许可，见`THIRD_PARTY_NOTICES.md`。这是本地已验证交付，不代表Mooncakes发布、组委会验收或CAD厂商互操作认证。


## 持续集成

GitHub Actions 在 Ubuntu 24.04 分别执行 JS、Wasm-GC 的 check/build/test、格式与公共接口检查，并运行三个 MoonBit 消费示例。JS 任务另运行独立 golden tag 对照、文件计划例程和 ezdxf 1.4.3 对六份转码输出的严格审计；非零 audit 错误或修复会令任务失败。工作流与安装入口见 `.github/workflows/check.yml` 和 `tools/ci-install.sh`，实际结果以对应提交的 Actions jobs 为准。
