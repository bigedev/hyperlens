import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/code_anchor.dart';

/// 源码视图的阅读位置（`CodeAnchor`）。
///
/// 两个要点：
/// - **换字号后落回同一行**：偏移按字号比例缩放（行高与字号成正比）；
/// - **认不出来的数据当没记**：宁可回到顶部，也不要跳到一个随机位置。
void main() {
  group('按字号换算偏移', () {
    test('字号没变：原样返回', () {
      const CodeAnchor anchor = CodeAnchor(offset: 1200, fontSize: 14);
      expect(anchor.resolveOffset(14), 1200);
    });

    test('字号变大：偏移等比放大（停在原来那一行）', () {
      const CodeAnchor anchor = CodeAnchor(offset: 1200, fontSize: 14);
      expect(anchor.resolveOffset(21), 1800, reason: '1200 × 21/14');
    });

    test('字号变小：偏移等比缩小', () {
      const CodeAnchor anchor = CodeAnchor(offset: 1800, fontSize: 21);
      expect(anchor.resolveOffset(14), 1200);
    });

    test('字号未知（0）：原样返回，不做除法', () {
      const CodeAnchor anchor = CodeAnchor(offset: 640, fontSize: 0);
      expect(anchor.resolveOffset(14), 640);
    });

    test('当前字号未知：同样原样返回', () {
      const CodeAnchor anchor = CodeAnchor(offset: 640, fontSize: 14);
      expect(anchor.resolveOffset(0), 640);
    });

    test('顶部恒为 0', () {
      expect(CodeAnchor.top.resolveOffset(30), 0);
    });
  });

  group('序列化', () {
    test('往返：偏移与字号都在', () {
      const CodeAnchor anchor = CodeAnchor(offset: 812.5, fontSize: 18);
      final CodeAnchor? parsed = CodeAnchor.tryParse(anchor.toJson());

      expect(parsed, anchor);
    });

    test('也接受 JSON 字符串（两边共用一套读写）', () {
      expect(
        CodeAnchor.tryParse('{"offset": 300, "fontSize": 16}'),
        const CodeAnchor(offset: 300, fontSize: 16),
      );
    });

    test('缺 fontSize：按「未知」处理，偏移照样可用', () {
      expect(
        CodeAnchor.tryParse(<String, Object?>{'offset': 300}),
        const CodeAnchor(offset: 300, fontSize: 0),
      );
    });

    test('缺 offset / 不是 map / 坏 JSON：一律 null（= 回到顶部）', () {
      expect(CodeAnchor.tryParse(<String, Object?>{'fontSize': 14}), isNull);
      expect(CodeAnchor.tryParse(42), isNull);
      expect(CodeAnchor.tryParse(null), isNull);
      expect(CodeAnchor.tryParse('{不是 json'), isNull);
    });
  });

  group('源码行号：与预览交接的公共坐标', () {
    test('往返：行号跟着一起走', () {
      const CodeAnchor anchor =
          CodeAnchor(offset: 812.5, fontSize: 18, line: 240);
      final CodeAnchor? parsed = CodeAnchor.tryParse(anchor.toJson());
      expect(parsed, anchor);
      expect(parsed!.line, 240);
    });

    test('行号算不出来（0）时不写这个键（老记忆的形状不变）', () {
      const CodeAnchor anchor = CodeAnchor(offset: 120, fontSize: 14);
      expect(anchor.toJson().containsKey('line'), isFalse);
    });

    test('老数据没有行号：按 0 处理，仍按像素偏移还原', () {
      final CodeAnchor? parsed =
          CodeAnchor.tryParse('{"offset": 300, "fontSize": 16}');
      expect(parsed?.line, 0);
      expect(parsed?.resolveOffset(16), 300);
    });
  });
}
