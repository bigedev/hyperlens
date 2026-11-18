/// Dart → 页面的**滚动原语**。
///
/// 整个包只允许两条：`mdScrollToLine(n)`（Markdown）与
/// `hyperLensScrollToPath(p)`（HTML）。任何新跳转（目录、搜索命中、锚点、AST 节点）
/// 都必须复用它们 —— 每多一条原语，就多一套「顶对齐 / 吸顶补偿 / 夹底」的实现，
/// 而这三件事的细节在两边已经各踩过一次坑（见 `html_anchor.dart` 的 clamp、
/// `markdown_view.html` 的 mdScrollToLine）。
///
/// 调用方拿到的是一段 JS 字符串，交给宿主的 `runJavaScript` 执行 —— 包不碰 WebView。
library;

import '../model/preview_position.dart';

/// 页面里的 JS 全局名与函数名（与模板、注入脚本逐字一致，见各自的注释）。
///
/// 改这里必须同时改：`assets/web/markdown_view.html` 的 `mdScrollToLine`、
/// `html_anchor.dart` 的 `hyperLensScrollToPath`。
abstract final class HyperlensCommands {
  /// 把某个地址滚到视口顶端。地址类型决定用哪条原语 —— 调用方不判断。
  static String forPosition(PreviewPosition position) => switch (position) {
        SourceAddress(:final int line) => scrollToLine(line),
        DomAddress(:final String path) => scrollToPath(path),
      };

  /// Markdown：滚到源码第 [line] 行（1 起）。
  static String scrollToLine(int line) =>
      'mdScrollToLine(${line < 1 ? 1 : line})';

  /// HTML：把 DOM 路径 [path] 指向的节点滚到视口顶端。
  static String scrollToPath(String path) =>
      'hyperLensScrollToPath(${_jsString(path)})';

  /// 单引号字符串字面量：`'` 与 `\` 要转义，`<` 一并转掉（内联进 `<script>`
  /// 时它可能被解析成标签，与 `payload.dart` 的载荷同一个口径）。
  static String _jsString(String value) => "'${value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('<', r'\u003c')}'";
}
