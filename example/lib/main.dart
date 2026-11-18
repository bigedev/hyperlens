/// hyperlens 的示例：一个页面，把「文档 → 载荷 → 回执」整条链路走一遍。
///
/// 演示五件事，正好对应用这个包需要的五步：
///
/// 1. **渲染**：`HyperlensPage.fromText(...).render(...)` 得到一份可以直接交给
///    `loadHtmlString` 的整页 HTML —— Markdown 与 HTML 两条路同一个入口；
/// 2. **回执**：注册 `HyperlensBridge.channelName`，用 `PreviewEvent.parse` 分发；
/// 3. **目录**：章节清单走同一条回执，点击只用一条命令
///    `HyperlensCommands.forPosition(entry.address)`（Markdown 是源码行，HTML 是 DOM 路径，
///    调用方不判断）；
/// 4. **位置**：把上报的 `PreviewPosition` 存下来 —— 但要分两个值：「此刻在哪」跟着
///    每条回执走；「上次读到哪」只在**离开阅读处**（回顶部 / 换文档）那一刻定格，
///    重开时传回 `restore` 落回原处。两条判据混成一个，这个按钮就永远等于原地重开；
/// 5. **语法树**：首屏来骨架（`ast` 回执），点「语法树」再用
///    `HyperlensCommands.requestSyntaxAst()` 拉完整树。
///
/// 示例文档都写成**两段**：第一段英文、第二段中文，方便对照排版差异；Markdown 那份
/// 还带了公式（KaTeX）与图表（Mermaid）—— 这两样由包里按内容自动门控，调用方不用开关。
///
/// 宿主自己负责的部分这里都留着：WebView 生命周期、页面外壳、目录 UI —— 包不碰 UI。
///
/// 平台：官方的 `webview_flutter` 只实现 android / ios / macos。windows / linux 上
/// 本示例照常编译运行，只是把载荷以源码形式展示 —— 库本身是纯 Dart，与平台无关，
/// 那两平台接自己的 WebView 即可（其余代码不用改）。
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';
import 'package:hyperlens/root_bundle.dart';
// 唯一 import flutter 的入口：rootBundle 版资产读取。纯 Dart 场景自己实现
// HyperlensAssetLoader 即可，主入口 hyperlens.dart 不依赖 flutter。
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const _DemoApp());

/// 演示用文档：一份 Markdown、一份 HTML。真实宿主这里换成读文件。
///
/// 两份都是「第一段英文、第二段中文」。Markdown 那份还带公式与图表 —— 包里按内容
/// 自动判要不要内联 KaTeX / Mermaid（`detectMarkdownExtras`），调用方没有开关。
const String _markdownDemo = r'''
# hyperlens demo

Part 1 — English

## One address, two documents

- A Markdown address is a **source line**; the page reports the line the reader settled on.
- An HTML address is a **DOM path** such as `body>article>h2:nth(2)`.

Both live in the same `PreviewPosition`, so "jump to a section" and "come back to where
I was reading" are one code path.

## Math

Inline math works: $a^2 + b^2 = c^2$, and so does a block:

$$
\int_{0}^{1} x^2\,\mathrm{d}x = \frac{1}{3}
$$

## Diagram

```mermaid
flowchart LR
  src[source] --> render[render payload]
  render --> view[your WebView]
  view -->|receipts| host[your app]
```

## Receipts

| receipt | payload |
| --- | --- |
| `render` | the submitted page is alive |
| `position` | reading position + viewport |
| `outline` | section list |
| `ast` | syntax tree (skeleton first) |

```dart
final html = await HyperlensPage.fromText(
  source: text,
  path: 'demo/a.md',
).render(assets: const HyperlensRootBundleAssetLoader());
```

> Link clicks are intercepted as well: try [this section](#receipts) or
> [pub.dev](https://pub.dev/packages/hyperlens).

---

# hyperlens 示例

第二部分 —— 中文

## 一套坐标，两种文档

- Markdown 的地址是**源码行**，滚动停下时页面把行号发回来；
- HTML 的地址是 **DOM 路径**（`body>article>h2:nth(2)`）。

两种地址放在同一个 `PreviewPosition` 里，所以「跳到某一节」与「返回时落回读到的
位置」是同一条代码路径。

## 公式

行内公式：$e^{i\pi} + 1 = 0$；块级公式：

$$
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
$$

## 图表

```mermaid
sequenceDiagram
  页面->>宿主: render ok
  宿主->>页面: mdScrollToLine(12)
  页面->>宿主: position + outline + ast
```

## 回执

| 回执 | 载荷 |
| --- | --- |
| `render` | 这次提交的页面活着 |
| `position` | 阅读位置 + 视口 |
| `outline` | 章节清单 |
| `ast` | 语法树骨架 |

> 侧栏点一条标题试试：那条命令走的是 [HyperlensCommands.forPosition]。

链接也拦下来了：点 [这一段](#回执) 或 [外链](https://pub.dev/packages/hyperlens)。
''';

