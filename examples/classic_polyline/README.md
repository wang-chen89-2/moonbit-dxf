# 旧式开放二维折线到真实几何点列

```sh
moon run examples/classic_polyline --target js
moon run examples/classic_polyline --target wasm-gc
```

程序将自包含AC1009记录流转为R12 Binary，再解析并送入GeometrySink。实际moon-geometry.DxfPolyline应包含3个点：(1.25,-2.5)、(4.5,8.75)、(9,3)，并检查原始Binary保存字节不变。这个最小程序用于展示调用，不声明CAD合规认证。

投影通过已发布dxfkit组装POLYLINE及其连续VERTEX/SEQEND，随后映射到已有Point2D模型；不复制几何算法或原地修改原件。BLOCKS的局部图元和102私有字段不进入此投影。

只支持开放XY普通二维子集：主记录和VERTEX的70标志、75拟合类型均为0或缺省；至少2个完整顶点；bulge/宽度/厚度/Z为0；法向缺省或(0,0,1)，SEQEND完整。闭合、曲线/拟合、空间/网格、非默认法向或缺结束标记的序列不投影，后续受支持图元仍可消费；原document/tag流/save不丢失。完整性诊断与上游几何覆盖边界仍适用。
