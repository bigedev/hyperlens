import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/model/preview_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

/// HTML 预览的阅读位置通道（`html_anchor.dart`）。
///
/// 这些逻辑在主机上能全部钉住：**注入什么脚本**、**回执怎么解析**都是纯字符串，
/// 不需要 WebView（`flutter_tester` 里也没有 WebViewPlatform，见 R131）。
void main() {
  group('回执解析', () {
    test('scroll <JSON> → PreviewAnchor（block = -1，只有像素）', () {
      expect(
        parseHtmlAnchorReport('scroll {"block":-1,"offset":0,"scrollY":420}'),
        const PreviewAnchor(block: -1, offset: 0, scrollY: 420),
      );
    });

    test('不是位置回执：返回 null（看图页的 imageReady 之类照旧交给调用方）', () {
      expect(parseHtmlAnchorReport('imageReady 1'), isNull);
      expect(parseHtmlAnchorReport(''), isNull);
      expect(parseHtmlAnchorReport('top token {"block":0,"scrollY":1}'), isNull,
          reason: 'Markdown 的 top 前缀是另一条通道，别混进来');
    });

    test('坏 JSON / 缺关键字段：当「没有位置」，不要跳到随机偏移', () {
      expect(parseHtmlAnchorReport('scroll {不是 json'), isNull);
      expect(parseHtmlAnchorReport('scroll {"block":-1}'), isNull);
    });
  });

  group('注入脚本', () {
    test('null 也要显式落回顶部（否则新文件继承上一篇的滚动位置）', () {
      expect(
        htmlAnchorScript(null),
        contains('hyperLensAnchorHold({"block":-1,"offset":0.0,"scrollY":0.0})'),
      );
    });

    test('带位置：脚本跑时落一次、load 之后再按一次（图片撑高会漂）', () {
      final String js = htmlAnchorScript(
        const PreviewAnchor(block: -1, offset: 0, scrollY: 1234),
      );
      expect(
        'hyperLensAnchorHold({"block":-1,"offset":0.0,"scrollY":1234.0})'
            .allMatches(js),
        hasLength(2),
      );
      expect(js, contains("window.addEventListener('load'"));
    });

    test('上报节流、手势接管、点链接前补一枪都在脚本里', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('window.HyperLens.postMessage'));
      expect(js, contains('hyperLensAnchorSchedule(250)'));
      expect(js, contains("addEventListener('touchstart'"));
      expect(js, contains("addEventListener('click'"));
    });

  });
}
