## 0.1.0

未发布。首次从编辑器应用的预览实现中抽出。

- Markdown 渲染载荷：行 / 块标记、DOMPurify 清洗、KaTeX 与 mhchem 公式。
- HTML 渲染载荷：用 DOM 路径作为阅读位置地址。
- 回执协议：渲染完成、点击链接、位置上报、大纲上报、命中已定位、锚点已滚动、
  认不出的消息。
- 与预览同一次解析得出的大纲与语法树，位置都落在源码行上。
- 资产（marked、DOMPurify、KaTeX、mhchem、highlight.js、Mermaid）改由包声明，
  宿主不再声明同名路径。
- 对外符号：`MarkdownPage` 是唯一的渲染入口；其余是 `HyperlensAssets`、
  `HyperlensBridge`、`HyperlensTheme`、`HyperlensLogger` 与 `HyperlensAssetLoader`
  （Flutter 侧用 `RootBundleAssetLoader`）。
- WebView 通道名改为注入模板，不再写死，宿主可以注册自己的名字。
- 增强资产（KaTeX、mhchem、Mermaid）缺失时降级为纯文本，并通过 `HyperlensLogger`
  上报，而不是整页失败。
- `HyperlensTheme` 把深色与墨水屏当成两个独立维度：墨水屏是叠在主题表之上的单色
  覆盖层，深浅两态各发一份（默认态 `*-ink.css` 白底黑字，反白版 `*-ink-dark.css`
  黑底白字）。
- 深色底上 Mermaid 图表保持完整：桑基图的连线渐变带原先消失，原因是 Mermaid 给每条
  连线写死 `mix-blend-mode: multiply`（该模式只在浅底上成立）；现仅在深色两档把混合
  模式改回 `normal`，浅色与墨屏浅色的观感不变。
