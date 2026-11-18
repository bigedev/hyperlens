import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/css_color.dart';

void main() {
  group('cssHexColor：进 <style> 之前的唯一一道校验', () {
    test('四种十六进制写法原样返回', () {
      for (final String hex in <String>[
        '#fff',
        '#ffff',
        '#ffffff',
        '#ffffffff',
        '#0A1b2C',
      ]) {
        expect(cssHexColor(hex, 'background'), hex);
      }
    });

    test('破出样式块的写法被拒绝', () {
      expect(
        () => cssHexColor('#fff}</style><script>x', 'background'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('命名色 / rgb() / var() 一律拒绝：校验器没法穷举它们的语法', () {
      for (final String value in <String>[
        'red',
        'rgb(0,0,0)',
        'rgba(0,0,0,.5)',
        'var(--bg)',
        '',
        '#12345',
        '#fffff',
        ' #fff',
        '#fff ',
      ]) {
        expect(
          () => cssHexColor(value, 'background'),
          throwsA(isA<ArgumentError>()),
          reason: '应拒绝 $value',
        );
      }
    });

    test('报错里能看出是哪个参数（调用方有多个颜色入参）', () {
      expect(
        () => cssHexColor('red', 'foregroundHex'),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'foregroundHex'),
        ),
      );
    });
  });
}
