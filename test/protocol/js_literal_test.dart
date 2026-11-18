import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/protocol/js_literal.dart';

void main() {
  group('jsJson：内联进 <script> 的三个禁区', () {
    test('普通值原样（与 jsonEncode 一致）', () {
      expect(jsJson(<String, Object?>{'a': 1, 'b': 'x'}), '{"a":1,"b":"x"}');
    });

    test('</script> 被转义：不转就当场截断整段脚本', () {
      final String out = jsJson({'markdown': '</script><b>x</b>'});
      expect(out.contains('</script>'), isFalse);
      expect(out.contains('<'), isFalse);
      expect(out.contains(r'\u003c'), isTrue);
    });

    test('U+2028 / U+2029 被转义：JS 字符串字面量里它们是换行符', () {
      final String out = jsJson({'s': 'a\u2028b\u2029c'});
      expect(out.contains('\u2028'), isFalse);
      expect(out.contains('\u2029'), isFalse);
      expect(out.contains(r'\u2028'), isTrue);
      expect(out.contains(r'\u2029'), isTrue);
    });

    test('换行与回车由 jsonEncode 转义（结果里没有裸换行）', () {
      final String out = jsJson({'s': 'a\nb\rc'});
      expect(out.contains('\n'), isFalse);
      expect(out.contains('\r'), isFalse);
      expect(out.contains(r'\n'), isTrue);
      expect(out.contains(r'\r'), isTrue);
    });
  });

  group('jsSingleQuoted：单引号字面量', () {
    test('普通值原样包一层单引号', () {
      expect(jsSingleQuoted('body>div#main'), "'body>div#main'");
    });

    test('引号与反斜杠要转义', () {
      expect(jsSingleQuoted(r"a'b\c"), r"'a\'b\\c'");
    });

    test('换行必须显式转义：地址可能来自跨会话持久化', () {
      final String out = jsSingleQuoted('a\nb\rc');
      expect(out.contains('\n'), isFalse);
      expect(out.contains('\r'), isFalse);
      expect(out, r"'a\nb\rc'");
    });

    test('尖括号与 U+2028 / U+2029 与 jsJson 同一口径', () {
      final String out = jsSingleQuoted('</script>\u2028\u2029');
      expect(out.contains('<'), isFalse);
      expect(out.contains('\u2028'), isFalse);
      expect(out.contains('\u2029'), isFalse);
      expect(out.contains(r'\u003c'), isTrue);
    });

    test('反斜杠先转：顺序错了会把转义序列再转一遍', () {
      expect(jsSingleQuoted(r'\n'), r"'\\n'");
    });
  });
}
