import 'package:meta/meta.dart';

/// 渲染一页预览需要的视觉参数。
///
/// 颜色一律用 `#rrggbb` 字符串，**不是 `Color`**：包内不 import flutter（`Color`
/// 来自 `dart:ui`），而这些值最终是拼进 CSS 文本的，字符串就是最短路径。
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
/// （宿主就是这么做——它的底色来自应用主题，深色档还被截图逐像素核过）。
/// 预设与宿主的取值不必一致，改这里不影响使用方。
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
