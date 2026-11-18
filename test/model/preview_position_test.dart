import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/anchor_handoff.dart';
import 'package:hyperlens/src/model/code_anchor.dart';
import 'package:hyperlens/src/model/preview_position.dart';

void main() {
  group('地址：只有源码行与 DOM 路径两种', () {
    test('源码行：JSON 字符串 / 已解好的 Map 都认', () {
      expect(
        PreviewPosition.tryParse('{"line":12}'),
        const PreviewSourceAddress(12),
      );
      expect(
        PreviewPosition.tryParse(<String, Object?>{'line': 3}),
        const PreviewSourceAddress(3),
      );
    });

    test('DOM 路径：路径优先于行号（HTML 侧的地址）', () {
      expect(
        PreviewPosition.tryParse('{"path":"body>div#main>h2:nth(3)"}'),
        const PreviewDomAddress('body>div#main>h2:nth(3)'),
      );
    });

    test('不是 JSON / 不是对象 / 认不出地址 → null（当「没有位置」，回顶部）', () {
      expect(PreviewPosition.tryParse('not json'), isNull);
      expect(PreviewPosition.tryParse('42'), isNull);
      expect(PreviewPosition.tryParse(null), isNull);
      expect(PreviewPosition.tryParse('{"path":""}'), isNull);
      expect(PreviewPosition.tryParse('{"line":0}'), isNull);
      expect(PreviewPosition.tryParse('{"line":"x"}'), isNull);
    });

    test('老记忆（只有 block / offset / scrollY）→ 无地址，不猜', () {
      // 文件被改过时按像素落位会把读者扔到无关段落；明确回顶部好过猜
      expect(
        PreviewPosition.tryParse('{"block":12,"offset":345.5,"scrollY":6789}'),
        isNull,
      );
    });

    test('老记忆里带 line 的：换算成源码行（一次性，运行时不再有第三套坐标）', () {
      expect(
        PreviewPosition.tryParse('{"block":12,"offset":0,"scrollY":6789,"line":240}'),
        const PreviewSourceAddress(240),
      );
    });

    test('toJson ↔ tryParse 往返一致（模板的 payload.restore 就走这条）', () {
      const PreviewPosition line = PreviewSourceAddress(7);
      const PreviewPosition path = PreviewDomAddress('body>p:nth(2)');
      expect(PreviewPosition.tryParse(jsonEncode(line.toJson())), line);
      expect(PreviewPosition.tryParse(jsonEncode(path.toJson())), path);
    });

    test('top 是第 1 行；HTML 的「从头」是 body', () {
      expect(PreviewPosition.top, const PreviewSourceAddress(1));
      expect(PreviewDomAddress.body.path, 'body');
    });
  });

  group('观测量：每帧的视口顶 / 底，不进地址', () {
    test('解析 line / bottomLine', () {
      final PreviewViewport viewport =
          PreviewViewport.parse(<String, Object?>{'line': 10, 'bottomLine': 42});
      expect(viewport.topLine, 10);
      expect(viewport.bottomLine, 42);
    });

    test('缺字段 / 0 / 不是对象 → null（不猜行号）', () {
      expect(PreviewViewport.parse(<String, Object?>{'line': 0}).topLine, isNull);
      expect(PreviewViewport.parse('nope').topLine, isNull);
      expect(PreviewViewport.parse(null), PreviewViewport.empty);
    });

    test('不进地址：同一处位置的两帧，屏幕高度变了也不算换位置', () {
      const PreviewPosition position = PreviewSourceAddress(10);
      expect(
        PreviewPosition.tryParse('{"line":10,"bottomLine":42}'),
        position,
      );
      expect(
        PreviewPosition.tryParse('{"line":10,"bottomLine":60}'),
        position,
      );
    });
  });

  /// 模板那边的约定（字段与 `mdTopAnchor` / `mdRestore` / `mdScrollToLine` 一一对应）。
  /// 主机上没有 WebView，只能钉住「脚本还在、口径没被改回去」；真正的行为在真浏览器
  /// 里验过（逐 token 的行号表、落位与反算都对得上）。
  group('模板里的行号脚本（静态资源）', () {
    final String html = File('assets/web/markdown_view.html').readAsStringSync();

    test('每个顶级块前插行号标记，扫完就摘（留着会让块序号整体挪位）', () {
      expect(html.contains("'<span class=\"hyperlens-md-line hyperlens-l-'"), isTrue);
      expect(html.contains('mdBlockLines = mdReadBlockLines(host)'), isTrue);
      expect(html.contains("querySelectorAll('.hyperlens-md-line')"), isTrue);
    });

    test('上报只给 line + bottomLine，不再带 block / offset / scrollY', () {
      final int report = html.indexOf('function mdTopAnchor');
      expect(report, greaterThan(0));
      final String body = html.substring(report, report + 600);
      expect(body.contains('line: mdLineAt(y)'), isTrue);
      expect(body.contains('bottomLine:'), isTrue);
      expect(body.contains('block:'), isFalse);
      expect(body.contains('scrollY:'), isFalse);
    });

    test('还原只有一档：按行；算不出来就回顶部（没有像素兜底）', () {
      final int restore = html.indexOf('function mdRestore');
      expect(restore, greaterThan(0));
      final String body = html.substring(restore, restore + 500);
      expect(body.contains('mdYForLine(a.line)'), isTrue);
      expect(body.contains('scrollTo(0, Math.max(0, y === null ? 0 : y))'), isTrue);
    });

    test('滚动原语是 mdScrollToLine；旧的按块滚动已删除', () {
      expect(html.contains('function mdScrollToLine(line)'), isTrue);
      expect(html.contains('mdScrollToBlock'), isFalse);
    });

    test('目录清单只带行号，不带块号', () {
      final int outline = html.indexOf('outline.push({');
      expect(outline, greaterThan(0));
      final String body = html.substring(outline, outline + 300);
      expect(body.contains('line: mdLineOfBlock(i)'), isTrue);
      expect(body.contains('block:'), isFalse);
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
      final PreviewSourceAddress? address = PreviewAnchorHandoff.toPreview(
        entryPath: 'docs/readme.md',
        codeLine: 42,
      );
      expect(address, const PreviewSourceAddress(42));
    });

    test('源码 → HTML 预览：不动（那条通道的地址是 DOM 路径）', () {
      expect(
        PreviewAnchorHandoff.toPreview(entryPath: 'docs/page.html', codeLine: 42),
        isNull,
      );
    });

    test('源码还没报过行号（0）：不猜', () {
      expect(
        PreviewAnchorHandoff.toPreview(entryPath: 'docs/readme.md', codeLine: 0),
        isNull,
      );
    });

    test('预览 → 源码：只带行号，偏移交给顶对齐闭环', () {
      final PreviewCodeAnchor? anchor = PreviewAnchorHandoff.toCode(previewLine: 7);
      expect(anchor?.line, 7);
      expect(anchor?.offset, 0);
      expect(anchor?.fontSize, 0);
    });

    test('预览没算出行号：不猜', () {
      expect(PreviewAnchorHandoff.toCode(previewLine: 0), isNull);
    });
  });
}
