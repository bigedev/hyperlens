import 'package:meta/meta.dart';

/// 渲染一页预览需要的视觉参数。
///
/// 颜色一律用 `#rrggbb` 字符串，**不是 `Color`**：包内不 import flutter（`Color`
/// 来自 `dart:ui`），而这些值最终是拼进 CSS 文本的，字符串就是最短路径。
///
/// 这不再是口头约定：三个颜色在渲染入口（`buildMarkdownHtml` / `htmlPreviewCss`）
/// 都会过一遍十六进制校验，命名色、`rgb()`、`var()` 一律拒绝 —— 它们被**原样**
/// 拼进 `<style>`，`#fff}</style><script>…` 足以破出样式块。自定义配色请先转成
/// 十六进制（`#rgb` / `#rgba` / `#rrggbb` / `#rrggbbaa`）。
///
/// 两个维度**互相独立**：[isDark] 决定取深色还是浅色那套主题表，[isInk] 决定要不要
/// 再叠一层单色覆盖层。四个组合都有意义，最常见的是：
///
/// | 组合 | 长相 |
/// |---|---|
/// | 都不设 | 普通浅色 |
/// | [isDark] | 普通深色 |
/// | [isInk] | 墨水屏浅色（白底黑字 + 1px 黑线，墨水屏的默认态） |
/// | [isDark] + [isInk] | 墨水屏深色（黑底白字，即浅色态的反白） |
///
/// 预设只是「不给主题时也能看」的默认值：使用方有自己的配色体系时应该自己构造
/// （调用方通常就是这么做的 —— 底色来自它自己的应用主题，深色档还要逐像素核过）。
/// 预设与调用方的取值不必一致，改这里不影响使用方。
///
/// **加档位要连 `==` / `hashCode` 一起加。** 渲染结果是**快照**：底色、正文色、
/// 覆盖层都在加载那一刻拼进 HTML，页面已经打开就改不动（OHOS 上
/// `WebView.setBackgroundColor` 对已加载页面不重绘）。于是宿主普遍拿这个类当
/// 「这一页该长什么样」的唯一定义 —— 例如 bige-editor 的 `HtmlPreviewView` 会把
/// **上次注入的** `HyperlensTheme` 与本帧算出来的比一比，不相等就整页重载。
///
/// 所以：凡影响注入 CSS 的东西都必须是本类字段，并参与 `==` / `hashCode`。漏一个
/// 的表现不是报错，而是「切了主题页面没变」。
///
/// 反面例子（2026-11-19 真机）：墨屏与浅色的**底色都是 `#ffffff`**，只有 [isInk]
/// 不同。宿主当时只比底色，「墨屏 → 浅色」判定为没变 ⇒ 不重载 ⇒ 页面留在墨屏那层
/// 单色覆盖里，书里彩色的标题全变成黑字。别让宿主去猜哪些字段影响长相：让它比这个
/// 类。
@immutable
class HyperlensTheme {
  const HyperlensTheme({
    required this.background,
    required this.foreground,
    required this.border,
    this.fontSize = 16,
    this.isDark = false,
    this.isInk = false,
  });

  /// 页面底色。会替换模板里两处占位符（`html/body` 与 `.markdown-body`）。
  final String background;

  /// 正文色与图表描边色。网页里的 `body` 没有 color 规则，不显式给的话
  /// Mermaid 图表会取到浏览器默认黑。
  final String foreground;

  /// 图表/表格描边色（CSS 变量 `--md-border-default`）。
  final String border;

  /// 正文基准字号（逻辑像素）。页面按它排版，`rem`/`em` 的相对关系不变。
  final double fontSize;

  /// 深色档：主题表与高亮表都取 dark 那套（与 [isInk] 叠加时取墨水屏的反白版）。
  final bool isDark;

  /// 墨水屏档：在主题表之上**再叠一层单色覆盖层**（覆盖层只做两件事：把带颜色的
  /// 变量压成黑白、把「靠浅灰底分层」换成 1px 黑线）。
  ///
  /// 覆盖层分浅色与反白两份（`*-ink.css` / `*-ink-dark.css`）：墨水屏设备默认是
  /// 浅色（白底黑字），也能开深色，深色就是浅色的反白。选哪份看 [isDark]。
  final bool isInk;

  static const HyperlensTheme light = HyperlensTheme(
    background: '#ffffff',
    foreground: '#1f2328',
    border: '#d0d7de',
  );

  static const HyperlensTheme dark = HyperlensTheme(
    background: '#0d1117',
    foreground: '#e6edf3',
    border: '#30363d',
    isDark: true,
  );

  /// 墨水屏默认态：白底黑字。
  static const HyperlensTheme ink = HyperlensTheme(
    background: '#ffffff',
    foreground: '#000000',
    border: '#000000',
    isInk: true,
  );

  /// 墨水屏深色：上面那份的反白（黑底白字）。
  static const HyperlensTheme inkDark = HyperlensTheme(
    background: '#000000',
    foreground: '#ffffff',
    border: '#ffffff',
    isDark: true,
    isInk: true,
  );

  @override
  bool operator ==(Object other) =>
      other is HyperlensTheme &&
      other.background == background &&
      other.foreground == foreground &&
      other.border == border &&
      other.fontSize == fontSize &&
      other.isDark == isDark &&
      other.isInk == isInk;

  @override
  int get hashCode => Object.hash(
        background,
        foreground,
        border,
        fontSize,
        isDark,
        isInk,
      );

  @override
  String toString() => 'HyperlensTheme(background: $background, '
      'foreground: $foreground, border: $border, fontSize: $fontSize, '
      'isDark: $isDark, isInk: $isInk)';
}
