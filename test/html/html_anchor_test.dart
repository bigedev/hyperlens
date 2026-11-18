import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/model/preview_position.dart';
import 'package:flutter_test/flutter_test.dart';

/// HTML 预览的阅读位置通道（`html_anchor.dart`）。
///
/// 这些逻辑在主机上能全部钉住：**注入什么脚本**、**回执怎么解析**都是纯字符串，
/// 不需要 WebView。
void main() {
  group('注入脚本', () {
    test('null 也要显式落回顶部（否则新文件继承上一篇的滚动位置）', () {
      expect(
        htmlAnchorScript(null),
        contains('hyperLensAnchorHold({"path":"body"})'),
      );
    });

    test('带位置：脚本跑时落一次、load 之后再按一次（图片撑高会漂）', () {
      final String js = htmlAnchorScript(
        const PreviewDomAddress('body>div#main>h2:nth(2)'),
      );
      expect(
        'hyperLensAnchorHold({"path":"body>div#main>h2:nth(2)"})'.allMatches(js),
        hasLength(2),
      );
      expect(js, contains("window.addEventListener('load'"));
    });

    test('拿到源码行地址（不该发生在 HTML 页上）时按顶部处理，不瞎跳', () {
      expect(
        htmlAnchorScript(const PreviewSourceAddress(42)),
        contains('hyperLensAnchorHold({"path":"body"})'),
      );
    });

    test('路径的生成 / 解析 / 视口顶端三点都在脚本里（地址的整套依据）', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('function hyperLensPathOf('));
      expect(js, contains('function hyperLensByPath('));
      expect(js, contains('function hyperLensPathSeg('));
      expect(js, contains('function hyperLensTopElement('));
      // 吸顶栏会挡住「顶端那一点」，跳转与还原都要补偿
      expect(js, contains('function hyperLensStickyInset('));
    });

    test('上报节流、手势接管、点链接前补一枪都在脚本里', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('hyperLensAnchorSchedule(250)'));
      expect(js, contains("addEventListener('touchstart'"));
      expect(js, contains("addEventListener('click'"));
    });

    test('通道名注入：默认 HyperLens，占位符必须被替换干净', () {
      // 占位符残留 = `window.__HYPERLENS_CHANNEL__` 恒为 undefined，位置通道静默哑掉
      expect(htmlAnchorScript(null), contains('window.HyperLens.postMessage'));
      expect(htmlAnchorScript(null), isNot(contains('__HYPERLENS_CHANNEL__')));

      // 自定义名只需是「别的名字」：这条不锁某个应用，只证明参数进了脚本、
      // 且默认名没有跟着一起注入（两处都注入 = 通道注册两次）。
      final String host = htmlAnchorScript(null, channelName: 'HostChannel');
      expect(host, contains('window.HostChannel.postMessage'));
      expect(host, isNot(contains('window.HyperLens')));
    });

    test('通道名不是合法标识符：当场抛错（否则整段脚本语法错、整条通道废掉）', () {
      expect(
        () => htmlAnchorScript(null, channelName: 'Big-E'),
        throwsArgumentError,
      );
    });

    test('落位只有一条路：有路径按节点，找不到就回顶部（没有像素兜底）', () {
      final int at = htmlAnchorScript(null).indexOf('function hyperLensAnchorRestore');
      final String body = htmlAnchorScript(null).substring(at, at + 600);
      expect(body.contains('window.scrollTo(0, 0)'), isTrue);
      expect(body.contains('a.scrollY'), isFalse);
    });

    test('目录跳转后记住「点的就是这一条」（末尾几节顶不到顶端）', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('hyperLensSectionClamp'));
      expect(js, contains('function hyperLensScrollToPath('));
    });

    test('折叠里的标题不算章节 —— `<details>` 收起时 rects 非空、但点不到', () {
      // 2026-11-18 实测（notes/html/anchor-probe.html）：只判 getClientRects() 会把
      // 收起的小节收进抽屉，读者点了滚不过去。可见性必须再查祖先 details。
      final String js = htmlAnchorScript(null);
      expect(js, contains('function hyperLensVisible('));
      final int at = js.indexOf('function hyperLensVisible(');
      expect(js.substring(at, at + 400), contains("node.tagName === 'DETAILS'"));
    });

    test('顶端探测点在吸顶栏之下 12px（贴在边沿会退到上一块）', () {
      final String js = htmlAnchorScript(null);
      final int at = js.indexOf('function hyperLensTopElement(');
      final String body = js.substring(at, at + 500);
      expect(body, contains('hyperLensStickyInset()'));
      expect(body, contains('probeY'));
    });

    test('章节检索：h 标签之外认 ARIA 语义标题，同一节点只收一条', () {
      final String js = htmlAnchorScript(null);
      // 并集选择器：同时是 <h3> 又带 role="heading" 的元素由 querySelectorAll
      // 只返回一次，清单里不会出现两条同名条目
      expect(js, contains('h1, h2, h3, h4, h5, h6, [role="heading"], [aria-level]'));
      expect(js, contains('function hyperLensSectionLevel('));
      // 标题套标题只留外层（内层落点与外层相差不到一行）
      expect(js, contains('function hyperLensInsideHeading('));
      expect(js, contains('if (hyperLensInsideHeading(el)) { continue; }'));
      // 层级优先级：标签 → aria-level（缺省 2，超过 6 按 6）
      final int at = js.indexOf('function hyperLensSectionLevel(');
      final String body = js.substring(at, at + 420);
      expect(body, contains("tag.charAt(0) === 'H'"));
      expect(body, contains("getAttribute('aria-level')"));
      expect(body, contains('return 2;'));
      expect(body, contains('aria > 6 ? 6 : aria'));
    });

    test('清单缓存按文档尺寸失效（重排后必须重扫）', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('function hyperLensInvalidateSections('));
      expect(js, contains('hyperLensInvalidateSections(); hyperLensSectionsPost();'));
    });

    test('折叠展开 / 图片撑开要能重扫：load 与 resize 都不会触发', () {
      // 实测（2026-11-18，aria-heading-probe.html）：展开 <details> 后抽屉一直停在
      // 7 条 —— 宽度没变不触发 resize、load 早过了。必须盯文档高度。
      final String js = htmlAnchorScript(null);
      expect(js, contains('function hyperLensWatchResize('));
      expect(js, contains('new ResizeObserver('));
      expect(js, contains('observer.observe(document.body)'));
      // 注入时就该开始观察（不能等读者先滚一下）；语法树一篇一次，排在中间
      expect(
        js,
        contains('hyperLensSectionsPost();\n'
            'hyperLensSyntaxPost();\n'
            'hyperLensWatchResize();'),
      );
      // 回调里要先失效缓存，否则 hyperLensSections() 会把旧清单原样返回
      final int at = js.indexOf('function hyperLensWatchResize(');
      final String body = js.substring(at, at + 900);
      expect(body, contains('hyperLensInvalidateSections();'));
      expect(body, contains('hyperLensSectionsPost();'));
    });
  });
}
