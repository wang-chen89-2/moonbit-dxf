# 命名102应用组的字段计划

已有图纸中同一实体有多个应用组，组内还可重复同一组码。显式给出handle、appdata名称和occurrence，自动捕获目标原值；无需先手算全文件tag索引。

```sh
moon run examples/appdata_plan --target js
moon run examples/appdata_plan --target wasm-gc
moon build --target js
node examples/appdata_plan/run.mjs NEW_OUTPUT_DIRECTORY
```

输出目录须不存在。Node例程复制独立ezdxf生成的完整R2018样例和请求，形成原件绑定计划，预览后写入新文件；保留每步命令、回执和原件。图纸/请求模型为原始CC0-1.0数据，代码沿项目MIT。

请求在原格式上增加可选字符串：

```json
[{"handle":"34","appdata":"EDITOR_META","code":9,"occurrence":1,"value":{"text":"reviewed"}}]
```

它只改EDITOR_META的第二个直属code9，ARCHIVE_META、EXPORT_META中的同码/同值不受影响。未给appdata的旧请求继续跳过102载荷。生成计划仍是原来的index/code/expected/value数组，绑定容器格式也不变。

库调用为`doc.value_edit_in_appdata(handle, application, code, value, occurrence?)`，结果交给`rewrite_values`。名称不带花括号，按UTF8字节精确匹配，不折叠大小写或猜测旧代码页；只定位一个唯一顶层组及其直属字段，子组字段不计数。支持普通`}`和同名`NAME}`结束；目标重名、未闭合、缺失、错名结束或出现次序越界会报错。此入口不选择0/102标记。

它处理既有应用数据，不新增应用语义认证、子组地址、XDATA APPID查询或引用更新；最终写出仍受原有结构、版本、wire及旧值规则约束。名称不能直接代表APPID表注册验证。
