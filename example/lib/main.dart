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
/// 6. **链接**：包判「什么算链接、什么算离开文档」（`isExternalPreviewLink`），
///    回执带地址空间（`space` / `context`，HTML 档由 `linkSpace:` / `linkContext:`
///    注入）；解析在宿主 —— 示例把「同文件 + `#片段`」落成
///    `PreviewDomAddress('#片段')`，跨文件只演示到「拿到路径」。
///
/// 这六步全在本文件里，其余都是外壳 —— 示例只有一屏，代码按职责分开：
///
/// | 文件 | 干什么 |
/// | --- | --- |
/// | `main.dart`（本文件） | 入口 + 渲染流水线：提交、回执分发、位置语义 |
/// | `src/demo_documents.dart` | 两份演示文档（Markdown / HTML） |
/// | `src/preview_toolbar.dart` | 文档档位、主题档位 |
/// | `src/outline_drawer.dart` | 目录抽屉 |
/// | `src/status_bar.dart` | 页脚两行（此刻在哪 / 上次读到哪） |
/// | `src/syntax_sheet.dart` | 语法树弹层 |
/// | `src/platform_fallback.dart` | 平台判定 + 无 WebView 平台的载荷视图 |
///
/// 宿主自己负责的部分这里都留着：WebView 生命周期、页面外壳、目录 UI —— 包不碰 UI。
///
/// 平台：官方的 `webview_flutter` 只实现 android / ios / macos。windows / linux 上
/// 本示例照常编译运行，只是把载荷以源码形式展示 —— 库本身是纯 Dart，与平台无关，
/// 那两平台接自己的 WebView 即可（其余代码不用改）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';
import 'package:hyperlens/root_bundle.dart';
// 唯一 import flutter 的入口：rootBundle 版资产读取。纯 Dart 场景自己实现
// HyperlensAssetLoader 即可，主入口 hyperlens.dart 不依赖 flutter。
import 'package:webview_flutter/webview_flutter.dart';

import 'src/demo_documents.dart';
import 'src/outline_drawer.dart';
import 'src/platform_fallback.dart';
import 'src/preview_toolbar.dart';
import 'src/status_bar.dart';
import 'src/syntax_sheet.dart';

void main() => runApp(const _DemoApp());

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

/// 渲染流水线本体：一次 [_render] 就是一次提交，回执在 [_onMessage] 分发。
class _DemoPageState extends State<_DemoPage> {
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
  final ValueNotifier<String> _status =
      ValueNotifier<String>('Ready to render…');

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
  final ValueNotifier<PreviewSyntaxTree?> _syntax =
      ValueNotifier<PreviewSyntaxTree?>(null);

