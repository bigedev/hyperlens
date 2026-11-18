import 'dart:convert';

import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/model/html_outline.dart';
import 'package:hyperlens/src/model/preview_position.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlOutline.parse：页面回传的 <h1>~<h6>', () {
    test('层级 / 文本按页面给的来，地址是 DOM 路径（HTML 没有源码行号）', () {
      final HtmlOutline outline = HtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{
          'level': 1,
          'text': '第一章',
          'path': 'body>div#main>h1:nth(1)',
          'id': '',
        },
        <String, Object>{
          'level': 2,
          'text': '第一节',
          'path': 'body>div#main>h2:nth(2)',
          'id': 'sec1',
        },
      ]));
      expect(outline.length, 2);
      expect(outline.entries[0].level, 1);
      expect(outline.entries[1].text, '第一节');
      expect(
        outline.entries[1].address,
        const DomAddress('body>div#main>h2:nth(2)'),
      );
      expect(outline.entries[1].id, 'sec1');
      expect(
        outline.entries.every((e) => e.address is DomAddress),
        isTrue,
      );
    });

    test('坏条目单条丢弃，不整体失败', () {
      final HtmlOutline outline = HtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '好的', 'path': 'body>h1:nth(1)'},
        <String, Object>{'level': 9, 'text': '层级越界', 'path': 'body>h9'},
        <String, Object>{'text': '缺字段'},
        <String, Object>{'level': 2, 'text': '缺路径'},
        'not a map',
      ]));
      expect(outline.entries.map((e) => e.text), <String>['好的']);
    });

    test('认不出来的载荷 → 空清单（不抛异常）', () {
      expect(HtmlOutline.parse('{').isEmpty, isTrue);
      expect(HtmlOutline.parse(<Object>[]).isEmpty, isTrue);
      expect(HtmlOutline.parse(null).isEmpty, isTrue);
    });

    test('只处理 `outline ` 前缀，别的一律返回 null', () {
      expect(HtmlOutline.parseReport('scroll {"path":"body","sec":0}'), isNull);
      expect(HtmlOutline.parseReport('outline []'), isNotNull);
    });

    test('页面报来的 sec 下标越界就当没有当前节', () {
      final HtmlOutline outline = HtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '唯一', 'path': 'body>h1:nth(1)'},
      ]));
      expect(outline.sectionAtIndex(0), 0);
      expect(outline.sectionAtIndex(3), -1);
      expect(outline.sectionAtIndex(-1), -1);
      expect(HtmlOutline.empty.sectionAtIndex(0), -1);
    });
  });

  group('parseHtmlAnchorWithSection：一条位置回执同时带回读到第几节', () {
    test('一次解出地址（DOM 路径）与 sec（不用把同一条 JSON 解两遍）', () {
      final report = parseHtmlAnchorWithSection(
        'scroll {"path":"body>div#main>p:nth(3)","sec":3}',
      );
      expect(report, isNotNull);
      expect(
        report!.position,
        const DomAddress('body>div#main>p:nth(3)'),
      );
      expect(report.section, 3);
    });

    test('没有 sec → section = -1（位置有、章节没有）', () {
      final report = parseHtmlAnchorWithSection('scroll {"path":"body"}');
      expect(report?.section, -1);
      expect(report?.position, DomAddress.body);
    });

    test('老回执只有像素：位置为 null（按「没有地址」回顶部），不再猜', () {
      final report =
          parseHtmlAnchorWithSection('scroll {"block":-1,"scrollY":1200}');
      expect(report, isNotNull);
      expect(report!.position, isNull);
    });

    test('不是位置回执 / JSON 坏了 → null', () {
      expect(parseHtmlAnchorWithSection('outline []'), isNull);
      expect(parseHtmlAnchorWithSection('scroll {'), isNull);
    });
  });

  test('注入脚本里有扫标题 / 上报清单 / 跳转三段（Dart 侧按名字调用）', () {
    // 页面侧函数名是契约：`HyperlensCommands.scrollToPath` 就调 hyperLensScrollToPath
    final String script = htmlAnchorScript(null);
    expect(script, contains('hyperLensSectionsPost'));
    expect(script, contains('hyperLensScrollToPath'));
    expect(script, contains("'outline '"));
    expect(script, contains('sec: hyperLensSectionIndex()'));
  });
}
