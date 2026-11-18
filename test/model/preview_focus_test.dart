import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/asset/hyperlens_assets.dart';
import 'package:hyperlens/src/html/html_document_style.dart';
import 'package:hyperlens/src/markdown/payload.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:hyperlens/src/protocol/commands.dart';
import 'package:hyperlens/src/model/preview_focus.dart';

/// 预览侧的搜索命中定位（`lib/src/model/preview_focus.dart`）。
///
/// 这一块**在主机上只能测到这里**：`flutter_tester` 里没有 `WebViewPlatform`
/// （见 `tool/shots_gen.dart` 为什么绕开 `.md`），真正的高亮与滚动只有真机能验。
/// 所以下面钉的是另一半：喂给页面的坐标算得对、编码不会把页面弄白、
/// 以及「为定位开脚本」之前确实把作者的脚本摘掉了。
void main() {
  group('PreviewFocus.fromLineColumn：行列 → 片段 + 第几次出现', () {
    // 三行里 alpha 出现了三次，正好用来测消歧
    const String doc = '第一行 alpha\n'
        '第二行 beta alpha\n'
        '第三行 alpha';

    test('第一处命中：片段就是要亮的那几个字，序号 0', () {
      // 「第一行 alpha」：a 在第 5 个字符（1 起）
      final PreviewFocus? focus = PreviewFocus.fromLineColumn(
        text: doc,
        line: 1,
        column: 5,
        length: 5,
      );
      expect(focus, const PreviewFocus(needle: 'alpha', occurrence: 0));
    });

    test('第二处命中：同一个词，靠 occurrence 区分（否则只能滚到第一处）', () {
      // 「第二行 beta alpha」：第 5~8 是 beta，alpha 从第 10 个字符起
      final PreviewFocus? focus = PreviewFocus.fromLineColumn(
        text: doc,
        line: 2,
        column: 10,
        length: 5,
      );
      expect(focus, const PreviewFocus(needle: 'alpha', occurrence: 1));
    });

    test('第三处命中：序号累计到最后', () {
      final PreviewFocus? focus = PreviewFocus.fromLineColumn(
        text: doc,
        line: 3,
        column: 5,
        length: 5,
      );
      expect(focus, const PreviewFocus(needle: 'alpha', occurrence: 2));
    });

    test('行号 / 列号 / 长度任一不成立就不定位 —— 宁可停在开头', () {
      // 行号越界：文件在搜索之后被改短了
      expect(
        PreviewFocus.fromLineColumn(text: doc, line: 9, column: 1, length: 3),
        isNull,
      );
      // 列号越界
      expect(
        PreviewFocus.fromLineColumn(text: doc, line: 1, column: 99, length: 3),
        isNull,
      );
      // 没有精确区间（只给了行号）：整行不是一个「片段」
      expect(
        PreviewFocus.fromLineColumn(text: doc, line: 1, column: null, length: 3),
        isNull,
      );
      expect(
        PreviewFocus.fromLineColumn(text: doc, line: 1, column: 1, length: 0),
        isNull,
      );
      expect(
        PreviewFocus.fromLineColumn(text: '', line: 1, column: 1, length: 1),
        isNull,
      );
    });

    test('片段是空白就不定位：高亮一个空格既看不见也定位不到', () {
      expect(
        PreviewFocus.fromLineColumn(text: 'a  b', line: 1, column: 2, length: 2),
        isNull,
      );
    });

    test('CRLF 文档：\\r 不进片段（否则 JS 侧永远找不到这段文字）', () {
      // 行尾的 \r 落在列区间里时直接判为不可信
      expect(
        PreviewFocus.fromLineColumn(
          text: 'a\r\nb\r\n',
          line: 1,
          column: 2,
          length: 1,
        ),
        isNull,
      );
      // 正常位置不受影响
      expect(
        PreviewFocus.fromLineColumn(
          text: 'a\r\nbeta\r\n',
          line: 2,
          column: 1,
          length: 4,
        ),
        const PreviewFocus(needle: 'beta', occurrence: 0),
      );
    });

    test('片段跨到行尾之外会被裁到行尾（搜索命中从不跨行）', () {
      final PreviewFocus? focus = PreviewFocus.fromLineColumn(
        text: 'abc\ndef',
        line: 1,
        column: 2,
        length: 99,
      );
      expect(focus, const PreviewFocus(needle: 'bc', occurrence: 0));
    });
  });

  group('载荷：focus 只在该有时出现', () {
    test('带命中时载荷里有 focus，键与页面约定一致', () {
      final String payload = buildMarkdownPayload(
        markdown: 'x',
        dark: false,
        fontSize: 16,
        token: '1:1',
        restore: PreviewPosition.top,
        focus: const PreviewFocus(needle: 'alpha', occurrence: 3),
      );
      final Map<String, Object?> json = jsonDecode(payload) as Map<String, Object?>;
      expect(json['focus'], <String, Object?>{
        'needle': 'alpha',
        'occurrence': 3,
      });
    });

    test('没有命中时载荷里连键都没有（页面靠它判断要不要定位）', () {
      final String payload = buildMarkdownPayload(
        markdown: 'x',
        dark: false,
        fontSize: 16,
        token: '1:1',
        restore: PreviewPosition.top,
      );
      expect(payload.contains('"focus"'), isFalse);
    });

    test('片段里带 < 也安全：内联进 <script> 不会被当成标签', () {
      final String payload = buildMarkdownPayload(
        markdown: 'x',
        dark: false,
        fontSize: 16,
        token: '1:1',
        restore: PreviewPosition.top,
        focus: const PreviewFocus(needle: '</script>', occurrence: 0),
      );
      expect(payload.contains('<'), isFalse);
      expect(payload.contains(r'\u003c'), isTrue);
      // 转义回来的仍是原片段
      final Map<String, Object?> json =
          jsonDecode(payload.replaceAll(r'\u003c', '<')) as Map<String, Object?>;
      expect(
        (json['focus']! as Map<String, Object?>)['needle'],
        '</script>',
      );
    });
  });

  group('页面脚本', () {
    test('forFocus 是「脚本 + 调用」一整段：定义在前、调用在后', () {
      final String script = HyperlensCommands.forFocus(
        const PreviewFocus(needle: 'alpha', occurrence: 0),
      );
      expect(script.contains('hyperLensApplyFocus'), isTrue);
      expect(script.contains('hyperLensClearFocus'), isTrue);
      expect(script.contains('createTreeWalker'), isTrue);
      // 调用在定义之后：页面顺序执行，反了就「函数未定义」
      expect(
        script.lastIndexOf('hyperLensApplyFocus(') >
            script.indexOf('function hyperLensApplyFocus'),
        isTrue,
      );
    });

    test('forFocus 里的参数已编码：`<` 与引号都不能原样出现', () {
      final String script = HyperlensCommands.forFocus(
        const PreviewFocus(needle: 'a"b<c', occurrence: 2),
      );
      final String call = script.substring(script.lastIndexOf('hyperLensApplyFocus('));
      expect(call.contains('"occurrence":2'), isTrue);
      // `<` 会被解析成标签，`"` 会截断 JSON
      expect(call.contains('<'), isFalse);
      expect(call.contains(r'\u003c'), isTrue);
      expect(call.contains(r'\"'), isTrue);
    });

    test('真模板：焦点脚本有占位符，且渲染成功后才应用', () {
      final String template =
          File('assets/web/markdown_view.html').readAsStringSync();
      expect(template.contains('/*__FOCUS_JS__*/'), isTrue);
      expect(template.contains('hyperLensApplyFocus(payload.focus)'), isTrue);
      // 位置回执要报在命中处，所以定位必须早于 mdWatchAnchor 的那段流程
      expect(
        template.indexOf('hyperLensApplyFocus(payload.focus)') <
            template.indexOf('mdWatchAnchor(payload.token)'),
        isTrue,
      );
      // 有命中就不做位置还原：mdHold 会在 1.5s 内反复落位，与命中定位抢滚动条
      expect(template.contains('if (payload.restore && !payload.focus)'), isTrue);
    });

    test('模板替换会把焦点脚本内联进页面（占位符不能剩下）', () async {
      Future<String> load(String path) async => switch (path) {
            HyperlensAssets.markdownViewHtml =>
              '<script>/*__FOCUS_JS__*/</script><script>/*__PAYLOAD__*/</script>',
            _ => 'X',
          };
      final String html = await buildMarkdownHtml(
        load: load,
        dark: false,
        background: '#ffffff',
        foreground: '#1f2328',
        border: '#d0d7de',
        payload: '{}',
        markdown: '',
      );
      expect(html.contains('function hyperLensApplyFocus'), isTrue);
      expect(html.contains('/*__FOCUS_JS__*/'), isFalse);
    });
  });

  group('高亮配色（真机踩到：墨主题原来是白底，等于看不见）', () {
    test('Markdown：覆盖主题那三档 mark，且排在主题 CSS 之后', () {
      final String template =
          File('assets/web/markdown_view.html').readAsStringSync();
      expect(template.contains('.markdown-body mark[data-hyperlens-focus]'), isTrue);
      // 同一份 <style> 里，主题 CSS 占位符在前；反过来就会被
      // `.markdown-body mark`（0,1,1）之外的更具体规则抢回去
      expect(
        template.indexOf('.markdown-body mark[data-hyperlens-focus]') >
            template.indexOf('/*__MD_THEME_CSS__*/'),
        isTrue,
      );
    });

    test('墨主题：灰底 + 描边（它的 `mark` 底色本来就是白纸色）', () {
      final String ink = File('assets/web/md-ink.css').readAsStringSync();
      expect(ink.contains('.markdown-body mark[data-hyperlens-focus]'), isTrue);
      expect(
        RegExp(r'mark\[data-hyperlens-focus\]\s*\{[^}]*#d9d9d9').hasMatch(ink),
        isTrue,
      );
    });
  });

  group('HTML 预览：开脚本前先摘掉作者的代码', () {
    test('<script> 整段消失，普通标签与属性原样留着', () {
      const String page = '<html><head><script>alert(1)</script></head>'
          '<body><a href="a.html" class="x">链接</a>'
          '<img src="pic.png" data-id="7"></body></html>';
      final String clean = stripAuthorScripts(page);
      expect(clean.contains('<script'), isFalse);
      expect(clean.contains('alert(1)'), isFalse);
      expect(clean.contains('href="a.html"'), isTrue);
      expect(clean.contains('class="x"'), isTrue);
      expect(clean.contains('data-id="7"'), isTrue);
    });

    test('内联事件三种引号写法都摘掉 —— 脚本一开它们就能读同源文件', () {
      const String page = '<body onload="boot()">'
          "<a onclick='go()'>a</a>"
          '<b onmouseover=hover()>b</b>'
          '<i ondblclick="x()">i</i></body>';
      final String clean = stripAuthorScripts(page).toLowerCase();
      expect(clean.contains('onload'), isFalse);
      expect(clean.contains('onclick'), isFalse);
      expect(clean.contains('onmouseover'), isFalse);
      expect(clean.contains('ondblclick'), isFalse);
    });

    test('自闭合 script、正文里的 <script 字样都不许把后面内容吃掉（那是白屏）',
        () {
      // 自闭合写法：曾经的「没闭合就删到文档末尾」兜底会连 after 一起删掉
      const String selfClosing = '<p>before</p><script src="a.js"/><p>after</p>';
      expect(stripAuthorScripts(selfClosing).contains('after'), isTrue);

      // 教程类文档常把标签当文字写；`<script` 后面根本没有配对的 `</script>`
      const String tutorial =
          '<pre>&lt;script&gt; 的用法：<script 开头</pre><p>after</p>';
      expect(stripAuthorScripts(tutorial).contains('after'), isTrue);
    });

    // 真机回归：看图页（`scripts: true`）整份 html 都是我们自己生成的，
    // 桥脚本就写在里面 —— 一律摘掉的话 `bzZoom` / `say()` 全没了，缩放按钮点了不动、
    // 横滑与双击也不回报，整屏只剩静态图。所以摘不摘要按「是不是别人的页面」判。
    test('自有页面（看图）不摘脚本：那份 html 里的脚本就是我们的桥', () {
      expect(stripsAuthorScripts(ownPage: true), isFalse);
    });

    test('作者页面为定位 / 阅读位置开脚本时才摘', () {
      expect(stripsAuthorScripts(focus: true), isTrue);
      expect(stripsAuthorScripts(restore: true), isTrue);
      expect(stripsAuthorScripts(anchor: true), isTrue);

      // 脚本全关：本来就不跑，摘不摘都无所谓 —— 判定为 false（省一次替换）
      expect(stripsAuthorScripts(), isFalse);
    });

    test('真实模板过一遍：结构还在，只有成对的 script 被摘掉', () {
      final String template =
          File('assets/web/markdown_view.html').readAsStringSync();
      final String clean = stripAuthorScripts(template);
      expect(clean.contains('</script>'), isFalse, reason: '成对的都摘干净了');
      // 白屏的判据：正文容器与文档结尾都还在
      expect(clean.contains('id="content"'), isTrue);
      expect(clean.contains('</html>'), isTrue);
    });

    test('注入的脚本挂在 </body> 之前；没有 body 就追加末尾', () {
      expect(
        injectScriptIntoHtml('<html><body>x</body></html>', 'S()'),
        '<html><body>x<script>S()</script></body></html>',
      );
      expect(
        injectScriptIntoHtml('<html><BODY>x</BODY></html>', 'S()'),
        '<html><BODY>x<script>S()</script></BODY></html>',
      );
      expect(injectScriptIntoHtml('<p>x</p>', 'S()'), '<p>x</p><script>S()</script>');
    });
  });
}
