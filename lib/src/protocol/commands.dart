/// Dart → 页面的**滚动原语**。
///
/// 整个包只允许两条：`mdScrollToLine(n)`（Markdown）与
/// `hyperLensScrollToPath(p)`（HTML）。任何新跳转（目录、搜索命中、锚点、AST 节点）
/// 都必须复用它们 —— 每多一条原语，就多一套「顶对齐 / 吸顶补偿 / 夹底」的实现，
/// 而这三件事的细节在两边已经各踩过一次坑（见 `html_anchor.dart` 的 clamp、
/// `markdown_view.html` 的 mdScrollToLine）。
///
/// 调用方拿到的是一段 JS 字符串，交给自己的 `runJavaScript` 执行 —— 包不碰 WebView。
library;

import 'focus_script.dart';
import 'js_literal.dart';
import '../model/preview_focus.dart';
import '../model/preview_position.dart';
import '../model/preview_syntax.dart';

/// 页面里的 JS 全局名与函数名（与模板、注入脚本逐字一致，见各自的注释）。
///
/// 改这里必须同时改：`assets/web/markdown_view.html` 的 `mdScrollToLine`、
/// `html_anchor.dart` 的 `hyperLensScrollToPath`。
abstract final class HyperlensCommands {
  /// 把某个地址滚到视口顶端。地址类型决定用哪条原语 —— 调用方不判断。
  ///
  /// [kind] 只有在「地址与文档对不上」时才有用：HTML 页面拿到 [PreviewSourceAddress]
  /// （最常见的来源是新建文档时传的 `PreviewPosition.top`）说明调用方把 Markdown
  /// 那套坐标带到了 HTML —— 此时按设计回**顶部**（`scrollToPath('body')`），而不是
  /// 发一条 HTML 页面根本没有的 `mdScrollToLine(1)`：那条命令在页面上是
  /// `ReferenceError`，表现成「点了没反应」，日志里却看不出是地址给错了。
  static String forPosition(
    PreviewPosition position, {
    PreviewSourceKind? kind,
  }) =>
      switch (position) {
        PreviewSourceAddress(:final int line) => kind == PreviewSourceKind.html
            ? scrollToPath(PreviewDomAddress.body.path)
            : scrollToLine(line),
        PreviewDomAddress(:final String path) => scrollToPath(path),
      };

  /// Markdown：滚到源码第 [line] 行（1 起）。
  static String scrollToLine(int line) =>
      'mdScrollToLine(${line < 1 ? 1 : line})';

  /// Markdown：请求一份**完整**语法树（含子块与 inline token）。
  ///
  /// 首屏只发骨架（见 `preview_syntax.dart`）—— 完整树重得多，等结构面板真的要
  /// 展开某一段时再拉。页面收到后会再发一条 `ast` 回执，与骨架同一套闸门。
  /// 不是滚动原语，但同属「Dart 命令 → 页面」这一个方向，放在一起便于查改名。
  static String requestSyntaxAst() =>
      'window.hyperlensSyntaxAst && window.hyperlensSyntaxAst()';

  /// HTML：把 DOM 路径 [path] 指向的节点滚到视口顶端。
  ///
  /// 地址走 [jsSingleQuoted]：它可能来自**跨会话持久化**（[PreviewDomAddress] 不限
  /// 格式），一条换行就足以让整条命令报废。
  static String scrollToPath(String path) =>
      'hyperLensScrollToPath(${jsSingleQuoted(path)})';

  /// 对**已经打开的页面**补一次搜索定位：高亮 [focus] 指向的那一处并滚到视口中间。
  ///
  /// 渲染期用 `HyperlensPage.focus` 就够了；这条是给「页面不动、只换命中」的场景
  /// （HTML 预览从搜索打开时也是这一条）。返回整段「脚本 + 调用」，调用方直接
  /// `runJavaScript` 跑 —— 重复执行只是重新定义同一批函数，无害。
  ///
  /// 页面里没有 `hyperLensApplyFocus`（例如 HTML 页面脚本被关掉了）时，调用方会拿到
  /// 一个 `ReferenceError`：包不替你吞掉它，那说明这次注入没生效。
  ///
  /// 给了 [channelName] 时顺带回一条 `focus` 回执（凭据位写 `-`）：这样 Markdown 与
  /// HTML 对「命中亮了几处」的反馈是同一条消息 —— Markdown 模板自己发、带凭据，
  /// HTML 由这段脚本发。
  static String forFocus(PreviewFocus focus, {String? channelName}) =>
      previewFocusScript(focus, channelName: channelName);
}
