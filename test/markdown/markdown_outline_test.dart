import 'dart:io';

import 'package:hyperlens/src/model/markdown_outline.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('解析模板回传的章节清单', () {
    const String payload = '[{"level":1,"text":"大仓","block":0,"id":"大仓"},'
        '{"level":2,"text":"环境要求","block":3,"id":"环境要求"},'
        '{"level":3,"text":"macOS 工具链","block":5,"id":"macos-工具链"}]';

    test('字符串载荷（JS JSON.stringify）逐字段还原', () {
      final MarkdownOutline outline = MarkdownOutline.parse(payload);
      expect(outline.length, 3);
      expect(outline.isEmpty, isFalse);
      expect(outline.entries[1].level, 2);
      expect(outline.entries[1].text, '环境要求');
      expect(outline.entries[1].block, 3);
      expect(outline.entries[2].id, 'macos-工具链');
    });

    test('也收已解好的 List（与 PreviewAnchor.tryParse 同口径）', () {
      final MarkdownOutline outline = MarkdownOutline.parse(<Object?>[
        <String, Object?>{'level': 2, 'text': '只有一节', 'block': 1},
      ]);
      expect(outline.length, 1);
      expect(outline.entries.single.id, '');
    });

    test('坏载荷一律当「没有章节」，不抛异常（它跑在「渲染是否成功」的路径旁边）', () {
      for (final Object? bad in <Object?>['', 'not json', '{}', 'null', '[]', null, 42]) {
        expect(MarkdownOutline.parse(bad).isEmpty, isTrue, reason: '载荷：$bad');
      }
    });

    test('单条坏就丢那一条，其余照收', () {
      final MarkdownOutline outline = MarkdownOutline.parse('['
          '{"level":2,"text":"好的","block":4},'
          '{"level":9,"text":"层级越界","block":5},'
          '{"block":6},'
          '{"level":2,"text":"缺块号"},'
          '{"level":2,"text":"负块号","block":-1},'
          '{"level":3,"block":7}'
          ']');
      expect(outline.length, 2);
      expect(outline.entries[0].text, '好的');
      // 缺 text 的那条保留（标题可能是纯图标），文本按空串处理，抽屉里显示占位
      expect(outline.entries[1].text, '');
      expect(outline.entries[1].block, 7);
    });

    test('带源码行号（模板新回执）：line 逐条还原，缺省为 0', () {
      final MarkdownOutline outline = MarkdownOutline.parse(
        '[{"level":1,"text":"甲","block":0,"line":1},'
        '{"level":2,"text":"乙","block":4}]',
      );
      expect(outline.entries[0].line, 1);
      expect(outline.entries[1].line, 0); // 老回执没有这个键
    });

    test('载荷顺序乱了也按 block 排好 —— 否则二分反查会给错小节', () {
      final MarkdownOutline outline = MarkdownOutline.parse(
        '[{"level":2,"text":"后","block":9},{"level":2,"text":"前","block":2}]',
      );
      expect(outline.entries.first.block, 2);
      expect(outline.entries.last.block, 9);
      expect(outline.currentFor(3), 0);
    });

    test('同字段即同一条（抽屉靠它判断要不要重建）', () {
      expect(
        MarkdownOutline.parse(payload).entries[1],
        MarkdownOutline.parse(payload).entries[1],
      );
      expect(
        const OutlineEntry(level: 2, text: 'a', block: 1),
        const OutlineEntry(level: 2, text: 'a', block: 1, id: ''),
      );
    });
  });

  group('缩进按最外层标题归一', () {
    test('文档从 ## 起步时整篇不多缩一层', () {
      final MarkdownOutline outline = MarkdownOutline.parse('['
          '{"level":2,"text":"环境要求","block":0},'
          '{"level":3,"text":"Flutter-OH SDK","block":2},'
          '{"level":2,"text":"编译与运行","block":4}'
          ']');
      expect(outline.baseLevel, 2);
      expect(outline.indentOf(0), 0);
      expect(outline.indentOf(1), 1);
      expect(outline.indentOf(2), 0);
    });

    test('跳级照实缩进，但封顶 3 层（手机竖屏再深就成一条缝）', () {
      final MarkdownOutline outline = MarkdownOutline.parse('['
          '{"level":1,"text":"A","block":0},'
          '{"level":4,"text":"B","block":1},'
          '{"level":6,"text":"C","block":2}'
          ']');
      expect(outline.indentOf(0), 0);
      expect(outline.indentOf(1), 3);
      expect(outline.indentOf(2), 3);
    });

    test('空清单与其他越界下标都回 0', () {
      expect(MarkdownOutline.empty.indentOf(0), 0);
      expect(MarkdownOutline.empty.baseLevel, 1);
      final MarkdownOutline outline = MarkdownOutline.parse('[{"level":2,"text":"a","block":0}]');
      expect(outline.indentOf(-1), 0);
      expect(outline.indentOf(99), 0);
    });
  });

  group('反查「现在读到哪一节」', () {
    final MarkdownOutline outline = MarkdownOutline.parse('['
        '{"level":1,"text":"A","block":2},'
        '{"level":2,"text":"B","block":5}'
        ']');

    test('首个标题之前算第一节（抽屉不能一条都不高亮）', () {
      expect(outline.currentFor(0), 0);
      expect(outline.currentFor(1), 0);
      expect(outline.currentFor(-1), -1); // 非法位置仍然没有「当前项」
      expect(MarkdownOutline.empty.currentFor(3), -1);
    });

    test('标题本身与它下面的正文都算这一节', () {
      expect(outline.currentFor(2), 0);
      expect(outline.currentFor(4), 0); // A 与 B 之间的正文
      expect(outline.currentFor(5), 1);
      expect(outline.currentFor(999), 1); // 最后一节之后的正文
    });
  });

  group('屏幕上的当前节：标题还在屏上就算它（与源码态同一判据）', () {
    // 甲 @1（1..40）、乙 @41（41..80）、丙 @81
    final MarkdownOutline outline = MarkdownOutline.parse('['
        '{"level":1,"text":"甲","block":0,"line":1},'
        '{"level":2,"text":"乙","block":10,"line":41},'
        '{"level":2,"text":"丙","block":20,"line":81}'
        ']');

    test('标题就在顶端：是它', () {
      expect(outline.currentForScreen(1, 35), 0);
    });

    test('下一节的标题只在下半屏露头：仍算这一节', () {
      // 顶端 20 还在甲的正文里；屏幕 20..60 的中线是 40，乙的标题 41 还差一行
      expect(outline.currentForScreen(20, 60), 0);
    });

    test('下一节的标题压在中线上：仍算这一节', () {
      // 屏幕 20..62：中线 41，正好是乙的标题行
      expect(outline.currentForScreen(20, 62), 0);
    });

    test('下一节的标题越过中线：交给下一节', () {
      // 屏幕 20..64：中线 42，乙的标题 41 已经越过它
      expect(outline.currentForScreen(20, 64), 1);
    });

    test('下一节的标题还没上屏：仍算这一节', () {
      expect(outline.currentForScreen(20, 40), 0);
    });

    test('已经在乙里：就是乙（丙还没上屏）', () {
      expect(outline.currentForScreen(50, 80), 1);
    });

    test('老回执没有行号：退回块级判法（与旧行为一致）', () {
      final MarkdownOutline old = MarkdownOutline.parse('['
          '{"level":1,"text":"甲","block":0},'
          '{"level":2,"text":"乙","block":10}'
          ']');
      expect(old.currentForScreen(5, 20, block: 10), 1);
      expect(old.currentForScreen(5, 20, block: 3), 0);
    });

    test('currentForLine：首个标题之前算第一节，算不出来返回 -1', () {
      expect(outline.currentForLine(1), 0);
      expect(outline.currentForLine(40), 0);
      expect(outline.currentForLine(41), 1);
      expect(outline.currentForLine(0), -1);
      expect(MarkdownOutline.empty.currentForLine(5), -1);
    });
  });

  group('「这份清单换了没有」按内容比', () {
    const MarkdownOutline one = MarkdownOutline(<OutlineEntry>[
      OutlineEntry(level: 1, text: 'A', block: 0, id: 'a'),
      OutlineEntry(level: 2, text: 'B', block: 3, id: 'b'),
    ]);

    test('同一份清单重新回传（新对象）算一样 —— 重渲不该清折叠', () {
      // 别提成 const：const 会被规范化成同一个实例，那样测的就不是「新对象」
      final MarkdownOutline again = MarkdownOutline(<OutlineEntry>[
        const OutlineEntry(level: 1, text: 'A', block: 0, id: 'a'),
        const OutlineEntry(level: 2, text: 'B', block: 3, id: 'b'),
      ]);
      expect(identical(one, again), isFalse);
      expect(one.sameContentAs(again), isTrue);
    });

    test('标题改了 / 层级变了 / 增删一节，都算换了', () {
      expect(
        one.sameContentAs(
          const MarkdownOutline(<OutlineEntry>[
            OutlineEntry(level: 1, text: 'A', block: 0, id: 'a'),
            OutlineEntry(level: 2, text: 'B2', block: 3, id: 'b'),
          ]),
        ),
        isFalse,
      );
      expect(
        one.sameContentAs(
          const MarkdownOutline(<OutlineEntry>[
            OutlineEntry(level: 3, text: 'B', block: 3, id: 'b'),
          ]),
        ),
        isFalse,
      );
      expect(one.sameContentAs(MarkdownOutline.empty), isFalse);
    });

    test('空清单与自己一样（首帧还没收到回执时不该判成「换了」）', () {
      expect(MarkdownOutline.empty.sameContentAs(MarkdownOutline.empty), isTrue);
    });
  });

  group('模板里的钩子（静态资源）', () {
    final String html = File('assets/web/markdown_view.html').readAsStringSync();

    test('有块级滚动函数，且走 window.scrollTo（与位置还原同一套坐标）', () {
      expect(html.contains('function mdScrollToBlock(n)'), isTrue);
      final String body = functionBodyOf(html, 'function mdScrollToBlock(n)');
      expect(body.contains('window.scrollTo'), isTrue);
      // 跳过去之后要补报位置：读者可能马上按返回
      expect(body.contains('__mdReportAnchor'), isTrue);
    });

    test('目录跳转先放弃「按住还原」—— 否则跳过去又被拽回原位', () {
      // 无头实测（Chrome headless + 真模板）：跳到目标 top=0，400ms 后还原把页面
      // 拉回 -252px。读者看到的就是「点了目录却停在半路」，所以跳转必须取消还原。
      final String body = functionBodyOf(html, 'function mdScrollToBlock(n)');
      expect(body.contains('mdUserTouched = true'), isTrue);
      expect(body.contains('mdHolding = false'), isTrue);
    });

    test('清单回传带本页凭据 —— 否则换文档时会显示上一篇的目录', () {
      expect(html.contains("post('outline ' + payload.token + ' '"), isTrue);
    });

    test('清单收集排在 render 回执之后：回执是「真的渲染了」的唯一凭据，不能被吞掉', () {
      expect(
        html.indexOf("post('render ' + payload.token + ' ok") <
            html.indexOf("post('outline '"),
        isTrue,
      );
    });

    test('渲染回执带本页凭据 —— 否则旧页面收尾那枪会拆掉新这页的看门狗', () {
      for (final String tail in <String>[
        'ok（',
        'empty',
        'no-marked',
        '异常: ',
      ]) {
        expect(
          html.contains("post('render ' + payload.token + ' $tail"),
          isTrue,
          reason: '缺少带凭据的回执：$tail',
        );
      }
    });

    test('标题真的被写上 id（文档内 `[x](#小节)` 才跳得动）', () {
      expect(html.contains('function mdSlug(text, seen)'), isTrue);
      expect(html.contains('heading.id = slug'), isTrue);
      // slug 必须用「排除法」正则，不许改成 \p{…} + u 标志：老引擎上正则解析失败会让
      // 整个 <script> 块失效，连位置还原一起废掉（为一条 slug 规则不值当）。
      // 只看函数体（注释里提到这个取舍，不算数）。
      final String body = html.substring(
        html.indexOf('function mdSlug(text, seen)'),
        html.indexOf('function mdTopAnchor'),
      );
      expect(body.contains(r'\p{'), isFalse);
      expect(
        body.contains(
          r'.replace(/[^\w\-\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+/g',
        ),
        isTrue,
      );
    });

    test('锚点查找同时试转义与原样（`#%E9%85%8D%E7%BD%AE` 与 `#配置` 都要能跳）', () {
      expect(html.contains('decodeURIComponent(raw)'), isTrue);
      expect(html.contains('document.getElementById(raw)'), isTrue);
    });
  });
}

/// 取某段函数体的源码（从签名到它的收尾 `\n    }`）。
///
/// 比「从签名往后切 400 字」稳：函数里补两行注释就会把断言窗口顶出去，看起来像功能
/// 丢了、其实只是窗口不够长。
String functionBodyOf(String source, String signature) {
  final int at = source.indexOf(signature);
  expect(at, isNot(-1), reason: '模板里找不到 $signature');
  final int end = source.indexOf('\n    }', at);
  return source.substring(at, end == -1 ? source.length : end);
}
