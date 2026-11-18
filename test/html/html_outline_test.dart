import 'dart:convert';

import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/model/html_outline.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlOutline.parse：页面回传的 <h1>~<h6>', () {
    test('层级 / 下标 / 文本按页面给的来，line 恒为 0（HTML 没有源码行号）', () {
      final HtmlOutline outline = HtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '第一章', 'index': 0},
        <String, Object>{'level': 2, 'text': '第一节', 'index': 1},
      ]));
      expect(outline.length, 2);
      expect(outline.entries[0].level, 1);
      expect(outline.entries[1].text, '第一节');
      expect(outline.entries[1].block, 1);
      expect(outline.entries.every((e) => e.line == 0), isTrue);
    });

    test('坏条目单条丢弃，不整体失败', () {
      final HtmlOutline outline = HtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '好的', 'index': 0},
        <String, Object>{'level': 9, 'text': '层级越界', 'index': 1},
        <String, Object>{'text': '缺字段'},
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
      expect(HtmlOutline.parseReport('scroll {"block":-1,"scrollY":0}'), isNull);
      expect(HtmlOutline.parseReport('outline []'), isNotNull);
    });
  });

  group('parseHtmlAnchorWithSection：一条位置回执同时带回读到第几节', () {
    test('一次解出锚点与 sec（不用把同一条 JSON 解两遍）', () {
      final report = parseHtmlAnchorWithSection(
        'scroll {"block":-1,"offset":0,"scrollY":1200,"sec":3}',
      );
      expect(report, isNotNull);
      expect(report!.anchor.scrollY, 1200);
      expect(report.section, 3);
    });

    test('没有 sec → section = -1（位置有、章节没有）', () {
      final report =
          parseHtmlAnchorWithSection('scroll {"block":-1,"scrollY":0}');
      expect(report?.section, -1);
      expect(report?.anchor.scrollY, 0);
    });

    test('不是位置回执 / JSON 坏了 → null', () {
      expect(parseHtmlAnchorWithSection('outline []'), isNull);
      expect(parseHtmlAnchorWithSection('scroll {'), isNull);
    });
  });

  test('注入脚本里有扫标题 / 上报清单 / 跳转三段（Dart 侧按名字调用）', () {
    // 页面侧函数名是契约：`html_view.dart` 的 scrollToSection 就调 hyperLensScrollToSection
    final String script = htmlAnchorScript(null);
    expect(script, contains('hyperLensSectionsPost'));
    expect(script, contains('hyperLensScrollToSection'));
    expect(script, contains("'outline '"));
    expect(script, contains('sec: hyperLensSectionIndex()'));
  });
}
