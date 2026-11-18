import 'dart:convert';

import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/model/html_outline.dart';
import 'package:hyperlens/src/model/preview_position.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreviewHtmlOutline.parse：页面回传的 <h1>~<h6>', () {
    test('层级 / 文本按页面给的来，地址是 DOM 路径（HTML 没有源码行号）', () {
      final PreviewHtmlOutline outline = PreviewHtmlOutline.parse(jsonEncode(<Object>[
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
        const PreviewDomAddress('body>div#main>h2:nth(2)'),
      );
      expect(outline.entries[1].id, 'sec1');
      expect(
        outline.entries.every((e) => e.address is PreviewDomAddress),
        isTrue,
      );
    });

    test('坏条目单条丢弃，不整体失败', () {
      final PreviewHtmlOutline outline = PreviewHtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '好的', 'path': 'body>h1:nth(1)'},
        <String, Object>{'level': 9, 'text': '层级越界', 'path': 'body>h9'},
        <String, Object>{'text': '缺字段'},
        <String, Object>{'level': 2, 'text': '缺路径'},
        'not a map',
      ]));
      expect(outline.entries.map((e) => e.text), <String>['好的']);
    });

    test('认不出来的载荷 → 空清单（不抛异常）', () {
      expect(PreviewHtmlOutline.parse('{').isEmpty, isTrue);
      expect(PreviewHtmlOutline.parse(<Object>[]).isEmpty, isTrue);
      expect(PreviewHtmlOutline.parse(null).isEmpty, isTrue);
    });

    test('页面报来的 sec 下标越界就当没有当前节', () {
      final PreviewHtmlOutline outline = PreviewHtmlOutline.parse(jsonEncode(<Object>[
        <String, Object>{'level': 1, 'text': '唯一', 'path': 'body>h1:nth(1)'},
      ]));
      expect(outline.sectionAtIndex(0), 0);
      expect(outline.sectionAtIndex(3), -1);
      expect(outline.sectionAtIndex(-1), -1);
      expect(PreviewHtmlOutline.empty.sectionAtIndex(0), -1);
    });
  });

  test('注入脚本里有扫标题 / 上报清单 / 跳转三段（Dart 侧按名字调用）', () {
    // 页面侧函数名是契约：`HyperlensCommands.scrollToPath` 就调 hyperLensScrollToPath
    final String script = htmlAnchorScript(null);
    expect(script, contains('hyperLensSectionsPost'));
    expect(script, contains('hyperLensScrollToPath'));
    expect(script, contains("'outline - '"));
    expect(script, contains('sec: hyperLensSectionIndex()'));
  });
}