/// HTML 那一份走的是「看别人的页面」：样式、图表、公式都由作者自己带。
///
/// 公式这里用 MathML（浏览器原生支持），因为 HTML 预览**不注入** KaTeX —— 那是
/// Markdown 那份才有的增强；作者要公式就自己带渲染器或 MathML。
const String _htmlDemo = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>hyperlens demo</title>
  <style>
    body { font-family: Georgia, serif; max-width: 40em; margin: 2em auto; padding: 0 1em; }
    h1 { border-bottom: 2px solid currentColor; padding-bottom: .3em; }
    .note { padding: .6em .8em; border-left: 3px solid #888; }
    svg { display: block; margin: 1em 0; }
    math { font-size: 1.15em; }
  </style>
</head>
<body>
  <h1>HTML preview</h1>
  <p>Part 1 — English. Author styles are kept as written: this side is "look at someone
     else's page", not "re-typeset it for them".</p>

  <h2>A chart, drawn by the author</h2>
  <p>Scripts are stripped, so the picture has to be markup — here it is inline SVG:</p>
  <svg width="300" height="110" viewBox="0 0 300 110" role="img" aria-label="bar chart">
    <line x1="10" y1="95" x2="290" y2="95" stroke="#888" stroke-width="1"></line>
    <rect x="30"  y="55" width="40" height="40" fill="#3b6ea5"></rect>
    <rect x="100" y="35" width="40" height="60" fill="#5b8fc4"></rect>
    <rect x="170" y="15" width="40" height="80" fill="#7fb0dd"></rect>
    <rect x="240" y="70" width="40" height="25" fill="#a9cbe8"></rect>
    <text x="50"  y="108" font-size="10" text-anchor="middle" fill="#555">render</text>
    <text x="120" y="108" font-size="10" text-anchor="middle" fill="#555">position</text>
    <text x="190" y="108" font-size="10" text-anchor="middle" fill="#555">outline</text>
    <text x="260" y="108" font-size="10" text-anchor="middle" fill="#555">ast</text>
  </svg>

  <h2>Math, brought by the author</h2>
  <p>No KaTeX is injected into an HTML page — MathML is the built-in way:</p>
  <math display="block">
    <mi>x</mi><mo>=</mo>
    <mfrac>
      <mrow><mo>−</mo><mi>b</mi><mo>±</mo>
        <msqrt><mrow><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></mrow></msqrt>
      </mrow>
      <mrow><mn>2</mn><mi>a</mi></mrow>
    </mfrac>
  </math>

  <h2>Scripts</h2>
  <p class="note">Author scripts are stripped by default: rendering only opens the door for
     our own bridge, so positions and the outline stay in sync.</p>
  <p><a href="https://pub.dev/packages/hyperlens">pub.dev</a></p>

  <hr>

  <h1>HTML 预览</h1>
  <p>第二部分 —— 中文。作者写的样式原样保留 —— 这一档讲的是「看别人的页面」，
     不是替它定排版。</p>

  <h2>只有一条命令</h2>
  <p>章节从 <code>h1~h6</code>（含 ARIA 标题）扫出来，地址是 DOM 路径，
     所以目录点击与 Markdown 走同一个位置类型。</p>

  <h3>回执</h3>
  <ol>
    <li><code>render</code>：这次提交的页面活着；</li>
    <li><code>position</code>：阅读位置 + 视口；</li>
    <li><code>outline</code>：章节清单；</li>
    <li><code>ast</code>：语法树（先来骨架）。</li>
  </ol>

  <h2>表格</h2>
  <table border="0" cellpadding="6" style="border-collapse: collapse;">
    <tr><th align="left">回执</th><th align="left">载荷</th></tr>
    <tr><td><code>render</code></td><td>这次提交的页面活着</td></tr>
    <tr><td><code>position</code></td><td>阅读位置 + 视口</td></tr>
    <tr><td><code>outline</code></td><td>章节清单</td></tr>
  </table>
</body>
</html>
''';

/// 官方 `webview_flutter` 覆盖的平台；其余平台降级成展示载荷。
bool get _hasWebView =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };

class _DemoApp extends StatelessWidget {
  const _DemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'hyperlens example',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3B6EA5)),
        home: const _DemoPage(),
        debugShowCheckedModeBanner: false,
      );
}

class _DemoPage extends StatefulWidget {
  const _DemoPage();

  @override
  State<_DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<_DemoPage> {
  /// 三档主题：颜色与字号都由调用方给，包里只有「不给也能看」的预设。
  static const List<(String, HyperlensTheme)> _themes = <(String, HyperlensTheme)>[
    ('Light', HyperlensTheme.light),
    ('Dark', HyperlensTheme.dark),
    ('Ink', HyperlensTheme.ink),
  ];

  /// 没有 WebView 的平台最多摆这么多字符（载荷可能有几 MB，见 [_body]）。
  static const int _maxPreviewChars = 20000;

  /// 平台有 WebView 实现时才创建：官方包在 windows / linux 上**构造**
  /// `WebViewController()` 就会抛错（平台实现没注册），所以这里必须按平台判空。
  WebViewController? _controller;

  PreviewSourceKind _kind = PreviewSourceKind.markdown;
  int _themeIndex = 0;

  /// 最近一次提交的载荷：windows / linux 下用它当演示内容。
  String _payload = '';

  /// 最近一条回执的文字：只喂页脚那一行。
  ///
  /// 用 [ValueNotifier] 而不是 `setState`：位置回执**每滚停一次**就来一条，整页重建
  /// 没有意义（`_outline` 那类真会影响布局的才用 setState）。
  final ValueNotifier<String> _status = ValueNotifier<String>('Ready to render…');

  /// 章节清单：`outline` 回执给的那份。
  PreviewOutline _outline = PreviewOutline.empty;

  /// **页面此刻在哪**：本档最新一条 `position` 回执（含程序性落位）。
  ///
  /// 换主题、换字号之后重新提交就靠它落回原处 —— 那不该把人扔回开头。
  final Map<PreviewSourceKind, PreviewPosition> _live =
      <PreviewSourceKind, PreviewPosition>{};

  /// **上次读到哪**：每种文档各定格一份（Markdown 是源码行，HTML 是 DOM 路径）。
  ///
  /// 只在**离开阅读处**的那一刻定格，而不是每滚一次就覆盖：
  /// - 回顶部之前 —— 读者这次阅读到此为止；
  /// - 切到另一份文档之前 —— 切回来要落回原处。
  ///
  /// 为什么不跟 `_live` 一起更新：两条判据混成一个，「回到上次位置」就必然等于原地
  /// 重开 —— 读者看不出这个按钮做过什么，示例也等于没演示 `restore`。真实阅读器通常
  /// 每次滚停就落盘（防进程被杀），那是宿主的持久化策略；这里演示的是
  /// 「离开时定格 → 回来落回原处」这一条语义。
  ///
  /// 为什么要分文档：`PreviewPosition` 只有两种地址，把 Markdown 的行号传给 HTML
  /// 页面没有意义（库里会兜成回顶部）。按地址类型分开存，切文档时各自落回自己的位置。
  final Map<PreviewSourceKind, PreviewPosition> _bookmark =
      <PreviewSourceKind, PreviewPosition>{};

  /// 刚做过一次**程序性移动**（提交新页面 / 回顶部）：只影响状态栏那行注解 ——
  /// 让读者知道这会儿报上来的「顶部」是我们摆的，不是他滚到的。
  DateTime? _programmaticUntil;

  /// 现在是不是「程序性移动」的窗口期。
  bool get _movingProgrammatically =>
      _programmaticUntil?.isAfter(DateTime.now()) ?? false;

  /// 当前这一页的凭据：每次提交换一个。
  ///
  /// 页面把凭据原样带回来（Markdown 带得回来，HTML 没有凭据位），所以「这条回执是不是
  /// 页面上现在这一份发的」能判。切主题 / 切文档时，上一页的迟到位置会记到新页账上 ——
  /// `_live` 被写脏之后，落位与目录都会错，而且一声不响。
  String _token = '';

  /// 屏幕上这一份是哪种文档。
  ///
  /// 判回执归属不能拿 [_kind]：读者按下档位开关的那一刻它就变了，而页面上还是上一份。
  PreviewSourceKind _committedKind = PreviewSourceKind.markdown;

  /// 提交序号：只用来拼 [_token]。
  int _commitSeq = 0;

  /// 这条回执是不是**页面上现在这一份**发的。
  bool _fromLivePage(String? token) =>
      _committedKind == PreviewSourceKind.markdown
          ? token == _token
          : token == null;


  /// 语法树：首屏只来骨架，点「语法树」时按需拉完整树。
  ///
  /// 用 [ValueNotifier] 而不是 setState：完整树可能在弹层已经打开之后才到。
  final ValueNotifier<PreviewSyntaxTree?> _syntax = ValueNotifier<PreviewSyntaxTree?>(null);

  @override
  void dispose() {
    _status.dispose();
    _syntax.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_hasWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            // 相对资源（同目录 css / 图片）找不着时只该记一条，不该让文档打不开。
            onWebResourceError: (WebResourceError error) =>
                debugPrint('Preview resource error: ${error.description}'),
          ),
        )
        // 通道名必须与 HyperlensPage.fromText(channelName:) 一致；不一致时
        // 页面照常显示，只是位置与目录**静默不更新**（没有任何报错）。
        ..addJavaScriptChannel(
          HyperlensBridge.channelName,
          onMessageReceived: _onMessage,
        );
    }
    // 首帧之后再提交：平台视图还没挂出来时，第一次 loadHtmlString 会被整个丢掉。
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  /// 一次渲染 = 一次提交。主题、文档、「回到上次位置」都走这里。
  ///
  /// [restore] 为空时落回**这份文档此刻的位置**（换主题、换字号不该把人扔回开头）；
  /// 传了就按传入地址落位 —— 「回到上次位置」传的是 [_bookmark] 定格的地址。
  Future<void> _render({PreviewPosition? restore}) async {
    final bool markdown = _kind == PreviewSourceKind.markdown;
    final PreviewPosition? target = restore ?? _live[_kind];
    final String token = 'c${++_commitSeq}';
    final HyperlensPage page = HyperlensPage.fromText(
      source: markdown ? _markdownDemo : _htmlDemo,
      kind: _kind,
      theme: _themes[_themeIndex].$2,
      // 落位：Markdown 用源码行、HTML 用 DOM 路径，各记各的。
      restore: target,
      // 凭据：页面会把它带回来，用来丢掉上一页的迟到回执（见 _fromLivePage）。
      token: token,
      channelName: HyperlensBridge.channelName,
    );
    // Markdown 必须给 assets（模板 / marked / KaTeX 都是随包资产），HTML 不需要。
    final String html;
    try {
      html = await page.render(
        assets: markdown ? const HyperlensRootBundleAssetLoader() : null,
      );
    } catch (error) {
      // 资产缺失 / 载荷拼装失败：页面保持上一份不动，原因写进状态栏 ——
      // 停在「Ready to render…」上等人猜是最糟的收场。
      if (mounted) {
        _status.value = 'Render failed: $error';
      }
      return;
    }
    if (!mounted) {
      return;
    }
    // 先换凭据再提交：从这一刻起，旧页面的回执都算迟到。
    _committedKind = _kind;
    _token = token;
    setState(() {
      _payload = html;
      _outline = PreviewOutline.empty;
    });
    _status.value = 'Committed (${html.length} chars): '
        '${markdown ? 'Markdown' : 'HTML'} / ${_themes[_themeIndex].$1}'
        '${target == null ? '' : ', landed on $target'}';
    try {
      await _loadPayload();
    } catch (error) {
      _status.value = 'Load failed: $error';
    }
  }

  /// 把最近一份载荷提交给 WebView。
  ///
  /// 相对的图片 / css 由调用方自己的资源服务提供（baseUrl），示例文档没有相对资源，
  /// 所以不传。没有 WebView 的平台（windows / linux）什么都不做：载荷已经摆出来了。
  Future<void> _loadPayload() async {
    final WebViewController? controller = _controller;
    if (controller == null || _payload.isEmpty) {
      return;
    }
    // 提交之后的一小段时间里，页面报上来的位置是我们把它摆到哪儿的结果
    // （落位本身就会滚动），不算读者读到的位置。
    _markProgrammatic();
    await controller.loadHtmlString(_payload);
  }

  /// 标记「接下来一小段是程序性移动」。
  void _markProgrammatic([int milliseconds = 1600]) {
    _programmaticUntil = DateTime.now().add(Duration(milliseconds: milliseconds));
  }

  /// 回到顶部：读者的阅读**到此为止** —— 先把此刻的位置定格成「上次位置」，
  /// 再滚上去。这样「回到上次位置」回的是他读到的最后一处，而不是顶部。
  Future<void> _jumpToTop() async {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    final PreviewPosition? here = _live[_kind];
    if (here != null) {
      // setState：工具栏的 tooltip 显示的就是这个值。
      setState(() => _bookmark[_kind] = here);
    }
    _markProgrammatic(800);
    await controller.runJavaScript(
      HyperlensCommands.forPosition(PreviewPosition.top, kind: _kind),
    );
    if (mounted) {
      _status.value = 'Back at the top (last position: ${_bookmark[_kind] ?? 'none'})';
    }
  }

  /// 通道回调：页面发来的就是一条回执文本。
  void _onMessage(JavaScriptMessage message) {
    // 页面拆卸 / 热重启之后，通道仍可能送来最后几条：没有这道闸就是
    // `setState() called after dispose()`。
    if (!mounted) {
      return;
    }
    // 认不出来的一律归到 PreviewUnknownMessage：页面与 Dart 版本不同步时别炸。
    final PreviewEvent event = PreviewEvent.parse(message.message);
    switch (event) {
      case PreviewRenderReady(:final String? token, :final String result):
        if (!_fromLivePage(token)) {
          return;
        }
        // [result] 是页面给自己的一句调试文案（`ok（…）` / `empty` / `异常: …`），
        // 语言由包决定，示例不上屏 —— 状态栏只说「这一页活着」。
        debugPrint('Render ready: $result');
        _status.value = 'Render ready';

      case PreviewPositionReported(
          :final String? token,
          :final PreviewPosition? position,
          :final int? section,
        ):
        if (!_fromLivePage(token)) {
          return;
        }
        // 每滚停一次都会来一条：这条只更新「此刻在哪」，不碰「上次读到哪」——
        // 后者要等读者离开（回顶部 / 目录跳转 / 切文档）才定格，否则两个值永远相等。
        final bool programmatic = _movingProgrammatically;
        if (position != null) {
          _live[_kind] = position;
        }
        // 只刷页脚那行字：整页 setState 会让 WebView 白跑一趟重建。
        _status.value = 'Current position: ${position ?? 'not reported'}'
            '${section == null ? '' : ' (section ${section + 1})'}'
            '${programmatic ? ' (programmatic)' : ''}';

      case PreviewOutlineReported(:final String? token, :final PreviewOutline outline):
        if (!_fromLivePage(token)) {
          return;
        }
        // 换字号 / 换底色重排都会再来一份：新清单是**等值的新对象**，
        // 需要判「换没换」时用 sameContentAs，别比对象身份。
        setState(() => _outline = outline);
        _status.value = 'Outline: ${outline.length} entries';

      case PreviewLinkTapped(:final String href):
        _status.value = 'Link tapped: $href';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Link handed to the host: $href')));

      case PreviewSyntaxReported(:final String? token, :final PreviewSyntaxTree tree):
        if (!_fromLivePage(token)) {
          return;
        }
        // 抽屉 / 弹层绑的是这个 notifier：完整树可能在弹层打开之后才到，用 ValueListenable
        // 才能就地刷新（外层 setState 刷不到已经建好的 bottom sheet）。
        _syntax.value = tree;
        _status.value = 'Syntax tree: ${tree.count} nodes'
            '${tree.truncated ? ' (truncated)' : ''}';

      // 示例没有搜索入口（`focus:` / `HyperlensCommands.forFocus` 未演示），
      // 这条留着是为了说明「命中高亮」也走同一个通道。
      case PreviewFocusApplied(:final String? token, :final int? count):
        if (!_fromLivePage(token)) {
          return;
        }
        _status.value = 'Focus: ${count ?? 0} matches';

      case PreviewAnchorScrolled(:final String target):
        _status.value = 'In-page anchor: $target';

      case PreviewUnknownMessage(:final String raw):
        _status.value = 'Unrecognized receipt: $raw';
    }
  }

  /// 目录点击：**一条命令**，两种文档同一条路。
  Future<void> _jumpTo(PreviewOutlineEntry entry) async {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    // 目录跳转是读者主动离开当前这一段：先定格，回来时这里就是「上次位置」。
    final PreviewPosition? here = _live[_kind];
    if (here != null) {
      setState(() => _bookmark[_kind] = here);
    }
    Navigator.of(context).pop(); // 先收抽屉，免得命令跑在收起动画里
    await controller.runJavaScript(
      HyperlensCommands.forPosition(entry.address, kind: _kind),
    );
  }

  /// 语法树：首屏只有骨架，这里再要一份**完整**树（含子块与 inline token）。
  ///
  /// 完整树重得多，所以它不在渲染路径上 —— 只有读者真要看结构时才拉。
  Future<void> _showSyntax() async {
    final WebViewController? controller = _controller;
    if (controller != null) {
      await controller.runJavaScript(HyperlensCommands.requestSyntaxAst());
    }
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _SyntaxSheet(syntax: _syntax),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('hyperlens example'),
        actions: [
          IconButton(
            tooltip: 'Back to top',
            onPressed: _jumpToTop,
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            // 没有定格过（还没离开过这份文档）就没东西可回。
            tooltip: 'Back to last position (${_bookmark[_kind] ?? 'none'})',
            onPressed: _bookmark[_kind] == null
                ? null
                : () => _render(restore: _bookmark[_kind]),
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: 'Syntax tree (AST)',
            onPressed: _showSyntax,
            icon: const Icon(Icons.account_tree),
          ),
          Builder(
            builder: (BuildContext context) => IconButton(
              tooltip: 'Outline (${_outline.length})',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.toc),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: _outline.isEmpty
              ? const Center(child: Text('No outline yet'))
              : ListView(
                  children: [
                    for (final PreviewOutlineEntry entry in _outline.entries)
                      ListTile(
                        dense: true,
                        // 层级只影响缩进：清单本身不折叠，折叠是宿主的 UI 选择。
                        contentPadding: EdgeInsets.only(
                          left: 16 + (entry.level - 1) * 16.0,
                          right: 16,
                        ),
                        title: Text(entry.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${entry.address}'),
                        onTap: () => _jumpTo(entry),
                      ),
                  ],
                ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<PreviewSourceKind>(
                  segments: const [
                    ButtonSegment(value: PreviewSourceKind.markdown, label: Text('Markdown')),
                    ButtonSegment(value: PreviewSourceKind.html, label: Text('HTML')),
                  ],
                  selected: <PreviewSourceKind>{_kind},
                  onSelectionChanged: (Set<PreviewSourceKind> value) {
                    final PreviewSourceKind next = value.first;
                    if (next == _kind) {
                      return;
                    }
                    // 离开这份文档：把读到的位置定格下来，切回来时落回这里。
                    final PreviewPosition? here = _live[_kind];
                    setState(() {
                      if (here != null) {
                        _bookmark[_kind] = here;
                      }
                      // 档位立刻跟手：新载荷要等 render 回来，选中态不该跟着等。
                      _kind = next;
                      _outline = PreviewOutline.empty;
                    });
                    // 新文档落回它自己上次离开的地方（没读过就是开头）。
                    _render();
                  },
                ),
                SegmentedButton<int>(
                  segments: [
                    for (int i = 0; i < _themes.length; i++)
                      ButtonSegment(value: i, label: Text(_themes[i].$1)),
                  ],
                  selected: <int>{_themeIndex},
                  onSelectionChanged: (Set<int> value) {
                    setState(() => _themeIndex = value.first);
                    _render();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            // 两个值并排摆：读者滚来滚去只会让上面那行变，下面那行只在离开时定格。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 只订阅那行字：位置回执每滚停一次就来一条，没必要重建整页。
                ValueListenableBuilder<String>(
                  valueListenable: _status,
                  builder: (BuildContext context, String status, Widget? _) => Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Last position: ${_bookmark[_kind] ?? 'none (never left)'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final WebViewController? controller = _controller;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }
    // windows / linux：官方 webview_flutter 没有实现。库本身与平台无关，
    // 这里只把「拿到的载荷」摆出来，接口形状与前三个平台完全一样。
    //
    // 只摆开头：文档里有公式或 mermaid 时载荷是 4 MB 上下（Mermaid 一家就 3.5 MB），
    // 整份塞进一个 Text 要一次布局几百万字符 —— 那两平台上会直接卡死。
    final String shown = _payload.length <= _maxPreviewChars
        ? _payload
        : '${_payload.substring(0, _maxPreviewChars)}\n'
            '… (${_payload.length} chars total)';
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'No official WebView implementation on this platform — below is what\n'
            'HyperlensPage.render() produced. Wire your own WebView for the same\n'
            'result as on android / ios / macos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            shown,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 语法树弹层：节点按层级摊平，一行一个。
///
/// 绑的是 [ValueNotifier]：点开弹层时才发出的「要完整树」命令，回执往往在弹层
/// 已经建好之后才到 —— 用 [ValueListenableBuilder] 才能就地刷新。
class _SyntaxSheet extends StatelessWidget {
  const _SyntaxSheet({required this.syntax});

  final ValueNotifier<PreviewSyntaxTree?> syntax;

  /// 一次最多列这么多行：完整树可以有几千个节点，弹层不是给「逐条读完」用的。
  static const int _maxRows = 300;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<PreviewSyntaxTree?>(
      valueListenable: syntax,
      builder: (BuildContext context, PreviewSyntaxTree? tree, Widget? _) {
        final List<(int, PreviewSyntaxNode)> rows =
            _flatten(tree?.nodes ?? const <PreviewSyntaxNode>[]);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tree == null
                      ? "No syntax tree yet: it arrives with the page's ast receipt"
                      : '${tree.kind.wireName}: ${tree.count} nodes'
                          '${tree.truncated ? ' (truncated)' : ''}'
                          '${tree.issues.isEmpty ? '' : ', ${tree.issues.length} issue${tree.issues.length == 1 ? '' : 's'}'}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'The first one is the skeleton; this is the full tree pulled by '
                  'HyperlensCommands.requestSyntaxAst().',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No nodes')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length > _maxRows ? _maxRows : rows.length,
                          itemBuilder: (BuildContext context, int index) {
                            final (int depth, PreviewSyntaxNode node) = rows[index];
                            return _row(theme, depth, node);
                          },
                        ),
                ),
                if (rows.length > _maxRows)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      // 行数不写「of N」：摊平有上限（见 _flatten），那个 N 是截断后的
                      // 行数，说成总数会让人以为树被吃掉了 —— 真值在标题的节点数里。
                      '(showing first $_maxRows rows — the tree has ${tree?.count ?? 0} nodes)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 一行一个节点：地址在前（等宽、次要色），文本在后。
  ///
  /// 两段塞进**同一个** `Text` 而不是 Row 的两个子项：地址一栏在 HTML 里是
  /// `body>math>:nth(1)>mfrac>:nth(1)>…` 这种长 DOM 路径，占固定比例会把文本栏压窄，
  /// 不占比例又会直接撑破整行（就是那条黄黑条纹）。合成一段后省略发生在行尾，
  /// 短地址也不会白占宽度。
  Widget _row(ThemeData theme, int depth, PreviewSyntaxNode node) {
    final String where = node.line == null
        ? (node.path ?? '')
        : (node.endLine == null || node.endLine == node.line
            ? 'L${node.line}'
            : 'L${node.line}-${node.endLine}');
    final String label = <String>[
      node.type,
      if (node.level > 0) 'h${node.level}',
      if (node.lang != null) node.lang!,
      if (where.isNotEmpty) _tail(where),
    ].join('  ');
    final TextStyle? body = theme.textTheme.bodySmall;
    return Padding(
      // 缩进按层数无限长的话，MathML 那种十几层嵌套会让整行没有可用宽度。
      padding: EdgeInsets.only(
        left: (depth > _maxIndent ? _maxIndent : depth) * 10.0,
        top: 1,
        bottom: 1,
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: body?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: node.text, style: body),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 最多缩进这么多层：再深的嵌套靠「地址里的路径」表达，不靠空白。
  static const int _maxIndent = 8;

  /// 长地址只留尾巴（`…>mrow:nth(1)>mi:nth(1)`）。
  ///
  /// HTML 的地址是 DOM 路径，深层节点前半段几十行完全一样；原样显示会把这一行的
  /// 节点文本挤成省略号 —— 树的意义正好丢在最深的那几层。Markdown 的 `L42` 够短，
  /// 原样返回。
  static String _tail(String address) {
    // 放得下就原样（`body>svg:nth(1)>line:nth(1)` 这类浅层地址不该被动），
    // 放不下才收到尾巴，把宽度留给节点文本。
    const int full = 28;
    const int keep = 20;
    if (address.length <= full) {
      return address;
    }
    String tail = address.substring(address.length - keep);
    // 从中间截会切在 `>` 上：往后挪到下一段开头，别留半截标签名。
    final int cut = tail.indexOf('>');
    if (cut >= 0 && cut + 1 < tail.length) {
      tail = tail.substring(cut + 1);
    }
    return '…>$tail';
  }

  /// 深度优先摊平：(层级, 节点)。
  static List<(int, PreviewSyntaxNode)> _flatten(
    List<PreviewSyntaxNode> nodes, [
    int depth = 0,
  ]) {
    final List<(int, PreviewSyntaxNode)> out = <(int, PreviewSyntaxNode)>[];
    for (final PreviewSyntaxNode node in nodes) {
      out.add((depth, node));
      if (node.children.isNotEmpty) {
        // 超过 _maxRows 就不再往下走：完整树可能有几千个节点，摊完只为显示 300 行不值。
        if (out.length >= _maxRows * 4) {
          return out;
        }
        out.addAll(_flatten(node.children, depth + 1));
      }
    }
    return out;
  }
}
