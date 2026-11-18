/// WebView 与页面模板（`assets/web/*.html`）之间**必须逐字一致**的协议字符串。
///
/// 为什么集中：这些值在两边各写一份，改一处漏一处的表现是
/// 「回执永远不来 → 看门狗超时 → 提示退出重进」，从日志里几乎看不出是拼错了；
/// 而模板是资源文件，Dart 侧无法 import，只能靠这里的常量和模板注释互相指认。
///
/// 模板侧对应位置：
/// - 通道名：`window.<channelName>.postMessage(...)`（`markdown_view.html` 的占位符、
///   `html_anchor.dart` 注入脚本的占位符）
/// - 回执前缀：`post('render ' + token + ...)`、`post('ast ' + ...)`、`post('scroll ' + ...)`
///
/// **每条回执前缀都在这里定义，别在模型或注入脚本旁边另起一个 `kXxxPrefix`**：那些
/// 常量原本散在 `html_outline.dart` / `html_anchor.dart` / `bridge.dart` 三处，
/// 同一个 `'outline '` 写了两遍 —— 改一处漏一处的代价见文件头。
///
/// 名字带包前缀（不是裸 `Protocol`）：使用方 import 后与自己的同名类撞车的代价，
/// 比多打几个字高得多。
class HyperlensBridge {
  const HyperlensBridge._();

  /// 默认 JS 通道名（Dart 侧 `addJavaScriptChannel`，页面侧 `window.<channelName>`）。
  ///
  /// 与包品牌一致：页面是给使用方与三方看的，挂宿主品牌等于把别人的广告印在
  /// 自己页面上。两条渲染入口都允许使用方换成自己的名字：`MarkdownPage.channelName`
  /// 与 `htmlAnchorScript(channelName:)` —— WebView 侧注册的名字必须与之一致。
  static const String channelName = 'HyperLens';

  /// 渲染回执的前缀：页面拼成 `<前缀><token> <正文>`。
  ///
  /// 带空格，所以 `message.substring(prefix.length)` 之后就是 token 的开头。
  static const String receiptPrefix = 'render ';

  /// `link <href>`（点链接）；href 是 URL 编码后的整段。
  static const String linkPrefix = 'link ';

  /// `top <token> <JSON>`（阅读位置）。
  static const String positionPrefix = 'top ';

  /// `outline <token> <JSON>`（章节清单；HTML 侧没有凭据）。
  static const String outlinePrefix = 'outline ';

  /// `ast <token> <JSON>`（语法树；HTML 侧没有凭据）。
  static const String astPrefix = 'ast ';

  /// `focus <token> <JSON>`（搜索命中已高亮）。
  static const String focusPrefix = 'focus ';

  /// `anchor <token> <目标>`（页内锚点已滚动到位）。
  static const String anchorPrefix = 'anchor ';

  /// `scroll <JSON>`（HTML 侧的阅读位置）。
  ///
  /// 与 Markdown 的 [positionPrefix] 不同名：HTML 的地址是 DOM 路径，没有源码行。
  static const String scrollPrefix = 'scroll ';

  /// 通道名要原样拼进 `window.<name>`：不是合法标识符的话页面会直接抛语法错误，
  /// 表现为整页空白（HTML 注入脚本则整段失效）—— 这种错在真机上极难归因，
  /// 所以在拼装阶段就拦下来。两条渲染入口共用这一处校验。
  static void checkChannelName(String name) {
    if (!_identifier.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'channelName',
        'JS 通道名必须是合法标识符（字母/下划线开头，只含字母数字下划线）',
      );
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
}
