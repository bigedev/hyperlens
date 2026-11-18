import 'package:hyperlens/src/markdown/extras.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染增强门控（`markdown_extras.dart`）。
///
/// 这条判据的直接后果是「要不要内联 0.66 MB 的 KaTeX」：漏判会让公式原样露出来
/// （读者会当成渲染坏了），多判只是多加载一份不会被执行的脚本。所以下面同时钉住
/// 「该判有」和「不该判有」两侧 —— 后者是避免中文正文里的价格、代码块里的示例
/// 把整篇拖成慢渲染。
void main() {
  group('math 判据', () {
    test('行内 \$…\$ 判有', () {
      expect(detectMarkdownExtras('质能方程 \$E=mc^2\$ 成立').math, isTrue);
      expect(detectMarkdownExtras('\$a + b\$ 也行').math, isTrue);
    });

    test('块级 \$\$…\$\$ 与 \\[…\\] 判有', () {
      expect(
        detectMarkdownExtras('前文\n\n\$\$\n\\frac{1}{2}\n\$\$\n').math,
        isTrue,
      );
      expect(detectMarkdownExtras(r'\[ a^2 + b^2 = c^2 \]').math, isTrue);
      expect(detectMarkdownExtras(r'\(x_1\)').math, isTrue);
    });

    test('化学式靠定界符判（\\ce 自己不算）', () {
      expect(detectMarkdownExtras(r'$\ce{H2SO4}$').math, isTrue);
      expect(
        detectMarkdownExtras(r'\ce{H2SO4}').math,
        isFalse,
        reason: '没有公式定界符时 \\ce 只是普通文本，与命令行一致',
      );
    });

    test('中文价格（结尾贴空白）不判有', () {
      expect(
        detectMarkdownExtras('价格 \$5 到 \$10，按需购买').math,
        isFalse,
        reason: '与模板里的渲染判据同一口径：首尾贴空白不算公式',
      );
      expect(detectMarkdownExtras(r'转义写法 \$x\$').math, isFalse);
      expect(detectMarkdownExtras('只有一个 \$ 符号').math, isFalse);
    });

    test('围栏代码块里的 \$x\$ 不判有', () {
      const String md = '示例：\n\n```dart\nfinal s = "\$x\$";\n```\n\n完。';
      expect(detectMarkdownExtras(md).math, isFalse);
    });

    test('波浪线围栏同样剥掉', () {
      const String md = '~~~\n\$\$\nx\n\$\$\n~~~\n';
      expect(detectMarkdownExtras(md).math, isFalse);
    });

    test('行内代码里的 \$x\$ 不判有', () {
      expect(detectMarkdownExtras('写作 `` `\$x\$` `` 即可').math, isFalse);
      expect(detectMarkdownExtras('写作 `\$x\$` 即可').math, isFalse);
    });
  });

  group('mermaid 判据', () {
    test('```mermaid 围栏判有', () {
      expect(
        detectMarkdownExtras('```mermaid\ngraph TD;\nA-->B;\n```\n').mermaid,
        isTrue,
      );
      expect(
        detectMarkdownExtras('~~~mermaid\nsequenceDiagram\n~~~\n').mermaid,
        isTrue,
      );
      expect(
        detectMarkdownExtras('> ```mermaid\n> graph TD;\n> ```\n').mermaid,
        isTrue,
        reason: '引用块里的围栏也是围栏',
      );
    });

    test('别的语言围栏不判有', () {
      expect(detectMarkdownExtras('```dart\nvoid main() {}\n```').mermaid,
          isFalse);
      expect(
        detectMarkdownExtras('```\nmermaid\n```').mermaid,
        isFalse,
        reason: '没写 info string 的围栏不是 mermaid（内容里出现这个词不算）',
      );
    });

    test('围栏里的公式不算正文公式：图内公式吃的是 Mermaid 自带的那份 KaTeX', () {
      // 「图内公式探针」那篇正是这个形态：公式全在图里，正文一处也没有。
      // 判成 math 只会白内联 0.66 MB 的 KaTeX + mhchem + katex.css —— 图内公式由
      // Mermaid 自己渲染成 MathML（不依赖 katex.css），一行都用不上。
      const String md = '# 探针\n\n'
          '```mermaid\n'
          'graph LR\n'
          r'    A["$$E=mc^2$$"] --> B["价格 $5 到 $10"]'
          '\n```\n';
      final MarkdownExtras extras = detectMarkdownExtras(md);
      expect(extras.mermaid, isTrue);
      expect(extras.math, isFalse);
      expect(extras.toString(), 'extras=mermaid');
    });

    test(r'围栏里的 \(…\) / \[…\] 也不判有', () {
      expect(
        detectMarkdownExtras('```mermaid\ngraph LR\n'
                r'A[r"\[x^2\]"]'
                '\n```\n')
            .math,
        isFalse,
      );
      expect(
        detectMarkdownExtras('~~~mermaid\nsequenceDiagram\n'
                r'Note right of A: \(y\)'
                '\n~~~\n')
            .math,
        isFalse,
      );
    });

    test('正文与图里都有公式时，两个判据各判各的', () {
      const String md = r'$$x$$' '\n\n'
          '```mermaid\ngraph LR\n'
          r'A["$$y$$"]'
          '\n```\n';
      final MarkdownExtras extras = detectMarkdownExtras(md);
      expect(extras.math, isTrue, reason: '正文那块要 KaTeX');
      expect(extras.mermaid, isTrue);
      expect(extras.toString(), 'extras=math+mermaid');
    });
  });

  group('组合与边界', () {
    test('都没有时是 none，且 toString 说清楚', () {
      final MarkdownExtras extras = detectMarkdownExtras('# 标题\n\n正文。');
      expect(extras.any, isFalse);
      expect(extras.math, isFalse);
      expect(extras.mermaid, isFalse);
      expect(extras.toString(), 'extras=none');
    });

    test('两者都有时都能报出来', () {
      final MarkdownExtras extras = detectMarkdownExtras(
        '\$\$x\$\$\n\n```mermaid\ngraph TD;\n```\n',
      );
      expect(extras.math, isTrue);
      expect(extras.mermaid, isTrue);
      expect(extras.toString(), 'extras=math+mermaid');
    });

    test('空文档不炸', () {
      expect(detectMarkdownExtras('').any, isFalse);
    });

    test('未闭合的围栏：整段当代码，公式不判有', () {
      expect(detectMarkdownExtras('```\n\$x\$').math, isFalse);
    });
  });
}
