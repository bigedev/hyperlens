import 'package:hyperlens/src/model/html_outline.dart';
import 'package:hyperlens/src/model/markdown_outline.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:hyperlens/src/model/preview_syntax.dart';
import 'package:hyperlens/src/protocol/events.dart';
import 'package:hyperlens/src/protocol/hyperlens_bridge.dart';
import 'package:hyperlens/src/protocol/link_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// 页面 → Dart 的回执（`lib/src/protocol/events.dart`）。
///
/// **一条信封、一套拆法**，Markdown 与 HTML 共用：`<前缀><凭据> <载荷>`，无凭据时
/// 写 [HyperlensBridge.noToken]。这一层只做「字符串长什么样 → 是哪一类事件」，
/// 不碰会话与 WebView。
///
/// 格式错一格的后果都很具体：`top` 认不出来 = 返回时落回顶部；`link` 解码错 =
/// 点了没反应；把认不出的消息当成 `render` = 看门狗被旧页面拆掉、白屏再没人重试；
/// 而「HTML 的清单被 Markdown 的拆包规则切歪」这一条尤其安静 —— 它不报错，
/// 只是某个带空格的标题让整条回执变成一个垃圾凭据 + 空清单。
void main() {
  group('render', () {
    test('Markdown：拆出凭据与结果，结果里的空格原样保留', () {
      final PreviewEvent event = PreviewEvent.parse('render 7:12345 ok（12 条）');
      expect(event, isA<PreviewRenderReady>());
      event as PreviewRenderReady;
      expect(event.token, '7:12345');
      expect(event.result, 'ok（12 条）');
    });

    test('HTML：凭据位写 `-`，解析出来是 null（整页重载，没有迟到消息）', () {
      final PreviewEvent event =
          PreviewEvent.parse('render ${HyperlensBridge.noToken} ok（html）');
      event as PreviewRenderReady;
      expect(event.token, isNull);
      expect(event.result, 'ok（html）');
    });

    test('缺空格（只有前缀）不猜，归到 PreviewUnknownMessage', () {
      expect(PreviewEvent.parse('render'), isA<PreviewUnknownMessage>());
      expect(PreviewEvent.parse('render '), isA<PreviewUnknownMessage>());
    });
  });

  group('link', () {
    test('百分号转义会解码', () {
      final PreviewEvent event =
          PreviewEvent.parse('link %E6%96%87%E6%A1%A3%2Fa.md');
      event as PreviewLinkTapped;
      expect(event.href, '文档/a.md');
    });

    test('转义非法时按原样交给上层（上层还会再判一次）', () {
      final PreviewEvent event = PreviewEvent.parse('link %zz');
      event as PreviewLinkTapped;
      expect(event.href, '%zz');
    });

    test('旧式回执不带地址空间：space / context 都是 null', () {
      final PreviewEvent event = PreviewEvent.parse('link a%2Fb.md');
      event as PreviewLinkTapped;
      expect(event.space, isNull);
      expect(event.context, isNull);
    });

    test('带地址空间：space 还原、context 解码、href 里的 # 不被切掉', () {
      final PreviewEvent event = PreviewEvent.parse(
        'link repo docs%2Fchap2.html chap2.html%23sec2',
      );
      event as PreviewLinkTapped;
      expect(event.space, PreviewLinkSpace.repo);
      expect(event.context, 'docs/chap2.html');
      expect(event.href, 'chap2.html#sec2');
    });

    test('space 名不认识：按旧式整段解（页面与 Dart 版本不同步时别炸）', () {
      final PreviewEvent event = PreviewEvent.parse('link other a b');
      event as PreviewLinkTapped;
      expect(event.space, isNull);
      expect(event.href, 'other a b');
    });

    test('空 href 归到 PreviewUnknownMessage，别当成点了空链接', () {
      expect(
        PreviewEvent.parse('link repo docs%2Fa.md '),
        isA<PreviewUnknownMessage>(),
      );
      expect(PreviewEvent.parse('link '), isA<PreviewUnknownMessage>());
    });
  });

  group('top（阅读位置）', () {
    test('Markdown：地址 + 观测量', () {
      final PreviewEvent event = PreviewEvent.parse(
        'top 3:99 {"line":42,"bottomLine":70}',
      );
      event as PreviewPositionReported;
      expect(event.token, '3:99');
      expect(event.position, const PreviewSourceAddress(42));
      expect(
        event.viewport,
        const PreviewViewport(topLine: 42, bottomLine: 70),
      );
      expect(event.section, isNull, reason: 'Markdown 的当前节由调用方按大纲算');
    });

    test('HTML：同一条回执，地址是 DOM 路径，章节下标由页面给', () {
      final PreviewEvent event = PreviewEvent.parse(
        'top - {"path":"body>div#main>p:nth(3)","sec":3}',
      );
      event as PreviewPositionReported;
      expect(event.token, isNull);
      expect(event.position, const PreviewDomAddress('body>div#main>p:nth(3)'));
      expect(event.section, 3);
    });

    test('HTML：没带 sec → section 为 null（位置有、章节没有）', () {
      final PreviewEvent event = PreviewEvent.parse('top - {"path":"body"}');
      event as PreviewPositionReported;
      expect(event.position, PreviewDomAddress.body);
      expect(event.section, isNull);
    });

    test('只有 line、没有 bottomLine：观测量按空算，地址照收', () {
      final PreviewEvent event = PreviewEvent.parse('top t {"line":7}');
      event as PreviewPositionReported;
      expect(event.position, const PreviewSourceAddress(7));
      expect(event.viewport.topLine, 7);
      expect(event.viewport.bottomLine, isNull);
    });

    test('JSON 坏了：仍然认出是位置回执，但地址为 null（丢弃，别当成顶部）', () {
      final PreviewEvent event = PreviewEvent.parse('top 3:99 {oops}');
      event as PreviewPositionReported;
      expect(event.token, '3:99');
      expect(event.position, isNull);
      expect(event.viewport, PreviewViewport.empty);
      expect(event.section, isNull);
    });

    test('老回执只有块号 / 像素：地址为 null（一次性换算在 Dart 侧做不了，回顶部）', () {
      final PreviewEvent event =
          PreviewEvent.parse('top t {"block":4,"offset":12,"scrollY":960}');
      event as PreviewPositionReported;
      expect(event.position, isNull);
    });

    test('缺空格归到 PreviewUnknownMessage', () {
      expect(PreviewEvent.parse('top 3:99'), isA<PreviewUnknownMessage>());
    });
  });

  group('outline（章节清单）', () {
    test('Markdown：条目带源码行', () {
      final PreviewEvent event = PreviewEvent.parse(
        'outline 1:2 [{"level":2,"text":"安装","line":8,"id":"安装"}]',
      );
      event as PreviewOutlineReported;
      expect(event.token, '1:2');
      expect(event.outline, isA<PreviewMarkdownOutline>());
      expect(event.outline.length, 1);
      expect(event.outline.entries.single.address, const PreviewSourceAddress(8));
    });

    test('HTML：同一条回执、无凭据，条目带 DOM 路径', () {
      final PreviewEvent event = PreviewEvent.parse(
        'outline - [{"level":1,"text":"安装","path":"body>h1:nth(1)"}]',
      );
      event as PreviewOutlineReported;
      expect(event.token, isNull);
      expect(event.outline, isA<PreviewHtmlOutline>());
      expect(
        event.outline.entries.single.address,
        const PreviewDomAddress('body>h1:nth(1)'),
      );
    });

    test('标题里有空格也不会被切歪（信封按凭据位切，不按内容猜）', () {
      final PreviewEvent event = PreviewEvent.parse(
        'outline - [{"level":2,"text":"第三章 安装与卸载","path":"body>h2:nth(3)"}]',
      );
      event as PreviewOutlineReported;
      expect(event.token, isNull);
      expect(event.outline.entries.single.text, '第三章 安装与卸载');
      expect(
        event.outline.entries.single.address,
        const PreviewDomAddress('body>h2:nth(3)'),
      );
    });

    test('标记了凭据却给空清单：来源仍是 Markdown（两种空清单在调用方眼里一样）', () {
      final PreviewEvent event = PreviewEvent.parse('outline t []');
      event as PreviewOutlineReported;
      expect(event.outline.isEmpty, isTrue);
    });

    test('清单 JSON 坏了给空清单（目录空着，总比显示上一篇强）', () {
      final PreviewEvent event = PreviewEvent.parse('outline t not-json');
      event as PreviewOutlineReported;
      expect(event.outline.isEmpty, isTrue);
    });
  });

  test('anchor：页内锚点已滚好，只带目标（不带凭据）', () {
    final PreviewEvent event = PreviewEvent.parse('anchor 安装');
    event as PreviewAnchorScrolled;
    expect(event.target, '安装');
  });

  group('ast（语法树）', () {
    test('Markdown：凭据与树一起交出去', () {
      final PreviewEvent event = PreviewEvent.parse(
        'ast doc-1:v3 '
        '[{"type":"heading","line":1,"level":1,"text":"标题"},'
        '{"type":"code","line":3,"lang":"dart","text":"x"}]',
      );

      event as PreviewSyntaxReported;
      expect(event.token, 'doc-1:v3');
      expect(event.tree.kind, PreviewSourceKind.markdown);
      expect(event.tree.nodes, hasLength(2));
      expect(event.tree.nodes.first.level, 1);
    });

    test('HTML：无凭据，树带 DOM 路径', () {
      final PreviewEvent event = PreviewEvent.parse(
        'ast - {"kind":"html","nodes":[{"type":"h2","path":"body>h2:nth(1)"}]}',
      );

      event as PreviewSyntaxReported;
      expect(event.token, isNull);
      expect(event.tree.kind, PreviewSourceKind.html);
      expect(event.tree.nodes.single.path, 'body>h2:nth(1)');
    });

    test('树坏了也只丢树，不当成未知消息（别让状态条跳字）', () {
      final PreviewEvent event = PreviewEvent.parse('ast doc-1:v3 {不是 json');
      event as PreviewSyntaxReported;
      expect(event.token, 'doc-1:v3');
      expect(event.tree.isEmpty, isTrue);
    });
  });

  group('focus（命中已高亮，只用于日志）', () {
    test('Markdown：带凭据与处数', () {
      final PreviewEvent event = PreviewEvent.parse('focus 1:2 3');
      event as PreviewFocusApplied;
      expect(event.token, '1:2');
      expect(event.count, 3);
    });

    test('HTML：无凭据，0 处也算正常回执（没找到而已）', () {
      final PreviewEvent event = PreviewEvent.parse('focus - 0');
      event as PreviewFocusApplied;
      expect(event.token, isNull);
      expect(event.count, 0);
    });
  });

  test('认不出的消息原样带出去（页面与 Dart 版本不同步时别炸）', () {
    final PreviewEvent event = PreviewEvent.parse('hello from page');
    event as PreviewUnknownMessage;
    expect(event.raw, 'hello from page');
  });

  test('前缀必须带空格：`report` 之类不许被当成 `render`', () {
    expect(PreviewEvent.parse('renderx 1:2 ok'), isA<PreviewUnknownMessage>());
    expect(PreviewEvent.parse('topology 1:2 {}'), isA<PreviewUnknownMessage>());
  });
}
