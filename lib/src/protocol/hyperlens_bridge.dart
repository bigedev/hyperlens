/// WebView 与页面模板（`assets/web/*.html`）之间**必须逐字一致**的协议字符串。
///
/// 为什么集中：这些值在两边各写一份，改一处漏一处的表现是
/// 「回执永远不来 → 看门狗超时 → 提示退出重进」，从日志里几乎看不出是拼错了；
/// 而模板是资源文件，Dart 侧无法 import，只能靠这里的常量和模板注释互相指认。
///
/// 模板侧对应位置：
/// - 通道名：`window.HyperLens.postMessage(...)`（`markdown_view.html`）
/// - 回执前缀：`post('render ' + token + ...)`
///
/// 名字带包前缀（不是裸 `Protocol`）：使用方 import 后与自己的同名类撞车的代价，
/// 比多打几个字高得多。
class HyperlensBridge {
  const HyperlensBridge._();

  /// JS 通道名（Dart 侧 `addJavaScriptChannel`，模板侧 `window.<channelName>`）。
  ///
  /// 与包品牌一致：页面是给使用方与三方看的，挂宿主品牌等于把别人的广告印在
  /// 自己页面上。模板里当前按这个名字写死；「通道名可配」随渲染入口
  /// （`MarkdownPage` 把通道名注入模板）一起做，届时改成实例字段。
  static const String channelName = 'HyperLens';

  /// 渲染回执的前缀：页面拼成 `<前缀><token> <正文>`。
  ///
  /// 带空格，所以 `message.substring(prefix.length)` 之后就是 token 的开头。
  static const String receiptPrefix = 'render ';
}
