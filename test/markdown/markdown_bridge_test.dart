import 'package:hyperlens/src/markdown/bridge.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:flutter_test/flutter_test.dart';

/// 页面 → Dart 的回执格式（`lib/src/markdown/bridge.dart`）。
///
/// 这一层只做「字符串长什么样 → 是哪一类事件」，不碰会话与 WebView。格式错一格的
/// 后果都很具体：`top` 认不出来 = 返回时落回顶部；`link` 解码错 = 点了没反应；
/// 把认不出的消息当成 `render` = 看门狗被旧页面拆掉、白屏再没人重试。
void main() {
  group('render', () {
    test('拆出凭据与结果，结果里的空格原样保留', () {
      final MarkdownEvent event =
          MarkdownEvent.parse('render 7:12345 ok（12 条）');
      expect(event, isA<RenderReady>());
      event as RenderReady;
      expect(event.token, '7:12345');
      expect(event.result, 'ok（12 条）');
    });

    test('缺空格（只有前缀）不猜，归到 UnknownMessage', () {
      expect(MarkdownEvent.parse('render'), isA<UnknownMessage>());
      expect(MarkdownEvent.parse('render '), isA<UnknownMessage>());
    });
  });

  group('link', () {
    test('百分号转义会解码', () {
      final MarkdownEvent event =
          MarkdownEvent.parse('link %E6%96%87%E6%A1%A3%2Fa.md');
      event as LinkTapped;
      expect(event.href, '文档/a.md');
    });

    test('转义非法时按原样交给上层（上层还会再判一次）', () {
      final MarkdownEvent event = MarkdownEvent.parse('link %zz');
      event as LinkTapped;
      expect(event.href, '%zz');
    });
  });

  group('top（阅读位置）', () {
    test('解析出地址与观测量', () {
      final MarkdownEvent event = MarkdownEvent.parse(
        'top 3:99 {"line":42,"bottomLine":70}',
      );
      event as PositionReported;
      expect(event.token, '3:99');
      expect(event.position, const SourceAddress(42));
      expect(
        event.viewport,
        const PreviewViewport(topLine: 42, bottomLine: 70),
      );
    });

    test('只有 line、没有 bottomLine：观测量按空算，地址照收', () {
      final MarkdownEvent event = MarkdownEvent.parse('top t {"line":7}');
      event as PositionReported;
      expect(event.position, const SourceAddress(7));
      expect(event.viewport.topLine, 7);
      expect(event.viewport.bottomLine, isNull);
    });

    test('JSON 坏了：仍然认出是位置回执，但地址为 null（丢弃，别当成顶部）', () {
      final MarkdownEvent event = MarkdownEvent.parse('top 3:99 {oops}');
      event as PositionReported;
      expect(event.token, '3:99');
      expect(event.position, isNull);
      expect(event.viewport, PreviewViewport.empty);
    });

    test('老回执只有块号 / 像素：地址为 null（一次性换算在 Dart 侧做不了，回顶部）', () {
      final MarkdownEvent event =
          MarkdownEvent.parse('top t {"block":4,"offset":12,"scrollY":960}');
      event as PositionReported;
      expect(event.position, isNull);
    });

    test('缺空格归到 UnknownMessage', () {
      expect(MarkdownEvent.parse('top 3:99'), isA<UnknownMessage>());
    });
  });

  group('outline（章节清单）', () {
    test('解析出条目', () {
      final MarkdownEvent event = MarkdownEvent.parse(
        'outline 1:2 [{"level":2,"text":"安装","line":8,"id":"安装"}]',
      );
      event as OutlineReported;
      expect(event.token, '1:2');
      expect(event.outline.length, 1);
      expect(event.outline.entries.single.text, '安装');
      expect(event.outline.entries.single.address, const SourceAddress(8));
    });

    test('清单 JSON 坏了给空清单（目录空着，总比显示上一篇强）', () {
      final MarkdownEvent event =
          MarkdownEvent.parse('outline 1:2 not-json');
      event as OutlineReported;
      expect(event.outline.isEmpty, isTrue);
    });
  });

  test('anchor：页内锚点已滚好，只带目标', () {
    final MarkdownEvent event = MarkdownEvent.parse('anchor 安装');
    event as AnchorScrolled;
    expect(event.target, '安装');
  });

  test('认不出的消息原样带出去（页面与 Dart 版本不同步时别炸）', () {
    final MarkdownEvent event = MarkdownEvent.parse('hello from page');
    event as UnknownMessage;
    expect(event.raw, 'hello from page');
  });

  test('前缀必须带空格：`report` 之类不许被当成 `render`', () {
    expect(MarkdownEvent.parse('renderx 1:2 ok'), isA<UnknownMessage>());
    expect(MarkdownEvent.parse('topology 1:2 {}'), isA<UnknownMessage>());
  });
}
