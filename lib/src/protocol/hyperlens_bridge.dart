/// WebView 与页面模板（`assets/web/*.html`）之间**必须逐字一致**的协议字符串。
///
/// 为什么集中：这些值在两边各写一份，改一处漏一处的表现是
/// 「回执永远不来 → 看门狗超时 → 提示退出重进」，从日志里几乎看不出是拼错了；
/// 而模板是资源文件，Dart 侧无法 import，只能靠这里的常量和模板注释互相指认。
///
/// 模板侧对应位置：
/// - 通道名：`window.<channelName>.postMessage(...)`（`markdown_view.html` 的占位符、
///   `html_anchor.dart` 注入脚本的占位符）
/// - 回执信封：`post('<前缀>' + token + ' ' + 载荷)`，无凭据时 token 写 [noToken]
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
  /// 与包品牌一致：页面是给使用方与三方看的，挂调用方品牌等于把别人的广告印在
  /// 自己页面上。两条渲染入口都允许使用方换成自己的名字：`HyperlensPage.channelName`
  /// 与 `htmlAnchorScript(channelName:)` —— WebView 侧注册的名字必须与之一致。
  static const String channelName = 'HyperLens';

  /// 「这份文档没有回执凭据」的占位。
  ///
  /// 信封统一是 `<前缀><凭据> <载荷>`，凭据缺失时写它 —— **不用「载荷以 `{` 开头」
  /// 之类的嗅探**：`render` 的载荷是一句人话（`ok（…）`），JSON 判据在那个前缀上
  /// 直接失效，而 `-` 是确定的、可测的。
  ///
  /// Markdown 侧凭据由调用方给（用来丢弃换文档后旧页面的收尾回执）；HTML 侧每次
  /// 提交都是整页重载，不存在旧页面还在报，一律写 [noToken]。
  static const String noToken = '-';

  /// 渲染回执的前缀：页面拼成 `<前缀><凭据> <正文>`。
  ///
  /// 带空格，所以 `message.substring(prefix.length)` 之后就是凭据的开头。
  static const String receiptPrefix = 'render ';

  /// `link <编码后的 href>`（点链接）。不带凭据：它没有「哪一版文档」的问题。
  static const String linkPrefix = 'link ';

  /// `top <凭据> <JSON>`（阅读位置）：Markdown 带 `line`，HTML 带 `path`。
  ///
  /// 两种文档共用一条：位置就是位置，不因为格式不同换名字。
  static const String positionPrefix = 'top ';

  /// `outline <凭据> <JSON>`（章节清单）。
  static const String outlinePrefix = 'outline ';

  /// `ast <凭据> <JSON>`（语法树）。
  static const String astPrefix = 'ast ';

  /// `focus <凭据> <处数>`（搜索命中已高亮）。
  static const String focusPrefix = 'focus ';

  /// `anchor <目标>`（页内锚点已滚动到位）。不带凭据。
  static const String anchorPrefix = 'anchor ';

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

  /// 凭据要原样拼进信封：含空格会被拆成两截（载荷前半段变成凭据），
  /// 等于整条回执被静默丢弃。`-` 是「无凭据」的占位，不能让调用方用它当凭据。
  static void checkToken(String token) {
    if (token.isEmpty || token == noToken || token.contains(' ')) {
      throw ArgumentError.value(
        token,
        'token',
        '凭据不能为空、不能含空格、不能是「无凭据」占位 "-"',
      );
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
}
