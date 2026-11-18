import 'package:hyperlens/src/markdown/bridge.dart';
import 'package:hyperlens/src/model/preview_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 页面 → Dart 的回执格式（`lib/src/markdown/bridge.dart`）。
///
/// 这一层只做「字符串长什么样 → 是哪一类事件」，不碰会话与 WebView。格式错一格的
/// 后果都很具体：`top` 认不出来 = 返回时落回顶部；`link` 解码错 = 点了没反应；
/// 把认不出的消息当成 `render` = 看门狗被旧页面拆掉、白屏再没人重试。
void main() {
  group('render', () {
    test('拆出凭据与结果，结果里的空格原样保留', () {
      final MarkdownBridgeEvent event =
          MarkdownBridgeEvent.parse('render 7:12345 ok（12 条）');
      expect(event, isA<RenderReceipt>());
      event as RenderReceipt;
      expect(event.token, '7:12345');
      expect(event.result, 'ok（12 条）');
    });

    test('缺空格（只有前缀）不猜，归到 Unknown', () {
      expect(MarkdownBridgeEvent.parse('render'), isA<Unknown>());
      expect(MarkdownBridgeEvent.parse('render '), isA<Unknown>());
    });
  });

  group('link', () {
    test('百分号转义会解码', () {
      final MarkdownBridgeEvent event =
          MarkdownBridgeEvent.parse('link %E6%96%87%E6%A1%A3%2Fa.md');
      event as LinkTap;
      expect(event.href, '文档/a.md');
    });

    test('转义非法时按原样交给上层（上层还会再判一次）', () {
      final MarkdownBridgeEvent event = MarkdownBridgeEvent.parse('link %zz');
      event as LinkTap;
      expect(event.href, '%zz');
    });
  });

  group('top（阅读位置）', () {
    test('解析出锚点', () {
      final MarkdownBridgeEvent event = MarkdownBridgeEvent.parse(
        'top 3:99 {"block":4,"offset":12,"scrollY":960}',
      );
      event as PositionReport;
      expect(event.token, '3:99');
      expect(event.anchor, const PreviewAnchor(block: 4, offset: 12, scrollY: 960));
    });

    test('JSON 坏了：仍然认出是位置回执，但锚点为 null（丢弃，别当成顶部）', () {
      final MarkdownBridgeEvent event =
          MarkdownBridgeEvent.parse('top 3:99 {oops}');
      event as PositionReport;
      expect(event.token, '3:99');
      expect(event.anchor, isNull);
    });

    test('缺空格归到 Unknown', () {
      expect(MarkdownBridgeEvent.parse('top 3:99'), isA<Unknown>());
    });
  });

  group('outline（章节清单）', () {
    test('解析出条目', () {
      final MarkdownBridgeEvent event = MarkdownBridgeEvent.parse(
        'outline 1:2 [{"level":2,"text":"安装","block":1}]',
      );
      event as OutlineReport;
      expect(event.token, '1:2');
      expect(event.outline.length, 1);
      expect(event.outline.entries.single.text, '安装');
      expect(event.outline.entries.single.block, 1);
    });

    test('清单 JSON 坏了给空清单（目录空着，总比显示上一篇强）', () {
      final MarkdownBridgeEvent event =
          MarkdownBridgeEvent.parse('outline 1:2 not-json');
      event as OutlineReport;
      expect(event.outline.isEmpty, isTrue);
    });
  });

  test('anchor：页内锚点已滚好，只带目标', () {
    final MarkdownBridgeEvent event = MarkdownBridgeEvent.parse('anchor 安装');
    event as AnchorScrolled;
    expect(event.target, '安装');
  });

  test('认不出的消息原样带出去（页面与 Dart 版本不同步时别炸）', () {
    final MarkdownBridgeEvent event = MarkdownBridgeEvent.parse('hello from page');
    event as Unknown;
    expect(event.raw, 'hello from page');
  });

  test('前缀必须带空格：`report` 之类不许被当成 `render`', () {
    expect(MarkdownBridgeEvent.parse('renderx 1:2 ok'), isA<Unknown>());
    expect(MarkdownBridgeEvent.parse('topology 1:2 {}'), isA<Unknown>());
  });
}
