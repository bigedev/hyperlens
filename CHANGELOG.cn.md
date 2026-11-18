## 0.1.0

未发布。首次从编辑器应用的预览实现中抽出。

- Markdown 渲染载荷：行 / 块标记、DOMPurify 清洗、KaTeX 与 mhchem 公式。
- HTML 渲染载荷：用 DOM 路径作为阅读位置地址。
- HTML 章节除 `<h1>~<h6>` 外还认 ARIA 语义标题（`role="heading"`，层级取
  `aria-level`，缺省 2、超过 6 按 6）：一个标题只留一条，标题套标题只留外层。
- HTML 的章节清单盯文档高度（`ResizeObserver`）：折叠面板展开/收起、图片撑开之后
  自动重扫并重发，不必再靠切字号重载页面。
- 回执协议：渲染完成、点击链接、位置上报、大纲上报、命中已定位、锚点已滚动、
  认不出的消息。
- 与预览同一次解析得出的大纲与语法树，位置都落在源码行上。
- 资产（marked、DOMPurify、KaTeX、mhchem、highlight.js、Mermaid）改由包声明，
  宿主不再声明同名路径。
- 对外符号：`MarkdownPage` 是唯一的渲染入口；其余是 `HyperlensAssets`、
  `HyperlensBridge`、`HyperlensTheme`、`HyperlensLogger` 与 `HyperlensAssetLoader`
  （Flutter 侧用 `RootBundleAssetLoader`）。
- WebView 通道名改为注入，不再写死：Markdown 走模板占位符，HTML 走
  `htmlAnchorScript(channelName:)`，宿主可以注册自己的名字（两边必须与
  `addJavaScriptChannel` 一致，非法标识符在拼装阶段就抛错）。
- 增强资产（KaTeX、mhchem、Mermaid）缺失时降级为纯文本，并通过 `HyperlensLogger`
  上报，而不是整页失败。
- `HyperlensTheme` 把深色与墨水屏当成两个独立维度：墨水屏是叠在主题表之上的单色
  覆盖层，深浅两态各发一份（默认态 `*-ink.css` 白底黑字，反白版 `*-ink-dark.css`
  黑底白字）。
- 深色底上 Mermaid 图表保持完整：桑基图的连线渐变带原先消失，原因是 Mermaid 给每条
  连线写死 `mix-blend-mode: multiply`（该模式只在浅底上成立）；现仅在深色两档把混合
  模式改回 `normal`，浅色与墨屏浅色的观感不变。
- 阅读位置收成一种地址（破坏性变更）：Markdown 用源码行 `SourceAddress`，HTML 用 DOM 路径
  `DomAddress`（形如 `body>div#main>p:nth(3)`），另有 `PreviewViewport` 带每帧的视口行号，
  只服务章节高亮。`PreviewAnchor`（`block` / `offset` / `scrollY`）已删除，页面只认
  `HyperlensCommands` 那两条滚动原语（`mdScrollToLine` / `hyperLensScrollToPath`）；
  地址解析不出来时回顶部、不再按像素猜。旧记忆仍可读：存过 `line` 的直接用，
  只有像素的按「无地址」回顶部。
