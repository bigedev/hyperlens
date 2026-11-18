import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/html/html_tag_scan.dart';
import 'package:hyperlens/src/model/preview_syntax.dart';

/// HTML 标签扫描（`html_tag_scan.dart`）。
///
/// 只看源码文本：浏览器的 `document` 已经把错误修好了，树里没有痕迹。所以
/// 这些用例全部是「给一段源码，看能不能说出哪一行写错了」。
void main() {
  group('不报错的写法', () {
    test('正常 HTML：自闭合、void 元素、允许省略结尾的标签都不报', () {
      const String html = '<div>\n'
          '  <img src="a.png">\n'
          '  <br>\n'
          '  <ul><li>一<li>二</ul>\n'
          '  <p>段落\n'
          '  <table><tr><td>格子</table>\n'
          '</div>';

      expect(scanHtmlTagIssues(html), isEmpty);
    });

    test('属性值里有 `>`：标签边界按引号算，不把 `>` 当成标签结束', () {
      const String html = '<div title="a > b">\n'
          '  <span data-x=\'c > d\'>正文</span>\n'
          '</div>';

      expect(scanHtmlTagIssues(html), isEmpty);
      // 反过来验一次：真漏了闭合也照样能发现（说明确实扫到了这两个标签）
      expect(
        scanHtmlTagIssues('<div title="a > b"><span>x</div>'),
        hasLength(1),
      );
    });

    test('script 内容里的 `<` 不算标签，结束标签也不误报', () {
      const String html = '<div>\n'
          '<script>\n'
          'if (a < b && c > d) { /* <div> */ }\n'
          '</script>\n'
          '</div>';

      expect(scanHtmlTagIssues(html), isEmpty);
    });

    test('注释与 CDATA 里的标签不参与结构', () {
      const String html = '<div>\n'
          '<!-- <span> 是坏的，但在注释里 -->\n'
          '<![CDATA[ </p> ]]>\n'
          '</div>';

      expect(scanHtmlTagIssues(html), isEmpty);
    });

    test('空文档 / 纯文本：没有问题可报', () {
      expect(scanHtmlTagIssues(''), isEmpty);
      expect(scanHtmlTagIssues('只有文字，没有标签'), isEmpty);
    });
  });

  group('硬错', () {
    test('多出来的结束标签：报它自己那一行', () {
      final List<PreviewSyntaxIssue> issues =
          scanHtmlTagIssues('<div>\n</div>\n</div>');

      expect(issues, hasLength(1));
      expect(issues.single.kind, PreviewSyntaxIssueKind.unclosedTag);
      expect(issues.single.line, 3);
      expect(issues.single.detail, contains('</div>'));
    });

    test('嵌套写错：报上面那个没关的，落到它开始的行', () {
      final List<PreviewSyntaxIssue> issues =
          scanHtmlTagIssues('<div>\n  <span>文字\n</div>');

      expect(issues, hasLength(1));
      expect(issues.single.line, 2, reason: '问题在 span 那一行');
      expect(issues.single.detail, contains('<span>'));
    });

    test('到文件结尾都没关：报一次，落到开始行', () {
      final List<PreviewSyntaxIssue> issues =
          scanHtmlTagIssues('<div>\n  <section>\n    文字\n  </section>');

      expect(issues, hasLength(1));
      expect(issues.single.line, 1);
      expect(issues.single.detail, contains('<div>'));
    });

    test('script 没有结束标签：报一次并停止（后面的内容结构不可信）', () {
      final List<PreviewSyntaxIssue> issues =
          scanHtmlTagIssues('<script>\nvar a = 1;');

      expect(issues, hasLength(1));
      expect(issues.single.line, 1);
      expect(issues.single.detail, contains('<script>'));
    });

    test('最多报 maxIssues 条：一份烂到底的文档不该刷满面板', () {
      final List<PreviewSyntaxIssue> issues =
          scanHtmlTagIssues('</div>' * 60, maxIssues: 5);

      expect(issues, hasLength(5));
      expect(scanHtmlTagIssues('</div>' * 60, maxIssues: 0), isEmpty);
    });
  });
}