  @override
  void dispose() {
    _status.dispose();
    _syntax.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (hasWebViewPlatform) {
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
      source: demoDocument(_kind),
      kind: _kind,
      theme: demoThemes[_themeIndex].theme,
      // 落位：Markdown 用源码行、HTML 用 DOM 路径，各记各的。
      restore: target,
      // 凭据：页面会把它带回来，用来丢掉上一页的迟到回执（见 _fromLivePage）。
      token: token,
      channelName: HyperlensBridge.channelName,
      // 链接的地址空间：HTML 档告诉页面「你属于仓库里的 demo.html」，回执里就会带
      // 上 `repo` 与这个路径 —— 换文档之后上一页的迟到点击按它丢掉。
      // Markdown 模板发的是旧式信封（只有 href），这里**故意不传**：两种都认。
      linkSpace: markdown ? null : PreviewLinkSpace.repo,
      linkContext: markdown ? null : 'demo.html',
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
        '${markdown ? 'Markdown' : 'HTML'} / ${demoThemes[_themeIndex].label}'
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

  /// 换文档：离开这份之前先定格，切回来时落回这里。
  void _switchKind(PreviewSourceKind next) {
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
  }

  /// 换主题：重画文档，落回此刻的位置（换主题不该把人扔回开头）。
  void _switchTheme(int index) {
    setState(() => _themeIndex = index);
    _render();
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

  /// 点了一条链接：**判定归包，解析归宿主**。
  ///
  /// [isExternalPreviewLink] 只看协议头（`http` / `https` / `mailto` / `tel`）；
  /// 其余的 href 是文档内（或仓库内）相对地址，怎么解析是宿主的事。示例只有一份
  /// 文档，所以「跨文件」只演示到「拿到路径 + 片段」为止；能真落位的是
  /// 「同一份文档 + `#片段`」—— 走目录同一条命令，只是地址换成
  /// `PreviewDomAddress('#片段')`，页面按 id 取节点。
  void _openLink(String href, {PreviewLinkSpace? space, String? context}) {
    // 回执里的地址空间：只有渲染时设置过 `linkSpace` 的页面才带（旧式信封是 null）。
    final String from =
        space == null ? 'no space' : '${space.wireName} / ${context ?? '-'}';
    if (isExternalPreviewLink(href)) {
      _status.value = 'External link from $from: $href';
      _toast('Handed to the system browser: $href');
      return;
    }
    final Uri? uri = Uri.tryParse(href);
    final String path = uri?.path ?? '';
    // `Uri.fragment` 已经解过码：`#sec%202` 就是 `sec 2`。
    final String? fragment =
        (uri != null && uri.fragment.isNotEmpty) ? uri.fragment : null;
    // 真实宿主会按「当前文件所在目录」把相对路径解析成仓库路径，再交给文件视图；
    // 示例只有一份文档，`demo.html` 这类同文件目标直接认。
    final bool sameDocument = path.isEmpty || path == (context ?? '');
    if (fragment != null && sameDocument) {
      unawaited(_scrollToFragment(fragment, from));
      return;
    }
    final String target = path.isEmpty ? href : path;
    _status.value = 'Link from $from: $target'
        '${fragment == null ? '' : ' #$fragment'}';
    _toast(
      'Host would open $target'
      '${fragment == null ? '' : ' and land on #$fragment'}',
    );
  }

  /// 落到本页的 `#片段`：与目录跳转同一条命令，只是地址换成 id。
  Future<void> _scrollToFragment(String fragment, String from) async {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    // 与目录跳转同口径：这次离开阅读处，回来时落回这里。
    final PreviewPosition? here = _live[_kind];
    if (here != null) {
      setState(() => _bookmark[_kind] = here);
    }
    // 这次滚动由链接带来，不是读者自己滚的：别让它变成「上次位置」。
    _markProgrammatic(800);
    await controller.runJavaScript(
      HyperlensCommands.forPosition(PreviewDomAddress('#$fragment')),
    );
    if (mounted) {
      _status.value = 'Link landed on #$fragment ($from)';
      // 状态栏随即会被页面自己的位置回执盖掉（落位也是一次滚动）：地址空间放
      // SnackBar 里，演示时看得见「这条链接从哪个地址空间来」。
      _toast('Link from $from → #$fragment');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

      // 链接：判定归包（外链协议表），解析归宿主。`space` / `context` 是这一页的
      // 地址空间 —— 只有设置了 `linkSpace` 的页面才会带，旧式信封里是 null。
      case PreviewLinkTapped(
          :final String href,
          :final PreviewLinkSpace? space,
          :final String? context,
        ):
        _openLink(href, space: space, context: context);

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
      builder: (BuildContext context) => SyntaxSheet(syntax: _syntax),
    );
  }

  /// 正文区：有 WebView 就显示页面，没有就把载荷摆出来。
  Widget _view() {
    final WebViewController? controller = _controller;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }
    return PayloadFallbackView(payload: _payload);
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
      endDrawer: OutlineDrawer(outline: _outline, onTap: _jumpTo),
      body: Column(
        children: [
          PreviewToolbar(
            kind: _kind,
            themeIndex: _themeIndex,
            onKindChanged: _switchKind,
            onThemeChanged: _switchTheme,
          ),
          Expanded(child: _view()),
          // 两个值并排摆：读者滚来滚去只会让上面那行变，下面那行只在离开时定格。
          PreviewStatusBar(status: _status, bookmark: _bookmark[_kind]),
        ],
      ),
    );
  }
}
