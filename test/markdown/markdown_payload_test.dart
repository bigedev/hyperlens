import 'dart:convert';
import 'dart:io';

import 'package:hyperlens/src/asset/hyperlens_assets.dart';
import 'package:hyperlens/src/markdown/escape.dart';
import 'package:hyperlens/src/markdown/payload.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染载荷与模板替换（`lib/src/markdown/payload.dart`）。
///
/// 两条硬约束都出过真机问题：
/// 1. 正文里的 `<` 必须转义成 `\u003c`，否则内联进 `<script>` 会被当成标签，
///    页面直接白（而且框架异常不进 hilog，看着只是「预览坏了」）；
/// 2. 只有**底色**占位符是 `replaceAll`（它出现两处），其余必须是 `replaceFirst` ——
///    否则文档里恰好写着 `/*__PAYLOAD__*/` 的代码块会被一起换掉。
void main() {
  group('buildMarkdownPayload', () {
    test('键齐全，位置按 toJson 带出去（只有 line，没有块号 / 像素）', () {
      final String payload = buildMarkdownPayload(
        markdown: '# 标题',
        dark: true,
        fontSize: 18,
        token: '5:abc',
        restore: const SourceAddress(9),
      );
      final Map<String, Object?> json =
          jsonDecode(payload.replaceAll(r'\u003c', '<')) as Map<String, Object?>;

      expect(json['markdown'], '# 标题');
      expect(json['dark'], isTrue);
      expect(json['fontSize'], 18);
      expect(json['token'], '5:abc');
      expect(json['restore'], <String, Object?>{'line': 9});
    });

    test('正文里的 < 全部转义（内联进 script 才不会被当标签）', () {
      final String payload = buildMarkdownPayload(
        markdown: '<div onclick="x">a</div>',
        dark: false,
        fontSize: 16,
        token: '1:1',
        restore: PreviewPosition.top,
      );

      expect(payload.contains('<'), isFalse);
      expect(payload.contains(r'\u003c'), isTrue);
    });
  });

  group('buildMarkdownHtml', () {
    const String template = '<style>/*__MD_BACKGROUND__*/</style>'
        '<style>color: /*__MD_FOREGROUND__*/; '
        '--md-border-default: /*__MD_BORDER__*/;</style>'
        '<style>/*__MD_THEME_CSS__*/</style>'
        '<style>/*__HLJS_THEME_CSS__*/</style>'
        '<style>/*__KATEX_CSS__*/</style>'
        '<script>/*__DOMPURIFY_JS__*/</script>'
        '<script>/*__MARKED_JS__*/</script>'
        '<script>/*__HLJS_JS__*/</script>'
        '<script>/*__HLJS_DART_JS__*/</script>'
        '<script>/*__KATEX_JS__*/</script>'
        '<script>/*__MHCHEM_JS__*/</script>'
        '<script>/*__MERMAID_JS__*/</script>'
        '<script>var payload = /*__PAYLOAD__*/;</script>'
        '<body style="background: /*__MD_BACKGROUND__*/"></body>';

    Future<String> fakeLoad(String path) async => switch (path) {
          HyperlensAssets.markdownViewHtml => template,
          HyperlensAssets.mdDarkCss => 'DARK-THEME',
          HyperlensAssets.mdLightCss => 'LIGHT-THEME',
          HyperlensAssets.hljsDarkCss => 'DARK-HLJS',
          HyperlensAssets.hljsLightCss => 'LIGHT-HLJS',
          HyperlensAssets.mdInkCss => 'INK-THEME',
          HyperlensAssets.hljsInkCss => 'INK-HLJS',
          HyperlensAssets.markedJs => 'MARKED',
          HyperlensAssets.purifyJs => 'PURIFY',
          HyperlensAssets.highlightJs => 'HLJS',
          HyperlensAssets.highlightDartJs => 'HLJS-DART',
          HyperlensAssets.katexCss => 'KATEX-CSS',
          HyperlensAssets.katexJs => 'KATEX-JS',
          HyperlensAssets.mhchemJs => 'MHCHEM-JS',
          HyperlensAssets.mermaidJs => 'MERMAID-JS',
          _ => throw StateError('没这个资源：$path'),
        };

    test('深色：两处底色都换掉，主题与高亮取深色那套', () async {
      final String html = await buildMarkdownHtml(
        load: fakeLoad,
        dark: true,
        background: '#121212',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{"a":1}',
        markdown: '# 标题',
      );

      expect('#121212'.allMatches(html).length, 2);
      // 正文色 / 边框色各注入一处：图表原先取到的是浏览器默认黑，深底黑字看不清；
      // `--md-border-default` 原先根本没有定义，墨屏那条黑白判据从未生效
      expect(html.contains('color: #e6edf3;'), isTrue);
      expect(html.contains('--md-border-default: #d0d7de;'), isTrue);
      expect(html.contains('DARK-THEME'), isTrue);
      expect(html.contains('DARK-HLJS'), isTrue);
      expect(html.contains('LIGHT-THEME'), isFalse);
      expect(html.contains('MARKED'), isTrue);
      expect(html.contains('PURIFY'), isTrue, reason: '清洗器必须一起内联，缺了页面会拒绝渲染');
      expect(html.contains('HLJS-DART'), isTrue);
      expect(html.contains('{"a":1}'), isTrue);
      expect(html.contains('/*__'), isFalse);
    });

    test('浅色：取浅色那套', () async {
      final String html = await buildMarkdownHtml(
        load: fakeLoad,
        dark: false,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '# 标题',
      );

      expect(html.contains('LIGHT-THEME'), isTrue);
      expect(html.contains('LIGHT-HLJS'), isTrue);
      expect(html.contains('DARK-THEME'), isFalse);
    });

    test('墨水屏：浅色表打底，再叠一层黑白覆盖', () async {
      final String html = await buildMarkdownHtml(
        load: fakeLoad,
        dark: false,
        ink: true,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '# 标题',
      );

      // 布局规则仍来自 light，ink 只补颜色与分隔线，两层都要在
      expect(html.contains('LIGHT-THEME'), isTrue);
      expect(html.contains('INK-THEME'), isTrue);
      expect(html.contains('LIGHT-HLJS'), isTrue);
      expect(html.contains('INK-HLJS'), isTrue);
      expect(html.contains('DARK-THEME'), isFalse);
      // 覆盖层必须排在基础表之后，否则同权重规则会被 light 抢回去
      expect(
        html.indexOf('INK-THEME') > html.indexOf('LIGHT-THEME'),
        isTrue,
      );
    });

    test('只有底色是 replaceAll，其余占位符只换第一处', () async {
      const String twice = '/*__PAYLOAD__*/ 与 /*__PAYLOAD__*/';
      final String html = await buildMarkdownHtml(
        load: (String path) async =>
            path == HyperlensAssets.markdownViewHtml ? twice : 'X',
        dark: false,
        background: '#000000',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: 'P',
        markdown: '# 标题',
      );

      expect(html, 'P 与 /*__PAYLOAD__*/');
    });

    test('资源读不到就明确抛错（页面那边会 catch 成「读取资源失败」）',
        () async {
      await expectLater(
        buildMarkdownHtml(
          load: (String path) async => throw StateError('missing'),
          dark: false,
          background: '#fff',
          foreground: '#e6edf3',
          border: '#d0d7de',
          payload: '{}',
          markdown: '# 标题',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('不含公式：三处 KaTeX 占位按空串替换，且不去读那三份资产', () async {
      final List<String> loaded = <String>[];
      final String html = await buildMarkdownHtml(
        load: (String path) async {
          loaded.add(path);
          return fakeLoad(path);
        },
        dark: false,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '# 标题\n\n正文，没有公式。',
      );

      expect(loaded, isNot(contains(HyperlensAssets.katexCss)));
      expect(loaded, isNot(contains(HyperlensAssets.katexJs)));
      expect(loaded, isNot(contains(HyperlensAssets.mhchemJs)));
      expect(html.contains('KATEX'), isFalse);
      expect(html.contains('/*__'), isFalse, reason: '占位必须被换成空串，不能留在页面里');
    });

    test('含公式：KaTeX 与 mhchem 都内联，且 mhchem 排在 katex 之后', () async {
      final String html = await buildMarkdownHtml(
        load: fakeLoad,
        dark: false,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '质能方程 \$E=mc^2\$',
      );

      expect(html.contains('KATEX-CSS'), isTrue);
      expect(html.contains('KATEX-JS'), isTrue);
      expect(html.contains('MHCHEM-JS'), isTrue);
      expect(
        html.indexOf('KATEX-JS') < html.indexOf('MHCHEM-JS'),
        isTrue,
        reason: 'mhchem 是 UMD，运行时读全局 katex —— 顺序反了化学式会报未定义命令',
      );
      expect(html.contains('/*__'), isFalse);
    });

    // 这条读的是**真模板**，用来钉住 D7 的修复：marked 的输出必须先进 DOMPurify，
    // 不能直接落 innerHTML。把 sanitize 改回去，这里会红。
    test('真模板：marked 的输出先过 DOMPurify，且有 CSP 与白名单', () async {
      final String template =
          await File('assets/web/markdown_view.html').readAsString();

      expect(template.contains('window.DOMPurify.sanitize('), isTrue);
      expect(
        template.contains('host.innerHTML = window.marked.parse('),
        isFalse,
        reason: '直接把 marked 输出塞进 innerHTML 就是 D7 本体',
      );
      expect(template.contains('/*__DOMPURIFY_JS__*/'), isTrue);
      expect(template.contains('Content-Security-Policy'), isTrue);
      // class 必须留在白名单里：hljs 靠 language-* 识别语言
      final int attrsStart = template.indexOf('const PURIFY_ATTRS');
      expect(attrsStart, greaterThan(0), reason: '白名单要显式写出来，便于复核');
      expect(
        template.substring(attrsStart, template.indexOf('];', attrsStart)).contains("'class'"),
        isTrue,
      );
    });


    test('含 mermaid 围栏：只加载 Mermaid，不加载 KaTeX', () async {
      final List<String> loaded = <String>[];
      final String html = await buildMarkdownHtml(
        load: (String path) async {
          loaded.add(path);
          return fakeLoad(path);
        },
        dark: false,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '```mermaid\ngraph TD;\nA-->B;\n```\n',
      );

      expect(loaded, contains(HyperlensAssets.mermaidJs));
      expect(loaded, isNot(contains(HyperlensAssets.katexJs)));
      expect(html.contains('MERMAID-JS'), isTrue);
      expect(html.contains('KATEX-JS'), isFalse);
    });

    test('两种增强都没有：五处占位全按空串替换', () async {
      final List<String> loaded = <String>[];
      final String html = await buildMarkdownHtml(
        load: (String path) async {
          loaded.add(path);
          return fakeLoad(path);
        },
        dark: false,
        background: '#ffffff',
        foreground: '#e6edf3',
        border: '#d0d7de',
        payload: '{}',
        markdown: '# 标题',
      );

      expect(loaded, isNot(contains(HyperlensAssets.mermaidJs)));
      expect(loaded, isNot(contains(HyperlensAssets.katexJs)));
      expect(html.contains('MERMAID'), isFalse);
      expect(html.contains('KATEX'), isFalse);
      expect(html.contains('/*__'), isFalse);
    });

    // `\$` 在进页面之前必须换成占位字符：marked 会把它还原成裸 `$`，模板那边
    // 就分不清「要字面量」还是「要公式」（2026-11-17 真机走查发现）。
    test('载荷把转义美元符换成占位字符', () {
      final String payload = buildMarkdownPayload(
        markdown: r'转义写法 \$x\$ 应原样显示。',
        dark: false,
        fontSize: 16,
        token: 't1',
        restore: PreviewPosition.top,
      );
      expect(payload.contains(kEscapedDollarSentinel), isTrue);
      expect(payload.contains(r'\$'), isFalse, reason: '\$ 不能原样进页面');
    });

    test('真模板：转义占位在公式渲染之后才换回字面量', () async {
      final String template =
          await File('assets/web/markdown_view.html').readAsString();

      final int renderAt = template.indexOf('var mathCount = mdRenderMath(host);');
      final int restoreAt = template.indexOf('mdRestoreEscapedDollars(host);');
      expect(renderAt, greaterThan(0), reason: '公式渲染那一步不见了');
      expect(
        restoreAt,
        greaterThan(renderAt),
        reason: '先还原再加公式扫描 = 字面量又被当成定界符',
      );
    });
    // 钉住 2026-11-17 真机踩到的坑：扩展挂在 `marked.defaults` 上，lexer 自己另拼
    // 一份 options 就会把它们丢掉 —— 表现是「块级公式的 `$$` 原样露出来」，而行内公式
    // 走的是 DOM 扫描，照样正常，很容易误判成「扩展没注册」。
    test('真模板：lexer 的 options 以 marked.defaults 为底（否则扩展被丢掉）', () async {
      final String template =
          await File('assets/web/markdown_view.html').readAsString();

      expect(
        template.contains('Object.assign({}, window.marked.defaults'),
        isTrue,
        reason: '必须继承 defaults，extensions 才跟着进 lexer',
      );
      expect(
        template.contains('var markdownOptions = { breaks: true, gfm: true };'),
        isFalse,
        reason: '旧写法会丢掉 extensions：块级公式退化成裸文本',
      );
    });
    // 钉住 2026-11-17 验出来的坑：图内公式（`$$…$$`）是 foreignObject 里的 HTML，
    // 在 SVG 上下文里过 DOMPurify 会被整个移除（元素留下、内容清空 = 空框），
    // 只能把那段内容单独当 HTML 片段洗一遍再塞回。别把两步合回一步。
    test('真模板：图内公式的内容单独洗过再塞回 foreignObject', () async {
      final String template =
          await File('assets/web/markdown_view.html').readAsString();

      expect(
        template.contains('function mdPurifyMermaidSvg('),
        isTrue,
        reason: '图内公式依赖这个两次清洗的函数',
      );
      expect(
        template.contains("USE_PROFILES: { mathMl: true }"),
        isTrue,
        reason: 'foreignObject 里是 MathML，单独洗时走 mathMl profile',
      );
      expect(
        template.contains('fos2[i].innerHTML = kept[i];'),
        isTrue,
        reason: '洗完骨架要把存下来的内容按序塞回去',
      );
    });
    // 图里的公式定界符都要改写成 Mermaid 唯一认的双美元。判据必须走真 KaTeX 校验：
    // 只看正则会把 `A["价格 $5 到 $10"]` 也升级掉，而 Mermaid 那边不报错，
    // 静默排成一坨乱码 —— 比失败更难发现。
    //
    // 三条分支（`$…$` / `\[…\]` / `\(…\)`）的改写结果由设备侧用例
    // `integration_test/webview_preview_test.dart` 端到端验（回执里报「图内公式 N」），
    // 这里只钉「模板里确实有这三条、且都过同一道 KaTeX 校验」——主机上跑不了页面 JS。
    test('真模板：三种定界符升级，且都走 KaTeX 校验（strict:error）', () async {
      final String template =
          await File('assets/web/markdown_view.html').readAsString();

      expect(template.contains('function mdUpgradeMermaidMath('), isTrue);
      expect(
        template.contains("strict: 'error'"),
        isTrue,
        reason: '少了 strict 就识别不出「中文被当成公式」',
      );
      expect(
        template.contains('function mdKatexOk('),
        isTrue,
        reason: '三条分支要共用同一道校验，别各写一份 try/catch',
      );
      expect(
        template.contains(r'\\\['),
        isTrue,
        reason: r'图里的 \[…\]（正文的块级定界符）也要升级，否则图里露出一串反斜杠',
      );
      expect(
        template.contains(r'\\\('),
        isTrue,
        reason: r'图里的 \(…\)（正文的行内定界符）同理',
      );
      expect(
        template.contains("mdUpgradeMermaidMath(node.textContent"),
        isTrue,
        reason: '升级要作用在交给 mermaid 的源码上，不能只是定义',
      );
      expect(
        template.contains('getComputedStyle(host)'),
        isTrue,
        reason: '图表正文色要取 .markdown-body；取 document.body 会拿到浏览器默认黑',
      );
      expect(
        template.contains('[class*="section-edge-"]') &&
            template.contains('stroke: var(--md-border-default'),
        isTrue,
        reason: '思维导图连线由 cScale 派生，深色档会反相成黑线 —— 必须改吃宿主边框色',
      );
      expect(
        template.contains("themeVars['cScale' + c]") &&
            template.contains('svg .node-bkg'),
        isTrue,
        reason: '节点填充也走 cScale，深色档默认反相成纯黑 —— 必须给满 12 档并描边',
      );
    });
  });
}
