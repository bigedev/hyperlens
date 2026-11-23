## 0.2.3

两处预览的代码块不再只认 highlight.js 的「常用语言」包，常用的那些真的能着色了。

- 随包多带 41 份语法定义（`assets/web/hljs/`，官方 11.9.0 的 per-language 产物，约
  110 KB、压缩后约 50 KB）：PowerShell、CMake、Protocol Buffers、Groovy、Gradle、
  LaTeX、Haskell、Scala、Elixir、Erlang、Clojure、OCaml、GLSL、Verilog、VHDL、Nginx、
  Handlebars、Twig、ERB、批处理、VBScript、PostgreSQL 等。`highlight.min.js` 是官方
  **common** 构建，这些一个都不在里面 —— 于是同一份代码在编辑器里有色、预览里没色。
- 清单在 `HyperlensAssets.hljsExtraLanguages`，`all` 也一并包含；要瘦身就从那份清单里删。
- Vue 没有 highlight.js 规则（从来没有）。围栏写 `vue` 时退到 `xml`：它的规则把
  `<script>` / `<style>` 交给 JavaScript 与 CSS 语法，所以模板、脚本、样式三段都有色，
  只有 `<script lang="ts">` 按 JavaScript 解析。

## 0.2.2

回执有了唯一入口，宿主不必自己判「这条要不要挪到后台」；HTML 的语法树也能按需重发。

- 新增 `PreviewReceiptDispatcher`：通道消息整条交给 `dispatch()` 即可 —— 小回执同步解析，
  大回执（语法树可以到 2MB）挪到后台 isolate 解码，阈值与分流都在包内，不再对外暴露
  「多长算大」。同一份文档会连发两回（渲染时的骨架 + 语法面板要的完整树），晚到的那份
  按「期间已有别的树落地」或「后发起的先返回」判为过时并丢弃 —— 面板不会从完整树退回
  骨架。没有 isolate 的平台自动退化为同步解析。
- 构造时可接 `onLog`：大回执的后台解析耗时、被丢掉的过时回执各记一条，默认静默。
- HTML 的注入脚本挂上 `window.hyperlensSyntaxAst()`（与 Markdown 同名）：HTML 的树仍然
  一次带全，但首屏那条会丢（页面重载、白屏重试），调用方切到语法面板时可以用
  `HyperlensCommands.requestSyntaxAst()` 再要一份。
- 主入口文档、示例与两份 README 的最短用法都改走这个入口；示例的语法树弹层演示
  Markdown（骨架 → 完整树）与 HTML（重发）走的是同一条命令。

## 0.2.1

库本身没有改动 —— 这次让产物里的第三方许可声明与实际装进去的东西对上。

- `assets/web/mermaid.min.js` 换成新产物。除了 mermaid 与 KaTeX，里面还有 53 个依赖
  （d3 系 30 个、cytoscape 系、dagre-d3-es、dompurify、marked、lodash-es 等），分别按
  MIT / ISC / BSD-3-Clause /（MPL-2.0 或 Apache-2.0）分发。完整清单、每个包的版权行、
  四种许可的逐字全文都内联在产物末尾的注释里，副本走到哪，声明跟到哪。
- 新增 `assets/licenses/mermaid-bundle.txt`：同一份清单的纯文本版，供宿主的许可页直接读。
  原来的 `mermaid.txt` 只收两个主作品（mermaid、KaTeX）的 MIT 全文，看不出这个文件里
  还装着另外 53 个包。
- `THIRD_PARTY_NOTICES.md` / `.cn.md`：删掉「产物里没有第四方代码」的说法，把两份正文的
  分工写清楚；另补一条指出产物里还带一份 dompurify（3.4.18，mermaid 自带），与独立分发的
  `purify.min.js`（3.2.6）不是同一份代码，但同属 Apache-2.0，共用一份文本。

## 0.2.0

链接点击收口成一套协议，由包持有：什么算要拦的链接、回执长什么样、哪些协议算「离开
文档」。调用方只负责注入与接收，不再各抄一份。

- 新增 `PreviewLinkSpace`（`repo` / `book`）与 `linkReceipt()` / `parseLinkReceipt()` /
  `isExternalPreviewLink()` / `kPreviewExternalSchemes`（`lib/src/protocol/link_intent.dart`）。
  `links.dart` 里那份私有的外链协议表已删除，两处读同一份。
- 链接回执带上地址空间：`link <space> <context> <编码后的 href>`（例如
  `link repo docs%2Fchap2.html chap2.html%23sec2`）。`context` 用来丢掉「刚从那一页
  离开」的迟到回执 —— 旧信封只靠 `href` 判断，换页之后迟到的点击会算到新页头上。
  旧式 `link <编码后的 href>` 仍然认，已有模板不用改。
- `PreviewLinkTapped` 增加 `space` 与 `context`：宿主拿它跟自己配置的页面比，不一样
  就忽略。
- `HyperlensPage.fromText` / `htmlAnchorScript` 接受 `linkSpace` / `linkContext`：注入
  的 HTML 脚本自己就发带地址空间的信封，页面不再需要第二段手写的点击脚本（两段脚本
  会让一次点击发两条回执，第二条只靠下游的「同一处」判据兜住）。
- 注入的 HTML 脚本在同一轮 JS 里**先报位置、再报链接**（捕获阶段的监听注册得比链接
  监听早）：返回栈要的是「离开那一刻」的位置，不是上一次停稳的位置。
- 认不出的链接回执 —— 段数不对、地址空间名不认识、转义坏掉 —— 一律归到「认不出的
  消息」，不再把整句当成链接交出去；`%FF` 这类解不成 UTF-8 的转义也不再从解析器里抛。
- `OpenRepoFile` 保留跨文件链接的 `#片段`（`fragment`，已解码）：
  `README.md#getting-started` 不再丢掉小节。同一篇文档里的纯 `#锚点` 仍交给页面自己滚。
- 示例补上链接这条路的演法：HTML 文档挂了 `linkSpace` / `linkContext`，状态栏打出
  回来的地址空间；`demo.html#receipts` 这条经 `PreviewDomAddress('#receipts')` 落位。
  Markdown 文档仍旧发旧式信封 —— 两种都在屏上。

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
