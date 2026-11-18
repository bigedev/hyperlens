/// WebView 与页面模板（`assets/web/*.html`）之间**必须逐字一致**的协议字符串。
///
/// 为什么集中：这些值在两边各写一份，改一处漏一处的表现是
/// 「回执永远不来 → 看门狗超时 → 提示退出重进」，从日志里几乎看不出是拼错了；
/// 而模板是资源文件，Dart 侧无法 import，只能靠这里的常量和模板注释互相指认。
///
/// 模板侧对应位置：
/// - 通道名：`window.HyperLens.postMessage(...)`（`markdown_view.html`）
/// - 回执前缀：`post('render ' + token + ...)`
class JsProtocol {
  const JsProtocol._();

  /// JS 通道名（Dart 侧 `addJavaScriptChannel`，模板侧 `window.<channel>`）。
  static const String channel = 'HyperLens';

  /// 渲染回执的前缀：页面拼成 `<前缀><token> <正文>`。
  ///
  /// 带空格，所以下面 `message.substring(prefix.length)` 之后就是 token 的开头。
  static const String receiptPrefix = 'render ';
}
