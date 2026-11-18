import 'dart:convert';

import '../asset/web_assets.dart';
import '../model/preview_anchor.dart';
import '../model/preview_focus.dart';
import 'escape.dart';
import 'extras.dart';

/// 页面载荷：一份 JSON，模板里由 `/*__PAYLOAD__*/` 占位。
///
/// 从 `markdown_view.dart` 的 `_render` 里拆出来 —— 它只做「拼一个字符串」，与
/// WebView 生命周期无关，所以能在主机上测（比如**正文里的 `<` 必须转义**，
/// 否则内联进 `<script>` 会被解析成一个标签，页面直接白）。
///
/// [focus] 非空表示这一篇是从搜索命中打开的：渲染完要滚到那一段并高亮
/// （见 [PreviewFocus]）。此时**不做位置还原** —— 读者要的是命中，不是上次读到哪。
String buildMarkdownPayload({
  required String markdown,
  required bool dark,
  required double fontSize,
  required String token,
  required PreviewAnchor restore,
  PreviewFocus? focus,
}) {
  return jsonEncode(<String, Object?>{
    // `\$` 必须在进页面之前换成占位字符：marked 会把它还原成裸 `$`，
    // 到模板里就分不清「作者要字面量」还是「作者要公式」（见 markdown_escape.dart）。
    'markdown': protectEscapedDollars(markdown),
    'dark': dark,
    'fontSize': fontSize,
    'token': token,
    'restore': restore.toJson(),
    if (focus != null) 'focus': focus.toJson(),
  }).replaceAll('<', r'\u003c');
}

/// 把模板里的占位符换成实际资源与载荷。
///
/// 资源读取由 [load] 注入（生产是 `rootBundle.loadString`，测试里给假实现），
/// 这样这条「模板 + 多处替换」的流水线不必碰 Flutter 的资源通道。
///
/// 两处细节是有来历的：
/// - 底色占位符出现**两处**（html/body 与 `.markdown-body`），所以用 `replaceAll`；
/// - 其余占位符各一次，用 `replaceFirst` —— 用 all 会把正文里恰好出现的同样字符串
///   （代码块里写给读者看的模板片段）一起换掉。
///
/// [markdown] 只用于**门控**（见 [detectMarkdownExtras]）：不含公式的文档不内联
/// KaTeX 的 0.66 MB 资产，对应占位按空串替换（不是留着占位符 —— 那样模板里会漏出
/// `/*__…__*/`，也会让「同一份模板两种形态」变得难查）。
Future<String> buildMarkdownHtml({
  required Future<String> Function(String path) load,
  required bool dark,
  required String background,

  /// 正文色与图表描边色（见 `markdown_view.dart` 的 `_previewColors`）：
  /// 网页里的 `body` 没有 color 规则，不显式给的话图表会取到浏览器默认黑。
  required String foreground,
  required String border,
  required String payload,
  required String markdown,
  bool ink = false,
}) async {
  final MarkdownExtras extras = detectMarkdownExtras(markdown);
  final String html = await load(WebAssets.markdownViewHtml);
  final String mdCss = await load(
    dark ? WebAssets.mdDarkCss : WebAssets.mdLightCss,
  );
  final String hljsCss = await load(
    dark ? WebAssets.hljsDarkCss : WebAssets.hljsLightCss,
  );
  // 墨水屏档在浅色表之上**再叠一层覆盖**：布局规则仍来自 light，`*-ink.css`
  // 只做两件事 —— 把带颜色的变量压成黑白、把"靠浅灰底分层"换成 1px 黑线。
  // 单独维护一份完整 ink 表会跟上游 GitHub 样式漂移，覆盖式的维护成本低得多。
  final String mdThemeCss =
      ink ? '$mdCss\n${await load(WebAssets.mdInkCss)}' : mdCss;
  final String hljsThemeCss =
      ink ? '$hljsCss\n${await load(WebAssets.hljsInkCss)}' : hljsCss;
  // 公式（含化学式）：只有这篇文档真的写了公式才加载。mhchem 依赖全局 katex，
  // 模板里必须排在 katex 之后（见 markdown_view.html 的注释）。
  final String katexCss = extras.math ? await load(WebAssets.katexCss) : '';
  final String katexJs = extras.math ? await load(WebAssets.katexJs) : '';
  final String mhchemJs = extras.math ? await load(WebAssets.mhchemJs) : '';
  // 图表：只有出现 ```mermaid 围栏才内联 3.57 MB（Mermaid 12.x 更大，不用）。
  final String mermaidJs = extras.mermaid ? await load(WebAssets.mermaidJs) : '';
  return html
      .replaceAll('/*__MD_BACKGROUND__*/', background)
      .replaceAll('/*__MD_FOREGROUND__*/', foreground)
      .replaceAll('/*__MD_BORDER__*/', border)
      .replaceFirst('/*__MD_THEME_CSS__*/', mdThemeCss)
      .replaceFirst('/*__HLJS_THEME_CSS__*/', hljsThemeCss)
      .replaceFirst('/*__KATEX_CSS__*/', katexCss)
      .replaceFirst(
        '/*__MARKED_JS__*/',
        await load(WebAssets.markedJs),
      )
      // marked 不做 sanitize（v12 起连 sanitize 选项都删了），作者的 HTML 会原样
      // 回到 DOM。页面与回环资源服务同源（挂载仓库根），一个 <img onerror> 就够
      // 读出 .git/config 里的凭据 —— 所以输出必须过白名单清洗，见 D7。
      .replaceFirst(
        '/*__DOMPURIFY_JS__*/',
        await load(WebAssets.purifyJs),
      )
      .replaceFirst(
        '/*__HLJS_JS__*/',
        await load(WebAssets.highlightJs),
      )
      .replaceFirst(
        '/*__HLJS_DART_JS__*/',
        await load(WebAssets.highlightDartJs),
      )
      .replaceFirst('/*__KATEX_JS__*/', katexJs)
      .replaceFirst('/*__MHCHEM_JS__*/', mhchemJs)
      .replaceFirst('/*__MERMAID_JS__*/', mermaidJs)
      // 「按片段定位并高亮」的那段脚本：与 HTML 预览共用一份源码
      // （见 [kPreviewFocusJs]），别在模板里另抄一遍。
      .replaceFirst('/*__FOCUS_JS__*/', kPreviewFocusJs)
      .replaceFirst('/*__PAYLOAD__*/', payload);
}
