# moonbit-dxf

源码仓库：[wang-chen89-2/moonbit-dxf](https://github.com/wang-chen89-2/moonbit-dxf)。当前模块为 `wang-chen89-2/dxf`，维护与申报账号为 `wang-chen89-2`。原始来源作者标识 `wang-chen89`、许可证及 Git 作者历史按原记录保留，见[来源与许可](THIRD_PARTY_NOTICES.md)。

原生 MoonBit ASCII/Binary DXF 有类型记录流、原字节保留、显式修复与记录级诊断。模块名 `wang-chen89-2/dxf`，版本 0.1.0，尚未发布到 Mooncakes。它为 DXF 导入、检查、脚本重写与既有几何库提供格式层；不重复实现 OCS、bulge 或块拍平。

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

修复前可先执行 `node tools/dxf.mjs repair-preview damaged.dxf`：stdout 返回与实际 `repair` 写出时 stderr 相同的 `{discarded_bytes, diagnostics}` JSON；不会创建或改写文件，也不接受输出路径。退出0表示现有修复策略能生成候选结果，退出2表示参数、读取或修复失败。预览会在内存中执行完整修复；它不是可应用的计划，不绑定后续输入，也不表示所有诊断已消除。确认损失后再运行 `node tools/dxf.mjs repair damaged.dxf repaired.dxf`；输入发生变化时应重新预览。

预览与写出的独立文件消费者回归：`python -B tools/test_repair_preview.py verification-output/repair-preview`（目录须尚不存在）。它用手写 ASCII/Binary tag 和 Python struct 验证保留段、补边界、精确丢弃字节数、合法 Unicode/旧代码页字节及 NUL 替换；还验证无完整 Binary 段、R13、EOF 后记录、文件/参数错误的拒绝和原件/既有目标保护。

CLI 转换/修复需单独输出路径，按文件身份拒绝覆盖输入，包括Windows大小写别名和硬链接。`lint` 退出0表示没有当前退出规则的问题，1表示检出缺陷/不完整，2表示参数、文件或转换失败；不是 AutoCAD 合规认证。`repair` 将损失字节数和诊断打印到stderr，原件不变。

`patch`写出同时保护DXF原件和计划文件两个输入，输出不能指向任一输入或其文件别名；旧数组计划和原件绑定容器均适用。单独的既有目标仍按原行为允许写出。

文件身份保护的真实消费者回归可在JS构建后运行（需Python 3）：

```sh
moon build --target js --deny-warn
python -B tools/test_patch_alias.py verification-output/patch-alias
```

目录须尚不存在。测试只在新目录中的fixture/计划副本间创建真实硬链接，以系统`samefile`、设备号/文件号和链接数确认身份；覆盖两种计划的源文件/计划别名拒绝，以及独立新目标和既有目标成功写出，输出逐字节对照已知单处替换。无法创建硬链接会使测试失败，不以复制文件或跳过代替；Linux CI的JS任务必须实际运行。拒绝时校验目录项、文件内容与身份不变，不断言读取时间戳；这里不新增并发路径替换防护或原子写出承诺。

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

公共调用示例（在消费者moon.pkg中导入`"wang-chen89-2/dxf"`）：

```mbt
let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
let exact_original = doc.original_bytes()
let diagnostics = doc.lint()
let binary = doc.to_binary() // raises DxfError for unsupported conversion
```

批量改写的`ValueEdit`包含`index/expected_code/expected/value`；`RewriteResult`含`bytes/changes`，每个`ValueChange`记录原始索引、组码、字节区间和before/after。输入计划可乱序，重复/越界/前置条件不符会整体拒绝；原document不变。空计划返回原件，非空计划保持现有结构/版本/wire保护。实现排序计划、扫描结构保护并一次拼接源字节；需要缓冲完整输入/输出，没有低内存承诺。

结构保护按102应用组作用域区分私有载荷：按原tag索引的计划可改其中已知类型元数据（如code9文本），不再误当HEADER变量名。真实SECTION/TABLE名称、HEADER键和版本仍锁定；默认句柄请求继续跳过应用私有字段。

公开XRECORD在公开100/AcDbXrecord标记后的code9是既有Text载荷，允许通过原single/batch及句柄计划改值，无需HEADER迁移；下一物理记录重置权限。真实HEADER键/版本/结构名、未确认载荷上下文及旧expected/type/wire/hash检查保持，私有伪marker不放行。[完整原生及真实文件改写/接收](examples/xrecord_rewrite/README.md)。

可运行的MoonBit及JSON计划见[examples/rewrite](examples/rewrite/README.md)。CLI新增`tags INPUT`、`patch-plan INPUT PLAN.json`（只显示校验记录）和`patch INPUT OUTPUT PLAN.json`；旧CLI/API继续保留。未选范围逐字节保持，所选tag可规范化编码；不插入/删除tag或自动更新引用，文件宿主不提供原子替换承诺。

按记录句柄形成计划可用`value_edit_by_handle(handle, code, value, occurrence?)`与CLI `make-plan INPUT REQUESTS.json`。默认请求查找公共5句柄（DIMSTYLE为105），按组码/出现次序捕获原始有类型旧值，跳过102应用数据；输出兼容现有批量计划，文本用原始hex、Double用bits，避免把tags的有损显示当作旧字节。缺失/重复句柄或字段超界会拒绝。[普通字段示例](examples/handle_plan/README.md)。

需准确选择既有102私有字段时，请求可显式增加`"appdata":"应用名"`，或调用`value_edit_in_appdata(handle, application, code, value, occurrence?)`。只匹配唯一同名顶层组的直属字段，名称按UTF8字节精确比较，子组字段不计数；重名/未闭合目标组拒绝猜测。旧默认请求、计划数组和绑定容器不变；不提供子类/几何查询或完整应用语义认证。[命名应用组运行示例](examples/appdata_plan/README.md)。

同一记录含多个应用的XDATA时，可用 `xdata_by_appid(handle, application)` 读取唯一公共1001范围的原始有类型tag，或用 `value_edit_in_xdata(handle, application, code, value, occurrence?)` 捕获已有值；请求增加可选 `"xdata":"APP_B"`，与appdata互斥。名字按UTF8字节精确匹配，occurrence包含平衡的嵌套1002列表；先完整检查目标范围的歧义/结构，再返回读取或计划。空范围可读，不新增块/注册APPID或认证应用模式。真实文件接收方读取改写后的APPID载荷，现有计划/收据不变。[完整读取、改写及接收流程](examples/xdata_plan/README.md)。

需要确认整份原件时，文件CLI可用`make-bound-plan INPUT REQUESTS.json`生成含SHA256的可选容器；`patch-plan/patch`先核对当前输入字节，再做原有值/结构校验，成功记录摘要。旧make-plan默认数组及其所选tag合同保持不变。JSON拆封/数值词法由MoonBit处理，实际摘要由Node文件宿主计算；未增加核心依赖。[可运行原件绑定示例](examples/source_bound/README.md)。

已有按索引编写的计划（包括没有句柄的记录）可用`bind-plan INPUT PLAN.json`先完整校验，再向stdout输出同一原件绑定容器；不改原件/计划，不写DXF。编辑数字词法保留；若输入已绑定，须先匹配当前原件，失配不会被重新绑定。[既有计划绑定示例](examples/bind_plan/README.md)。

收到整份改写文件后，可执行 `node tools/dxf.mjs verify-patch SOURCE RECEIVED BOUND_PLAN.json`。该只读入口核对原件SHA256，复用既有原生计划审批并生成完整预期结果，再与实际接收文件逐字节比较；成功stdout在原收据字段上增加`verified:true`和实际文件`output_sha256`，不会写文件。任何额外字节、未选字段变化或仅数值词法/换行的变化都不能冒充该计划结果。退出0只证明读到的文件等于此原件/计划的结果，2表示参数、文件、计划审批或字节比较失败，不输出成功JSON。新核验要求既有原件绑定容器，旧数组计划的预览/写出仍支持。空计划沿用原有不改值合同，只核对绑定来源及字节身份，不触发编辑的版本/完整性审批；核验不代替lint或CAD验收。[完整用法及独立文件接收验证](examples/source_bound/README.md)。

按公共句柄交接完整物理记录可用 `doc.record_by_handle(handle)` 或 `node tools/dxf.mjs record INPUT OUTPUT HANDLE`：返回原始wire字节及绝对来源区间，文件收据另含原件/片段摘要和profile。实际接收方 `node examples/record_handoff/receive.mjs SOURCE RECORD RECEIPT` 核对原件成员关系并通过公共decoder读取一条物理记录；不会把片段当独立图纸、引用闭包或完整逻辑实体。保留102私有载荷，复用原拥有者规则和文件别名保护；新入口只接受完整typed、支持版本/wire一致的非repair源，旧API/JSON/计划与编码不变。[完整交接及错误边界](examples/record_handoff/README.md)。

没有句柄的旧图纸也可用 `doc.record_spans()` 或 `node tools/dxf.mjs records INPUT` 建立只读物理记录清单。每个公开 code0 开始一段，包含 SECTION、TABLE、ENDSEC、EOF 及未知种类；`RecordSpan` 给出零起算的 ordinal、`start_tag`/`end_tag` 和原件 `offset`/`end_offset`，两种 end 均为排他边界。首个 code0 前的标签、最后标签后的非标签空白不计入记录，仍保存在原件中。`kind: Bytes` 与 `handle: Bytes?` 保留原始编码，文件 JSON 使用 `kind_hex` 和 `handle_hex`/null，并给出 version、binary、source_bytes、record_count、records 和原件 source_sha256。

拥有者候选复用旧查找规则：忽略102私有组，止于首个公开100/1001，DIMSTYLE用105，其余可拥有句柄的记录用5，结构控制记录不取拥有者。候选可能缺失、非法或重复；清单不授权按该值编辑，旧句柄查找仍拒绝歧义。新入口要求完整typed、支持版本/wire一致的非repair源；退出0只表示清单生成，不表示CAD语义合法。调用者可把记录标签区间与现有 `tags` 联用，选定索引后照常 `bind-plan`、`patch-plan`、`patch` 和完整读回。[双格式无句柄索引编辑与接收示例](examples/record_inventory/README.md)。

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

重复句柄诊断对合法1到16位十六进制值按既有句柄身份规则比较，忽略大小写和前导零：`2A`与`00002a`会在后者原始offset报告`DuplicateHandle`，文件CLI `lint`退出1。原tag/字节及消息中的原写法保留；DIMSTYLE仍以105为拥有者，私有102字段仍排除。格式不合法的字符串保持原来的大写字符串比较，不借此新增句柄格式验证或改变解析接受范围。

真实文件入口回归：JS构建后运行 `python -B tools/test_handle_lint.py verification-output/handle-lint`，目录须不存在。独立bytes/struct模型与整数恒等式建立预期，逐一核对现有CLI的完整JSON、退出码、原始偏移及只读文件内容；CI执行位置与证据边界见[CI计划](CI-PLAN.md)。

TABLE缺少ENDTAB时，即使后续TABLE正常闭合，也会在下一TABLE的原始字节offset报告`UnclosedTable`；不会用后表的结束标记掩盖前表缺失。只读保存仍保持原字节，显式repair保留该诊断，不擅自补表边界。

块名按原字节进行ASCII大小写匹配；旧代码页名不再因UTF8失败合并为空名，无法显示为UTF8的缺块诊断给出原始十六进制名，不猜测代码页转换。

102应用定义组内的值不冒充记录自己的句柄、块名或XDATA控制符；原始载荷及通用值诊断仍保留。此处不宣称完整应用数据结构验证。

ASCII repair可跳过有物理边界的坏行对、替换UTF8非法字节及NUL/CR、补ENDSEC/EOF；不会声称找回被丢弃的数据。Binary repair仅在截断/未知尾部时保留最后一个完整关闭section之前的tag，附丢弃字节数并加EOF；没有可用section则报错。不做任意Binary字节滑窗重同步。repair不保证消除所有lint缺陷，更不保证ezdxf会接受任意坏图。

Binary即使恰好截在tag边界，只要section未闭合，也只保留此前完整section；单独的ENDSEC不算完整section。repair拒绝wire/version冲突及EOF后额外完整记录，避免隐式版本迁移或静默丢字段。`rewrite_value`保护SECTION/TABLE的第一个code2名称和版本声明，普通INSERT块名、HEADER的UCS名称仍可编辑；Opaque值也不能注入换行/NUL边界。

## 真实几何消费路径

`DxfGeometrySink`是本项目的同步ASCII tag回调trait，非上游预先提供的API。`doc.pump_geometry(sink)`提供完整单tag块；两种现成sink为`@adapters.DxfkitSink::new()`和`@adapters.GeometrySink::new()`，再取`.drawing()`得到真实上游对象。

dxfkit适配走发布版`scan_tags/build_drawing`，保留整图记录；moon-geometry适配只投递ENTITIES，避免其简单读取器将BLOCKS局部图元计入。后者投影LINE/CIRCLE、LWPOLYLINE和受限旧式POLYLINE点列，不能替代dxfkit的实体覆盖或块展开。两者都需要缓冲/分配；没有零开销声明，也没有把上游几何算法算作本库成果。

旧式`POLYLINE/VERTEX/SEQEND`投影复用dxfkit的多记录组装，再映射到真实Point2D点列。只接收至少2个完整顶点的开放XY普通二维折线：主记录70可为0、128或缺省，顶点70与所有75标志仍为0或缺省，bulge/宽度/厚度/Z为0，法向缺省或(0,0,1)，序列须有SEQEND。主记录128仅控制沿顶点的线型生成，不改变这里的点列坐标；本库不模拟线型绘制。闭合、曲线、空间/拟合/网格、非默认法向等变体继续不投影，原tag和save保持完整，不补点或猜测几何。[旧式折线示例](examples/classic_polyline/README.md)及[双格式线型标志消费示例](examples/classic_plinegen/README.md)。

消费者可用只读`GeometrySink::unprojected_classic_count()`查询当前缓冲中尚未投影的旧式折线候选数，及时提示这类有限投影遗漏；原`drawing()`结果不变。未完整到达SEQEND的候选也计入当前快照，完成合法开放序列后计数可回落；查询不清空或消费缓冲。它复用现有私有字段过滤与投影判断，扫描缓冲并可能分配对象。

计数仅覆盖已接收ENTITIES旧式POLYLINE，不含BLOCKS局部图元、ARC/TEXT等其他未支持种类；0不能用作整图完整性证明。两种后端的[投影状态示例](examples/projection_status/README.md)展示三实体输入、两个投影对象和一个未投影旧式候选，原件保存不变。

moon-geometry适配仅投递其模型可表示的几何字段，忽略其本就不支持的TEXT/图层元数据；旧代码页的这些字段不会再妨碍提取受支持LINE/CIRCLE。原始字段仍完整保留在核心document中，没有对原件做有损文本替换。

该几何投影也跳过102应用定义组的私有字段，避免其中的10/20等组码形成额外顶点或替换真实坐标；嵌套组及命名结束标记按记录作用域跟踪。原document、save和完整tag sink仍保留应用载荷；这里不新增完整APPDATA合法性认证。

该适配器逐记录使用上游解析器，防止LINE省略Z时继承前一条坐标，并使用上游输入结束刷新路径保留LWPOLYLINE点数组；999注释不改变段状态。重复取drawing或继续投递不会清空/重复已有结果。

上游简单数值读取器会忽略指数；适配层使用已发布dxfkit的typed-tag数值及moon-geometry公开对象构造器准确传递标量。实体种类、默认值和点数仍来自上游解析器，不重复实现几何算法；科学记数坐标、最小次正规数、最大有限Double和负零有实际对象断言。

## 验证与来源

`fixtures/`包含本项目用独立ezdxf 1.4.3创建并导出的6份R12/R2000/R2018文件，原始模型与数据采用CC0-1.0；文件身份和来源见`fixtures/MANIFEST.json`。是独立生产工具生成的真实格式输入，不是手写parser镜像；没有冒称AutoCAD/国产CAD原生导出实测。厂商样例因未核清逐文件授权而没有捆绑。

独立格式对照覆盖3,719个有序tag，六份本库转码输出经ezdxf回读，audit errors/fixes均0；双sink的实体数与坐标经过断言。五类坏图都由本库检出，ezdxf在加载或audit阶段对其中四类给出独立信号；XDATA括号缺失在该ezdxf流程未报告，不能宣称两库任意缺陷检出完全一致。

原生回归覆盖版本与段/表作用域、流式切分和截断、原始代码页字节、Int64边界、IEEE754位模式、局部改写前置条件以及102/XDATA选择边界。独立数值对照包括142种有限Double位模式及9个Int64边界值；这些历史精度扫描与生成方法记录在[验证说明](VERIFICATION.md)，不会把未重跑的历史结果计作新执行。

公共MoonBit消费者验证实际dxfkit/moon-geometry对象、旧式折线投影及原件保真。文件宿主回归验证严格UTF8输入、路径/硬链接别名保护、绑定计划、修复预览、物理记录交接和APPID/XRECORD改写接收，逐字节对照独立原件与预期；其范围不包括并发文件替换或写出耐久性。许可证、依赖和参考资料各按原记录保留，见[来源与许可](THIRD_PARTY_NOTICES.md)。验证结果不代表Mooncakes发布、组委会验收或CAD厂商互操作认证。


## 持续集成

GitHub Actions 在 Ubuntu 24.04 分别执行 JS、Wasm-GC 的 check/build/test、格式与公共接口检查，并运行九个 MoonBit 公共包消费示例。JS 任务另运行独立 golden tag 对照、文件计划与接收例程和 ezdxf 1.4.3 对六份转码输出的严格审计；非零 audit 错误或修复会令任务失败。工作流与安装入口见 `.github/workflows/check.yml` 和 `tools/ci-install.sh`，实际结果以对应提交的 Actions jobs 为准。
