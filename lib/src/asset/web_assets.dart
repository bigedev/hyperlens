/// `assets/web/` 下渲染资源的**唯一来源**。
///
/// 路径一律 `packages/hyperlens/…`：资产已随包声明（见 pubspec 的
/// `flutter: assets:`），宿主的 WebView 通过这个前缀读它们；宿主侧**不要**再
/// 声明同名路径 —— 两处都声明时，失效的那一处不会编译失败，只表现为白屏。
///
/// 为什么集中：同一个文件会被两条通道读取 —— 「WebView 直读」
/// （`rootBundle.loadString`）与「字符串拼装」（[buildMarkdownHtml] 用注入的
/// `load`）。升级一次 highlight.js 要在几个文件里改多处，漏一处不报错，
/// 只表现为那一路渲染白屏。
///
/// 只放路径、不放读取方法：两条通道的 `load` 注入方式不同（一个走 rootBundle、
/// 一个走测试假实现），统一读取入口反而会把测试替身挡在外面。
///
/// 与宿主的分工：diff 那一套（`diff_view.html`、`diff2html`、`diff-ink.css`）和
/// 站点预览的样式**不在本包里**，它们不参与 Markdown 渲染。
class WebAssets {
  const WebAssets._();

  /// 包内资产前缀。宿主用 `rootBundle` / `WebView` 读包内文件时都从它拼。
  static const String prefix = 'packages/hyperlens/assets/web';

  // ---- 模板 ----

  /// markdown 渲染页：`buildMarkdownHtml` 的占位符宿主。
  static const String markdownViewHtml = '$prefix/markdown_view.html';

  // ---- markdown 主题（GitHub 样式 + 墨水屏覆盖）----

  static const String mdLightCss = '$prefix/md-light.css';

  static const String mdDarkCss = '$prefix/md-dark.css';

  /// 墨水屏：叠在 light 之上的覆盖层，不是完整主题。
  static const String mdInkCss = '$prefix/md-ink.css';

  // ---- 代码高亮主题 ----

  static const String hljsLightCss = '$prefix/hljs-light.css';

  static const String hljsDarkCss = '$prefix/hljs-dark.css';

  static const String hljsInkCss = '$prefix/hljs-ink.css';

  // ---- 脚本 ----

  static const String markedJs = '$prefix/marked.min.js';

  /// DOMPurify：marked 不做 sanitize，输出必须过白名单清洗。
  static const String purifyJs = '$prefix/purify.min.js';

  static const String highlightJs = '$prefix/highlight.min.js';

  /// dart 不在 highlight.js 的「常用语言」包里，单独带一份语言定义。
  static const String highlightDartJs = '$prefix/highlight-dart.min.js';

  /// KaTeX：数学公式渲染。清洗完成之后才调用 `katex.render`（DOM API，不经过
  /// `innerHTML`），所以**不需要给 DOMPurify 白名单开 `math` / `svg`**。
  static const String katexJs = '$prefix/katex.min.js';

  /// KaTeX 的 mhchem 扩展（`\ce{}` / `\pu{}` 化学式）。
  ///
  /// 两条硬约束：
  /// - **必须排在 [katexJs] 之后** —— 它是 UMD，运行时读全局 `katex`；
  /// - **版本必须与 [katexJs] 同号** —— 跨版本混用的表现是「公式正常、`\ce` 报
  ///   未定义命令」，很难一眼归因。
  static const String mhchemJs = '$prefix/mhchem.min.js';

  /// KaTeX 样式。字体已 base64 内联（`tool/build_katex_css.py`），因为预览页的
  /// CSP 是 `font-src data:` —— 换成字体目录就得放开 CSP 并加一条静态资产路由。
  static const String katexCss = '$prefix/katex.min.css';

  /// Mermaid：```mermaid 围栏渲染成 SVG。
  ///
  /// 3.57 MB 的 IIFE 单文件（11.17.2），只有文档里真的出现 mermaid 围栏时才内联
  /// （见 `extras.dart` 的门控）。**锁 11.x**：12.x 的包体是 5.54 MB，对阅读场景
  /// 没有增量能力。
  static const String mermaidJs = '$prefix/mermaid.min.js';
}
