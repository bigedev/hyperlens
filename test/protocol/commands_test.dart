import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:hyperlens/src/protocol/commands.dart';

void main() {
  group('滚动原语：地址类型决定用哪条，调用方不判断', () {
    test('源码行 → mdScrollToLine', () {
      expect(
        HyperlensCommands.forPosition(const SourceAddress(42)),
        'mdScrollToLine(42)',
      );
    });

    test('DOM 路径 → hyperLensScrollToPath', () {
      expect(
        HyperlensCommands.forPosition(const DomAddress('body>div#main>p:nth(3)')),
        "hyperLensScrollToPath('body>div#main>p:nth(3)')",
      );
    });

    test('行号非法（0 / 负）按 1 处理：页面里没有第 0 行', () {
      expect(HyperlensCommands.scrollToLine(0), 'mdScrollToLine(1)');
      expect(HyperlensCommands.scrollToLine(-5), 'mdScrollToLine(1)');
    });

    test('路径里的引号 / 反斜杠 / 尖括号要转义（内联进 <script> 会出事）', () {
      expect(
        HyperlensCommands.scrollToPath("a'b\\c<d"),
        r"hyperLensScrollToPath('a\'b\\c\u003cd')",
      );
    });
  });
}
