import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/anchor_handoff.dart';
import 'package:hyperlens/src/model/code_anchor.dart';
import 'package:hyperlens/src/model/preview_anchor.dart';

void main() {
  group('PreviewAnchor.tryParse：JS 回传什么都行，但不能把读者扔到随机地方', () {
    test('正常的 JSON 字符串', () {
      expect(
        PreviewAnchor.tryParse('{"block":12,"offset":345.5,"scrollY":6789}'),
        const PreviewAnchor(block: 12, offset: 345.5, scrollY: 6789),
      );
    });

    test('已经解好的 Map 也认（模板之外再有人调它不至于踩空）', () {
      expect(
        PreviewAnchor.tryParse(<String, Object?>{
          'block': 3,
          'offset': 0,
          'scrollY': 0,
        }),
        const PreviewAnchor(block: 3, offset: 0, scrollY: 0),
      );
    });

    test('缺 offset：按 0 算，不整条丢掉', () {
      expect(
        PreviewAnchor.tryParse('{"block":2,"scrollY":900}'),
        const PreviewAnchor(block: 2, offset: 0, scrollY: 900),
      );
    });

    test('不是 JSON / 不是对象 / 缺关键字段 → null（当作没有位置，回顶部）', () {
      expect(PreviewAnchor.tryParse('not json'), isNull);
      expect(PreviewAnchor.tryParse('42'), isNull);
      expect(PreviewAnchor.tryParse(null), isNull);
      expect(PreviewAnchor.tryParse('{"offset":5}'), isNull);
      expect(PreviewAnchor.tryParse('{"block":"x","scrollY":1}'), isNull);
    });

    test('toJson ↔ tryParse 往返一致（模板的 payload.restore 就走这条）', () {
      const PreviewAnchor anchor =
          PreviewAnchor(block: 7, offset: 120, scrollY: 3050);
      expect(PreviewAnchor.tryParse(jsonEncode(anchor.toJson())), anchor);
    });

    test('视口底行：解析出来，但不进相等性、也不写回模板', () {
      final PreviewAnchor? parsed = PreviewAnchor.tryParse(
        '{"block":2,"scrollY":900,"line":10,"bottomLine":42}',
      );
      expect(parsed!.line, 10);
      expect(parsed.bottomLine, 42);
      // 观测量（同 CodeAnchor.screenBottomLine）：同一处的两帧，屏幕高度变了也不算换位置
      expect(
        parsed,
        const PreviewAnchor(block: 2, offset: 0, scrollY: 900, line: 10),
      );
      expect(parsed.toJson().containsKey('bottomLine'), isFalse);
    });
  });

  group('源码行号：预览与源码切换时靠它交接', () {
    test('往返：行号跟着一起走', () {
      const PreviewAnchor anchor =
          PreviewAnchor(block: 7, offset: 120, scrollY: 3050, line: 240);
      final PreviewAnchor? parsed = PreviewAnchor.tryParse(anchor.toJson());
      expect(parsed, anchor);
      expect(parsed!.line, 240);
    });

    test('行号算不出来（0）时不写这个键：HTML 预览与旧记忆里都没有它', () {
      const PreviewAnchor anchor =
          PreviewAnchor(block: 2, offset: 0, scrollY: 480);
      expect(anchor.toJson().containsKey('line'), isFalse);
    });

    test('老数据没有行号：按 0 处理，块级还原照旧', () {
      final PreviewAnchor? parsed =
          PreviewAnchor.tryParse('{"block":12,"offset":345.5,"scrollY":6789}');
      expect(parsed?.line, 0);
      expect(parsed?.block, 12);
    });
  });

  /// 模板那边的约定（字段与 `mdTopAnchor` / `mdRestore` 一一对应，见类注释）。
  /// 主机上没有 WebView，只能钉住「脚本还在、口径没被改掉」；真正的行为
  /// 在真浏览器里验过（逐 token 的行号表、落位与反算都对得上）。
  group('模板里的行号脚本（静态资源）', () {
    final String html = File('assets/web/markdown_view.html').readAsStringSync();

    test('每个顶级块前插行号标记，扫完就摘（留着会让块序号整体挪位）', () {
      expect(html.contains("'<span class=\"hyperlens-md-line hyperlens-l-'"), isTrue);
      expect(html.contains('mdBlockLines = mdReadBlockLines(host)'), isTrue);
      expect(html.contains("querySelectorAll('.hyperlens-md-line')"), isTrue);
    });

    test('上报带 line、还原优先按 line —— 预览与源码交接靠它', () {
      final int report = html.indexOf('function mdTopAnchor');
      expect(report, greaterThan(0));
      expect(html.substring(report, report + 600).contains('line: mdLineAt(y)'),
          isTrue);

      final int restore = html.indexOf('function mdRestore');
      expect(restore, greaterThan(0));
      expect(
        html.substring(restore, restore + 600).contains('mdYForLine(a.line)'),
        isTrue,
      );
    });

    test('词法失败也不许白屏：退回整篇 parse', () {
      final int render = html.indexOf('window.marked.lexer(');
      expect(render, greaterThan(0));
      expect(
        html.substring(render, render + 1200).contains('window.marked.parse('),
        isTrue,
      );
    });
  });

  group('预览 ↔ 源码交接', () {
    test('源码 → Markdown 预览：只带行号', () {
      final PreviewAnchor? anchor = AnchorHandoff.toPreview(
        entryPath: 'docs/readme.md',
        codeLine: 42,
      );
      expect(anchor?.line, 42);
      expect(anchor?.block, -1, reason: '预览侧按行找块，块号交给 JS 算');
    });

    test('源码 → HTML 预览：不动（那条通道记的是 scrollY）', () {
      expect(
        AnchorHandoff.toPreview(entryPath: 'docs/page.html', codeLine: 42),
        isNull,
      );
    });

    test('源码还没报过行号（0）：不猜', () {
      expect(
        AnchorHandoff.toPreview(entryPath: 'docs/readme.md', codeLine: 0),
        isNull,
      );
    });

    test('预览 → 源码：只带行号，偏移交给顶对齐闭环', () {
      final CodeAnchor? anchor = AnchorHandoff.toCode(previewLine: 7);
      expect(anchor?.line, 7);
      expect(anchor?.offset, 0);
      expect(anchor?.fontSize, 0);
    });

    test('预览没算出行号：不猜', () {
      expect(AnchorHandoff.toCode(previewLine: 0), isNull);
    });
  });
}
