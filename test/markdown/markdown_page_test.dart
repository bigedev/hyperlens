import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/hyperlens.dart';

/// 渲染入口（`MarkdownPage`）要钉住三件事：
/// - 通道名是**注入**进模板的（使用方能改成自己的名字，非法名字要当场拒绝）；
/// - 主题决定取哪套 CSS（深色 / 墨水屏覆盖层）；
/// - 增强资产缺失时降级，正文照常，只有日志里多一句。
void main() {
  const String template = '<html><body>'
      '<script>window.__HYPERLENS_CHANNEL__.postMessage(1)</script>'
      '<script>/*__PAYLOAD__*/</script>'
      '</body></html>';

  MarkdownPage page({
    String markdown = '# 标题',
    String channelName = HyperlensBridge.channelName,
    HyperlensTheme theme = HyperlensTheme.light,
  }) =>
      MarkdownPage(
        markdown: markdown,
        token: 'doc-1:v1',
        theme: theme,
        restore: PreviewAnchor.top,
        channelName: channelName,
      );

  group('通道名注入', () {
    test('默认名替换掉占位符，模板里不再留下它', () async {
      final _FakeAssets assets = _FakeAssets(template);
      final String html = await page().render(assets: assets);

      expect(html.contains('window.${HyperlensBridge.channelName}.postMessage'),
          isTrue);
      expect(html.contains('__HYPERLENS_CHANNEL__'), isFalse);
    });

    test('使用方可以换成自己的通道名', () async {
      final String html = await page(channelName: 'MyHostChannel')
          .render(assets: _FakeAssets(template));

      expect(html.contains('window.MyHostChannel.postMessage'), isTrue);
      expect(html.contains(HyperlensBridge.channelName), isFalse);
    });

    test('非法名字（拼进 window.<name> 会语法错）当场拒绝', () async {
      expect(
        () => page(channelName: 'bad name').render(assets: _FakeAssets(template)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('主题', () {
    test('深色档取 dark 那套 CSS', () async {
      final _FakeAssets assets = _FakeAssets(template);
      await page(theme: HyperlensTheme.dark).render(assets: assets);

      expect(assets.loaded, contains(HyperlensAssets.mdDarkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdInkCss)));
    });

    test('墨水屏档：浅色表打底，再叠 ink 覆盖层', () async {
      final _FakeAssets assets = _FakeAssets(template);
      await page(theme: HyperlensTheme.ink).render(assets: assets);

      expect(assets.loaded, contains(HyperlensAssets.mdLightCss));
      expect(assets.loaded, contains(HyperlensAssets.mdInkCss));
      expect(assets.loaded, isNot(contains(HyperlensAssets.mdDarkCss)));
      expect(assets.loaded, contains(HyperlensAssets.hljsInkCss));
    });
  });

  group('载荷', () {
    test('凭据与「从头」位置都进了页面', () async {
      final String html = await page().render(assets: _FakeAssets(template));

      expect(html.contains('"token":"doc-1:v1"'), isTrue);
      expect(html.contains('"restore"'), isTrue);
    });
  });

  group('增强资产缺失', () {
    test('公式库读不到：不抛，正文照常，日志里记一句', () async {
      final _FakeAssets assets = _FakeAssets(
        template,
        missing: <String>{HyperlensAssets.katexJs},
      );
      final _RecordingLogger logger = _RecordingLogger();

      final String html = await page(markdown: '公式：\$\$E=mc^2\$\$')
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
