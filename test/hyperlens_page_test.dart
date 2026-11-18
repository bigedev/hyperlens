import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/hyperlens.dart';

/// 渲染入口（`HyperlensPage`）：**一份文档进来，一份载荷出去**。
///
/// 要钉住的是「两种文档在这一个入口上概念一致」：
/// - 类型判定只认路径后缀 / 显式 kind，**不猜内容**；
/// - 通道名是注入的（能改成自己的名字，非法名字当场拒绝）；
/// - 主题在两边的含义相同（Markdown 取哪套 CSS，HTML 换算成 zoom + 覆盖层）；
/// - HTML 侧的顺序由入口保证：先摘作者脚本 → 再判可见 → 再注样式 → 再注脚本；
/// - 命中优先于还原：有焦点时不再落位，否则两者抢滚动条。
void main() {
  const String template = '<html><body>'
      '<script>window.__HYPERLENS_CHANNEL__.postMessage(1)</script>'
      '<script>/*__PAYLOAD__*/</script>'
      '</body></html>';

  HyperlensPage markdownPage({
    String markdown = '# 标题',
    String path = 'docs/a.md',
    String token = 'doc-1:v1',
    String channelName = HyperlensBridge.channelName,
    HyperlensTheme theme = HyperlensTheme.light,
  }) =>
      HyperlensPage.fromText(
        source: markdown,
        path: path,
        token: token,
        theme: theme,
        channelName: channelName,
      );

  group('文档类型判定', () {
    test('.md / .markdown 走 Markdown 分支', () {
      expect(
        HyperlensPage.fromText(source: 'x', path: 'a.md').kind,
        PreviewSourceKind.markdown,
      );
      expect(
        HyperlensPage.fromText(source: 'x', path: 'A.MARKDOWN').kind,
        PreviewSourceKind.markdown,
        reason: '后缀比较不分大小写',
      );
    });

    test('.html / .htm 走 HTML 分支，且不需要资产', () async {
      final HyperlensPage page =
          HyperlensPage.fromText(source: '<p>hi</p>', path: 'a.html');
      expect(page.kind, PreviewSourceKind.html);
      final String html = await page.render();
      expect(html, contains('<p>hi</p>'));
    });

    test('没有后缀就用显式 kind（不猜内容：`.txt` 里是 Markdown 也得说明）', () async {
      final HyperlensPage page = HyperlensPage.fromText(
        source: '# 标题',
        path: 'notes.txt',
        kind: PreviewSourceKind.markdown,
      );
      expect(page.kind, PreviewSourceKind.markdown);
      await expectLater(
        page.render(assets: _FakeAssets(template)),
        completes,
      );
    });

    test('判不出来直接拒绝，别把 Markdown 当 HTML 页渲染', () {
      expect(
        () => HyperlensPage.fromText(source: '# 标题', path: 'notes.txt'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => HyperlensPage.fromText(source: '# 标题'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('通道名注入（两种文档同一处校验）', () {
    test('默认名替换掉占位符，模板里不再留下它', () async {
      final _FakeAssets assets = _FakeAssets(template);
      final String html = await markdownPage().render(assets: assets);

      expect(html.contains('window.${HyperlensBridge.channelName}.postMessage'),
          isTrue);
      expect(html.contains('__HYPERLENS_CHANNEL__'), isFalse);
    });

    test('使用方可以换成自己的通道名', () async {
      final String html = await markdownPage(channelName: 'MyHostChannel')
          .render(assets: _FakeAssets(template));

      expect(html.contains('window.MyHostChannel.postMessage'), isTrue);
      expect(html.contains(HyperlensBridge.channelName), isFalse);
    });

    test('HTML 分支用同一个名字注入', () async {
      final String html = await HyperlensPage.fromText(
        source: '<p>hi</p>',
        path: 'a.html',
        channelName: 'MyHostChannel',
      ).render();

      expect(html.contains('window.MyHostChannel.postMessage'), isTrue);
      expect(html.contains('__HYPERLENS_CHANNEL__'), isFalse);
    });

    test('非法名字（拼进 window.<name> 会语法错）当场拒绝', () async {
      await expectLater(
        markdownPage(channelName: 'bad name')
            .render(assets: _FakeAssets(template)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        HyperlensPage.fromText(
          source: '<p>x</p>',
          path: 'a.html',
          channelName: '1bad',
        ).render(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('主题（Markdown 取 CSS，HTML 换算成 zoom）', () {
    test('深色档取 dark 那套 CSS', () async {
      final _FakeAssets assets = _FakeAssets(template);
      await markdownPage(theme: HyperlensTheme.dark).render(assets: assets);

      expect(assets.loaded, contains(HyperlensAssets.mdDarkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdInkCss)));
    });

    test('墨水屏默认态：浅色表打底，再叠单色覆盖层', () async {
      final _FakeAssets assets = _FakeAssets(template);
      await markdownPage(theme: HyperlensTheme.ink).render(assets: assets);

      expect(assets.loaded, contains(HyperlensAssets.mdLightCss));
      expect(assets.loaded, contains(HyperlensAssets.mdInkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdDarkCss)));
      expect(assets.loaded, contains(HyperlensAssets.hljsInkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdInkDarkCss)));
    });

    test('墨水屏深色：dark 表打底，叠的是反白版覆盖层', () async {
      final _FakeAssets assets = _FakeAssets(template);
      await markdownPage(theme: HyperlensTheme.inkDark).render(assets: assets);

      expect(assets.loaded, contains(HyperlensAssets.mdDarkCss));
      expect(assets.loaded, contains(HyperlensAssets.mdInkDarkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdInkCss)));
      expect(assets.loaded, contains(HyperlensAssets.hljsInkDarkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.hljsInkCss)));
    });

    test('HTML：底色 / zoom / color-scheme 都进样式，作者底色声明决定是否接管字色', () async {
      final String plain = await HyperlensPage.fromText(
        source: '<p>hi</p>',
        path: 'a.html',
        theme: HyperlensTheme.dark,
      ).render();
      expect(plain, contains('html,body{background-color:'));
      expect(plain, contains(':root{color-scheme:dark !important;}'));
      expect(plain, contains('body{zoom:'));

      final String own = await HyperlensPage.fromText(
        source: '<style>html{background:#fff}</style><p>hi</p>',
        path: 'a.html',
        theme: HyperlensTheme.dark,
      ).render();
      expect(own, contains('color:'), reason: '作者定了底色，字色得接管');
    });
  });

  group('载荷（Markdown）', () {
    test('凭据与「从头」位置都进了页面', () async {
      final String html = await markdownPage().render(assets: _FakeAssets(template));

      expect(html.contains('"token":"doc-1:v1"'), isTrue);
      expect(html.contains('"restore"'), isTrue);
    });

    test('不给 assets：说清为什么（HTML 才不需要资产）', () async {
      await expectLater(
        markdownPage().render(),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('assets'),
          ),
        ),
      );
    });

    test('凭据含空格也被拒绝（信封按空格切，凭据脏了整条回执被丢）', () async {
      await expectLater(
        markdownPage(token: 'doc 1').render(assets: _FakeAssets(template)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('HTML 分支的顺序与脚本', () {
    test('作者脚本先摘掉，再注入我们的样式与脚本', () async {
      final String html = await HyperlensPage.fromText(
        source: '<body onload="evil()"><script>evil()</script><p>hi</p>'
            '<a href="other.md">链接</a></body>',
        path: 'a.html',
      ).render();

      expect(html, isNot(contains('evil()')));
      expect(html, contains('hyperLensAnchorPost'));
      expect(html, contains('hyperLensAnchorWatchLinks'));
      expect(html, contains('hyperLensAnchorRenderReady'));
    });

    test('自有页面（ownPage）不摘脚本：那通常就是调用方自己的桥', () async {
      final String html = await HyperlensPage.fromText(
        source: '<script>window.myBridge = 1;</script><p>hi</p>',
        path: 'a.html',
        ownPage: true,
      ).render();

      expect(html, contains('window.myBridge = 1;'));
    });

    test('scripts: false → 只留内容，不注样式与脚本', () async {
      final String html = await HyperlensPage.fromText(
        source: '<p>hi</p>',
        path: 'a.html',
        scripts: false,
      ).render();

      expect(html, contains('<p>hi</p>'));
      expect(html, isNot(contains('hyperLensAnchorPost')));
      expect(html, isNot(contains('body{zoom:')));
    });

    test('有命中时不再落位（否则和命中抢滚动条），且命中脚本排在后面', () async {
      final String html = await HyperlensPage.fromText(
        source: '<p>目标 关键词 结尾</p>',
        path: 'a.html',
        focus: const PreviewFocus(needle: '关键词', occurrence: 0),
      ).render();

      expect(
        html,
        isNot(contains('hyperLensAnchorHold({')),
        reason: '落位调用不能出现，函数定义不算',
      );
      final int focusAt = html.indexOf('hyperLensApplyFocus(');
      final int anchorAt = html.indexOf('hyperLensAnchorPost');
      expect(focusAt, greaterThan(anchorAt), reason: '先摆好页面，再滚到命中处');
    });

    test('没有命中时显式落回 body（不继承上一篇的滚动位置）', () async {
      final String html = await HyperlensPage.fromText(
        source: '<p>hi</p>',
        path: 'a.html',
      ).render();

      expect(html, contains('hyperLensAnchorHold({"path":"body"})'));
    });
  });

  group('blankWithoutScripts（脚本不跑时还剩不剩内容）', () {
    test('HTML 里只有脚本：提醒调用方这页会白', () {
      final HyperlensPage page = HyperlensPage.fromText(
        source: '<html><body><script>document.write("hi")</script></body></html>',
        path: 'a.html',
      );
      expect(page.blankWithoutScripts, isTrue);
    });

    test('有正文：不白', () {
      final HyperlensPage page = HyperlensPage.fromText(
        source: '<p>hi</p>',
        path: 'a.html',
      );
      expect(page.blankWithoutScripts, isFalse);
    });

    test('Markdown 恒 false（那边永远有模板在渲染）', () {
      expect(markdownPage().blankWithoutScripts, isFalse);
    });
  });

  group('增强资产缺失（Markdown）', () {
    test('公式库读不到：不抛，正文照常，日志里记一句', () async {
      final _FakeAssets assets = _FakeAssets(
        template,
        missing: <String>{HyperlensAssets.katexJs},
      );
      final _RecordingLogger logger = _RecordingLogger();

      final String html = await markdownPage(markdown: '公式：\$\$E=mc^2\$\$')
          .render(assets: assets, logger: logger);

      expect(html.contains('E=mc^2'), isTrue, reason: '正文仍在');
      expect(logger.warnings, isNotEmpty);
      expect(logger.warnings.first, contains(HyperlensAssets.katexJs));
    });
  });
}

class _FakeAssets implements HyperlensAssetLoader {
  _FakeAssets(this.template, {this.missing = const <String>{}});

  final String template;
  final Set<String> missing;
  final List<String> loaded = <String>[];

  @override
  Future<String> loadString(String path) async {
    loaded.add(path);
    if (missing.contains(path)) {
      throw HyperlensAssetException(path);
    }
    return switch (path) {
      HyperlensAssets.markdownViewHtml => template,
      _ => 'X',
    };
  }
}

class _RecordingLogger implements HyperlensLogger {
  final List<String> warnings = <String>[];

  @override
  void warn(String tag, String message) => warnings.add('$tag: $message');

  @override
  void error(String tag, String message, [Object? cause]) {}
}
