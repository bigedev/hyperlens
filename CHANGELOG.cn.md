## 0.1.1

库本身没有改动 —— 这次只整理随包发布的内容。

- 示例按职责拆文件：`lib/main.dart` 只留渲染流水线（提交、回执分发、阅读位置语义），
  演示文档、工具栏、目录抽屉、页脚、语法树弹层、平台降级移入 `lib/src/`。
- `pubspec.yaml` 的 `description` 收紧到 pub 规范要求的长度区间。

## 0.1.0

首次从编辑器应用的预览实现中抽出。

- Markdown 渲染载荷：行 / 块标记、DOMPurify 清洗、KaTeX 与 mhchem 公式。
- HTML 渲染载荷：用 DOM 路径作为阅读位置地址。
- HTML 章节除 `<h1>~<h6>` 外还认 ARIA 语义标题（`role="heading"`，层级取
  `aria-level`，缺省 2、超过 6 按 6）：一个标题只留一条，标题套标题只留外层。
- HTML 的章节清单盯文档高度（`ResizeObserver`）：折叠面板展开/收起、图片撑开之后
  自动重扫并重发，不必再靠切字号重载页面。
- 新增语法树骨架回执（`ast`）：Markdown 与渲染共用同一次 lexer，HTML 用浏览器自己的
  `document` 遍历；载荷按节点数、深度、字节三档闸门裁剪。Dart 侧为
  `PreviewSyntaxTree` / `PreviewSyntaxNode`。
- 完整语法树（含子块与 inline token）按需拉取：`HyperlensCommands.requestSyntaxAst()`
  触发页面再发一条 `ast`，与骨架共用同一份 token 与行号。
- 语法问题清单（`ast` 回执的 `issues`）：页面侧判定代码围栏没闭合、表格某行列数
  和表头不符、引用式链接没有定义；Dart 侧补 `scanHtmlTagIssues()`
  （按源码文本扫标签栈，报未闭合与多余的结束标签，浏览器的 `document` 里看不到
  这些）。两条来源合并时页面在前、解析侧在后，同一处同一类只留一条。
- 回执协议：渲染完成、点击链接、位置上报、大纲上报、命中已定位、锚点已滚动、
  认不出的消息。
- 与预览同一次解析得出的大纲与语法树，位置都落在源码行上。
- 资产（marked、DOMPurify、KaTeX、mhchem、highlight.js、Mermaid）改由包声明，
  调用方不再声明同名路径。
- 对外符号：`HyperlensPage.fromText` 是唯一的渲染入口（Markdown 与 HTML 同一个）；
  其余是 `HyperlensAssets`、
  `HyperlensBridge`、`HyperlensTheme`、`HyperlensLogger` 与 `HyperlensAssetLoader`
  （Flutter 侧用 `HyperlensRootBundleAssetLoader`）。
- WebView 通道名改为注入，不再写死：Markdown 走模板占位符，HTML 走
  `htmlAnchorScript(channelName:)`，调用方可以注册自己的名字（两边必须与
  `addJavaScriptChannel` 一致，非法标识符在拼装阶段就抛错）。
- 增强资产（KaTeX、mhchem、Mermaid）缺失时降级为纯文本，并通过 `HyperlensLogger`
  上报，而不是整页失败。
- `HyperlensTheme` 把深色与墨水屏当成两个独立维度：墨水屏是叠在主题表之上的单色
  覆盖层，深浅两态各发一份（默认态 `*-ink.css` 白底黑字，反白版 `*-ink-dark.css`
  黑底白字）。
- 深色底上 Mermaid 图表保持完整：桑基图的连线渐变带原先消失，原因是 Mermaid 给每条
  连线写死 `mix-blend-mode: multiply`（该模式只在浅底上成立）；现仅在深色两档把混合
  模式改回 `normal`，浅色与墨屏浅色的观感不变。
- 阅读位置收成一种地址（破坏性变更）：Markdown 用源码行 `PreviewSourceAddress`，HTML 用 DOM 路径
  `PreviewDomAddress`（形如 `body>div#main>p:nth(3)`），另有 `PreviewViewport` 带每帧的视口行号，
  只服务章节高亮。`PreviewAnchor`（`block` / `offset` / `scrollY`）已删除，页面只认
  `HyperlensCommands` 那两条滚动原语（`mdScrollToLine` / `hyperLensScrollToPath`）；
  地址解析不出来时回顶部、不再按像素猜。旧记忆仍可读：存过 `line` 的直接用，
  只有像素的按「无地址」回顶部。
- 写明 `HyperlensTheme` 是宿主判断「页面要不要重载」的唯一定义：渲染结果是快照，
  底色 / 正文色 / 覆盖层都在加载时拼进 HTML，所以新增档位必须连 `==` / `hashCode`
  一起加。踩过的坑：墨屏与浅色底色同为 `#ffffff`，只比底色的宿主在「墨屏 → 浅色」
  时不重载，页面留在墨屏的单色覆盖里，彩色标题全变黑字（详见 `HyperlensTheme` 类注释）。
