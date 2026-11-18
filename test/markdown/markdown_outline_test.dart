import 'dart:io';

import 'package:hyperlens/src/model/markdown_outline.dart';
import 'package:hyperlens/src/model/preview_position.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('解析模板回传的章节清单', () {
    const String payload = '[{"level":1,"text":"大仓","line":1,"id":"大仓"},'
        '{"level":2,"text":"环境要求","line":12,"id":"环境要求"},'
        '{"level":3,"text":"macOS 工具链","line":20,"id":"macos-工具链"}]';

    test('字符串载荷（JS JSON.stringify）逐字段还原，地址是源码行', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse(payload);
      expect(outline.length, 3);
      expect(outline.isEmpty, isFalse);
      expect(outline.entries[1].level, 2);
      expect(outline.entries[1].text, '环境要求');
      expect(outline.entries[1].address, const PreviewSourceAddress(12));
      expect(outline.entries[2].id, 'macos-工具链');
    });

    test('也收已解好的 List（与 PreviewPosition.tryParse 同口径）', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse(<Object?>[
        <String, Object?>{'level': 2, 'text': '只有一节', 'line': 5},
      ]);
      expect(outline.length, 1);
      expect(outline.entries.single.id, '');
      expect(outline.entries.single.address, const PreviewSourceAddress(5));
    });

    test('坏载荷一律当「没有章节」，不抛异常（它跑在「渲染是否成功」的路径旁边）', () {
      for (final Object? bad in <Object?>['', 'not json', '{}', 'null', '[]', null, 42]) {
        expect(PreviewMarkdownOutline.parse(bad).isEmpty, isTrue, reason: '载荷：$bad');
      }
    });

    test('单条坏就丢那一条，其余照收', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse('['
          '{"level":2,"text":"好的","line":4},'
          '{"level":9,"text":"层级越界","line":5},'
          '{"line":6},'
          '{"level":2,"text":"缺行号"},'
          '{"level":2,"text":"行号为 0","line":0},'
          '{"level":2,"text":"行号为负","line":-1},'
          '{"level":3,"line":7}'
          ']');
      // 保留：好的、层级合法但没 text 的那条
      expect(outline.length, 2);
      expect(outline.entries[0].text, '好的');
      // 缺 text 的那条保留（标题可能是纯图标），文本按空串处理，抽屉里显示占位
      expect(outline.entries[1].text, '');
      expect(outline.entries[1].address, const PreviewSourceAddress(7));
    });

    test('载荷顺序乱了也按行号排好 —— 否则二分反查会给错小节', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse(
        '[{"level":2,"text":"后","line":30},{"level":2,"text":"前","line":2}]',
      );
      expect(outline.entries.first.address, const PreviewSourceAddress(2));
      expect(outline.entries.last.address, const PreviewSourceAddress(30));
      expect(outline.sectionAtLine(3), 0);
    });

    test('同字段即同一条（抽屉靠它判断要不要重建）', () {
      expect(
        PreviewMarkdownOutline.parse(payload).entries[1],
        PreviewMarkdownOutline.parse(payload).entries[1],
      );
      expect(
        const PreviewOutlineEntry(level: 2, text: 'a', address: PreviewSourceAddress(1)),
        const PreviewOutlineEntry(level: 2, text: 'a', address: PreviewSourceAddress(1), id: ''),
      );
    });
  });

  group('缩进按最外层标题归一', () {
    test('文档从 ## 起步时整篇不多缩一层', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse('['
          '{"level":2,"text":"环境要求","line":1},'
          '{"level":3,"text":"Flutter-OH SDK","line":5},'
          '{"level":2,"text":"编译与运行","line":9}'
          ']');
      expect(outline.baseLevel, 2);
      expect(outline.indentOf(0), 0);
      expect(outline.indentOf(1), 1);
      expect(outline.indentOf(2), 0);
    });

    test('跳级照实缩进，但封顶 3 层（手机竖屏再深就成一条缝）', () {
      final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse('['
          '{"level":1,"text":"A","line":1},'
          '{"level":4,"text":"B","line":2},'
          '{"level":6,"text":"C","line":3}'
          ']');
      expect(outline.indentOf(0), 0);
      expect(outline.indentOf(1), 3);
      expect(outline.indentOf(2), 3);
    });

    test('空清单与其他越界下标都回 0', () {
      expect(PreviewMarkdownOutline.empty.indentOf(0), 0);
      expect(PreviewMarkdownOutline.empty.baseLevel, 1);
      final PreviewMarkdownOutline outline =
          PreviewMarkdownOutline.parse('[{"level":2,"text":"a","line":1}]');
      expect(outline.indentOf(-1), 0);
      expect(outline.indentOf(99), 0);
    });
  });

  group('反查「现在读到哪一节」', () {
    final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse('['
        '{"level":1,"text":"A","line":10},'
        '{"level":2,"text":"B","line":50}'
        ']');

    test('首个标题之前算第一节（抽屉不能一条都不高亮）', () {
      expect(outline.sectionAtLine(1), 0);
      expect(outline.sectionAtLine(9), 0);
      expect(outline.sectionAtLine(0), -1); // 没有行号就没有「当前项」
      expect(PreviewMarkdownOutline.empty.sectionAtLine(3), -1);
    });

    test('标题本身与它下面的正文都算这一节', () {
      expect(outline.sectionAtLine(10), 0);
      expect(outline.sectionAtLine(49), 0); // A 与 B 之间的正文
      expect(outline.sectionAtLine(50), 1);
      expect(outline.sectionAtLine(9999), 1); // 最后一节之后的正文
    });
  });

  group('屏幕上的当前节：标题还在屏上就算它（与源码态同一判据）', () {
    // 甲 @1（1..40）、乙 @41（41..80）、丙 @81
    final PreviewMarkdownOutline outline = PreviewMarkdownOutline.parse('['
        '{"level":1,"text":"甲","line":1},'
        '{"level":2,"text":"乙","line":41},'
        '{"level":2,"text":"丙","line":81}'
        ']');

    PreviewViewport view(int top, int bottom) =>
        PreviewViewport(topLine: top, bottomLine: bottom);

    test('标题就在顶端：是它', () {
      expect(outline.sectionAtViewport(view(1, 35)), 0);
    });

    test('下一节的标题只在下半屏露头：仍算这一节', () {
      // 顶端 20 还在甲的正文里；屏幕 20..60 的中线是 40，乙的标题 41 还差一行
      expect(outline.sectionAtViewport(view(20, 60)), 0);
    });

    test('下一节的标题压在中线上：仍算这一节', () {
      // 屏幕 20..62：中线 41，正好是乙的标题行
      expect(outline.sectionAtViewport(view(20, 62)), 0);
    });

    test('下一节的标题越过中线：交给下一节', () {
      // 屏幕 20..64：中线 42，乙的标题 41 已经越过它
      expect(outline.sectionAtViewport(view(20, 64)), 1);
    });

    test('下一节的标题还没上屏：仍算这一节', () {
      expect(outline.sectionAtViewport(view(20, 40)), 0);
    });

    test('已经在乙里：就是乙（丙还没上屏）', () {
      expect(outline.sectionAtViewport(view(50, 80)), 1);
    });

    test('回执没带行号（老页面 / 空页）：返回 -1，不猜', () {
      expect(outline.sectionAtViewport(PreviewViewport.empty), -1);
      expect(outline.sectionAtViewport(const PreviewViewport(topLine: 0)), -1);
      expect(PreviewMarkdownOutline.empty.sectionAtViewport(view(5, 20)), -1);
    });
  });

  group('「这份清单换了没有」按内容比', () {
    const PreviewMarkdownOutline one = PreviewMarkdownOutline(<PreviewOutlineEntry>[
      PreviewOutlineEntry(level: 1, text: 'A', address: PreviewSourceAddress(1), id: 'a'),
      PreviewOutlineEntry(level: 2, text: 'B', address: PreviewSourceAddress(9), id: 'b'),
    ]);

    test('同一份清单重新回传（新对象）算一样 —— 重渲不该清折叠', () {
      // 别提成 const：const 会被规范化成同一个实例，那样测的就不是「新对象」
      final PreviewMarkdownOutline again = PreviewMarkdownOutline(<PreviewOutlineEntry>[
        const PreviewOutlineEntry(level: 1, text: 'A', address: PreviewSourceAddress(1), id: 'a'),
        const PreviewOutlineEntry(level: 2, text: 'B', address: PreviewSourceAddress(9), id: 'b'),
      ]);
      expect(identical(one, again), isFalse);
      expect(one.sameContentAs(again), isTrue);
    });

    test('标题改了 / 层级变了 / 地址变了 / 增删一节，都算换了', () {
      expect(
        one.sameContentAs(
          const PreviewMarkdownOutline(<PreviewOutlineEntry>[
            PreviewOutlineEntry(level: 1, text: 'A', address: PreviewSourceAddress(1), id: 'a'),
            PreviewOutlineEntry(level: 2, text: 'B2', address: PreviewSourceAddress(9), id: 'b'),
          ]),
        ),
        isFalse,
      );
      expect(
        one.sameContentAs(
          const PreviewMarkdownOutline(<PreviewOutlineEntry>[
            PreviewOutlineEntry(level: 3, text: 'B', address: PreviewSourceAddress(9), id: 'b'),
          ]),
        ),
        isFalse,
      );
      expect(
        one.sameContentAs(
          const PreviewMarkdownOutline(<PreviewOutlineEntry>[
            PreviewOutlineEntry(level: 1, text: 'A', address: PreviewSourceAddress(1), id: 'a'),
            PreviewOutlineEntry(level: 2, text: 'B', address: PreviewSourceAddress(10), id: 'b'),
          ]),
        ),
        isFalse,
      );
      expect(one.sameContentAs(PreviewMarkdownOutline.empty), isFalse);
    });

    test('空清单与自己一样（首帧还没收到回执时不该判成「换了」）', () {
      expect(PreviewMarkdownOutline.empty.sameContentAs(PreviewMarkdownOutline.empty), isTrue);
    });
  });

  group('模板里的钩子（静态资源）', () {
    final String html = File('assets/web/markdown_view.html').readAsStringSync();

    test('有行级滚动函数，且走 window.scrollTo（与位置还原同一套坐标）', () {
      expect(html.contains('function mdScrollToLine(line)'), isTrue);
      final String body = functionBodyOf(html, 'function mdScrollToLine(line)');
      expect(body.contains('window.scrollTo'), isTrue);
      // 跳过去之后要补报位置：读者可能马上按返回
      expect(body.contains('__mdReportAnchor'), isTrue);
    });

    test('目录跳转先放弃「按住还原」—— 否则跳过去又被拽回原位', () {
      // 无头实测（Chrome headless + 真模板）：跳到目标 top=0，400ms 后还原把页面
      // 拉回 -252px。读者看到的就是「点了目录却停在半路」，所以跳转必须取消还原。
      final String body = functionBodyOf(html, 'function mdScrollToLine(line)');
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
