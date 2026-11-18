## 0.1.0

未发布。首次从编辑器应用的预览实现中抽出。

- Markdown 渲染载荷：行 / 块标记、DOMPurify 清洗、KaTeX 与 mhchem 公式。
- HTML 渲染载荷：用 DOM 路径作为阅读位置地址。
- 回执协议：渲染完成、点击链接、位置上报、大纲上报、命中已定位、锚点已滚动、
  认不出的消息。
- 与预览同一次解析得出的大纲与语法树，位置都落在源码行上。
- 资产（marked、DOMPurify、KaTeX、mhchem、highlight.js、Mermaid）改由包声明，
  宿主不再声明同名路径。
