/// HTML 预览的样式注入（纯逻辑，可单测）。
///
/// 为什么单独一个文件：这是「往别人的文档里塞东西」的操作，位置规则有个**硬约束**
/// （见 [injectStyleIntoHtml] 的注释：插到 doctype 之前会让浏览器退回怪异模式），
/// 而它又没有 UI 可点 —— 抽出来才能用单测钉住，别指望真机上肉眼发现。
library;

/// 整页缩放的基准字号 = `中` 档的预览字号（`ViewFontSize.medium.preview`）。
///
/// 拿它当 1.0 的理由：HTML 是「看别人的页面」，默认档就该**原样呈现作者的设计**，
/// 不该像 Markdown 那样由我们替它定字号；小 / 大 两档再按比例缩。
const double kHtmlZoomBaseFontSize = 16;

/// 预览字号（逻辑像素）→ 整页缩放系数。
///
/// 用「缩放」而不是「改 `font-size`」：作者可能写死 `px`（改根字号对它们无效），
/// 也可能用 `rem` / `em`（改根字号只会影响前者之外的相对单位、比例关系还可能被
/// 破坏）。缩放是**整页等比**的，两种写法一起跟着变，作者的比例设计也不变形。
/// 缩放走 CSS `zoom` —— 在 Blink 里它是**参与布局**的（会重排，不是只放大画面），
/// 所以文字放大会自动换行、不会横向溢出。
///
/// 非法输入（NaN / 0 / 负数）一律回 1.0，别让一次调用失误把页面缩成空白；
/// 结果也 clamp 在 `0.5 ~ 3` —— 档位表是我们自己定的，越界只可能是调用方传错。
double htmlPreviewZoom(double previewFontSize) {
  if (!previewFontSize.isFinite || previewFontSize <= 0) {
    return 1;
  }
  return (previewFontSize / kHtmlZoomBaseFontSize).clamp(0.5, 3.0);
}

/// HTML 预览要注入的整段 CSS：底色兜底 + UA 配色档 + 整页缩放 + 链接下划线
/// （深色档另有可能提亮作者写死的整页字色，见 `liftText`）。
///
/// 各条规则的**优先级意图各不相同**，别当成并列的几条去「统一」：
/// - `html,body{background-color}`：**兜底** —— 作者声明了底色就让它赢（同 R101）；
/// - `:root{color-scheme}`：让 **UA 默认色**跟着我们的底色走（见 R118）；
/// - `body{zoom}`：作者一般不会声明，声明了也该由它赢（那是它的版面设计）；
/// - `a[href]{text-decoration:underline !important}`：**必须覆盖作者**。见 R108 ——
///   作者那句 `text-decoration:none` 等于「靠颜色区分链接」，而墨水屏没有颜色这一路，
///   下划线是唯一的形状线索。
///
///   为什么要 `!important`（**实测口径，别想当然**）：我们的选择器是 `a[href]`
///   （特异性 0,1,1），**本来就压过作者的普通 `a`（0,0,1）** —— 也就是说「只写了
///   `a{text-decoration:none}`」的文档不加 `!important` 也能赢；真正要挡的是**同 /
///   更高特异性的作者规则**：`a[href]`、`.foo a`、`#id a`，以及作者自己写的
///   `!important`。无头 Chromium 实测（Blink 与 ArkWeb / WebView 同源）：
///   作者写 `a[href]{none}` 或 `#wrap a{none}` 时，带 `!important` 计算值 = `underline`、
///   去掉立刻回 `none`。只碰装饰，颜色一律留给作者（实测作者的颜色原样保留）。
///
/// **[dark] 为什么必须有（R118）**：底色是我们按**应用主题**注入的，而页面里那些
/// 「没写 `color` 的文字」用的是 **UA 默认色**，它跟的是**系统**的
/// `prefers-color-scheme` —— 两个开关互不相干。应用切深色、系统还是浅色时，页面就
/// 成了「我们给深底、UA 给黑字」：`assets/demo-repo/code/index.html` 整页黑成一团，
/// 表现出来就是「打开后没有显示内容」（同一页切浅色主题立刻正常）。
///
/// 用 `color-scheme` 而**不是**无条件写 `color`：
/// - 它只改 UA 默认色（正文默认色、表单控件、滚动条），作者写过的 `color` 一概不碰；
/// - 无条件写 `html,body{color:…}` 会撞上「作者只声明了白底、没声明字色」的页面，
///   变成白底白字 —— 那是把一个看不见换成另一个看不见。
///
/// 所以**浅色档与墨主题一个 `color` 都不写**（作者配色原样保留），只有深色档在
/// [overrideTextColor] 成立时才接管一次。
///
/// 深色档的例外是 [overrideTextColor]（判据见 [htmlDeclaresPageBackground]）：
/// 作者没给整页声明背景时，底色是我们替他换掉的 —— 这一页的配色本来就不再保真，
/// 那么文字颜色也一并由我们接管（统一浅灰，见调用方传的 `foregroundHex`）。
/// 只提亮继承层是不够的：作者写在 `h2{color:#123}`、`.hint{color:#666}` 上的
/// 深色照样读不出来（notes 仓库 `outline/17-html.html` 就是这种）。
///
/// `!important` 是必须的：作者常写 `color-scheme: light dark`（本仓库演示页就是），
/// 语义是「两种都支持，让 UA 选」，而 UA 选的是**系统**偏好 —— 与我们的底色无关，
/// 不覆盖就继续按错的档位取默认色。残留风险（同等告知）：作者只写 `background:#fff`
/// 而完全不写 `color` 的页面，在深色档下会白底白字 —— 与浏览器「深色模式」下的表现
/// 一致，且这类页面本来就该自己声明字色。
String htmlPreviewCss({
  required String backgroundHex,
  required double zoom,
  required bool dark,
  bool ink = false,
  bool overrideTextColor = false,
  String foregroundHex = '#c4c7c5',
}) =>
    'html,body{background-color:$backgroundHex;}'
    ':root{color-scheme:${dark ? 'dark' : 'light'} !important;}'
    'body{zoom:$zoom;}'
    'a[href]{text-decoration:underline !important;text-underline-offset:2px;}'
    // 深色档接管**全部**文字颜色（判据见 [htmlDeclaresPageBackground]）。
    //
    // 为什么要连元素级一起改：底色既然是我们换的，这一页就不谈保真了。作者写死的
    // `body{color:#222}`、`h2{color:#123}`、`.hint{color:#666}` 在深底上都是「深灰
    // 看不见」，只提亮 `html,body` 那一层等于只修正文、标题仍旧发黑。
    //
    // 不写成 `*{color}`：`*` 的特异性是 (0,0,0)，遇到作者带 `!important` 的元素级
    // 规则（`h2{color:#123 !important}`）会输；`html body *` 是 (0,0,3)，多一层兜底。
    '${dark && overrideTextColor ? 'html,body{color:$foregroundHex !important;}'
        'html body *{color:$foregroundHex !important;}' : ''}'
    // 搜索命中的高亮（见 preview_focus.dart）：用属性选择器把作者自己的 `mark`
    // 摘出去，只染我们包的那一层。黄底黑字在深浅两档都醒目；墨主题整页 grayscale
    // 会把它压成灰底黑字，正好也是要的。
    //
    // 排在接管规则**之后**：黄底上的字必须是黑的，否则「接管成浅灰 + 黄底」比
    // 原来看不清还糟。特异性（0,1,1）本来就高过 `html body *`（0,0,3），顺序只是兜底。
    'mark[data-hyperlens-focus]{background:#ffe58f;color:#000 !important;border-radius:2px;}'
    // 墨主题的**唯一破例**：作者的颜色不再原样保留，整页灰化。
    //
    // 前面所有规则都刻意「颜色留给作者」，这里反过来 —— 16 级灰的屏幕上，
    // 作者靠「红=警告、绿=成功」表达的语义本来就会退化成相近的中灰，
    // 与其留半彩，不如统一成明度差（灰化后层次还在，色相信息本来也读不出）。
    // 用 `filter` 而不是 `*{color:#000}`：不动作者的语义结构，也顺带处理图片。
    '${ink ? 'html{filter:grayscale(1);}' : ''}';

/// 作者有没有给**整页**（`html` / `body` / `:root` / `*`）声明背景。
///
/// 用它决定深色档要不要接管文字颜色：
/// - 作者没管背景 ⇒ 底色是我们按主题换上去的，这一页的配色本来就不保真，
///   文字颜色也一并由我们定（统一浅灰），否则作者写死的深色字在深底上读不出来
///   （notes 仓库 `outline/17-html.html` 的 `h2{color:#123}`、`27-plain.html` 的
///   `body{color:#222}` 都是这种）；
/// - 作者管了背景（`body{background:#fff}` 之类）⇒ 那一页是自洽的白底黑字，
///   我们只补底色兜底，字色一律不碰 —— 否则就是白底白字。
///
/// 只看整页选择器：`28-sticky.html` 的 `.topbar{background:#123}` 是局部配色，
/// 不能因此认定「作者管了背景」（那样正文就漏修了）。代价也说清：本页里有白底
/// 卡片、而整页背景没声明的页面，卡片里的字会跟着变成浅灰 —— 深色档不谈保真，
/// 这是有意的取舍。
bool htmlDeclaresPageBackground(String html) {
  for (final RegExpMatch block
      in RegExp(r'<style\b[^>]*>([\s\S]*?)</style\s*>', caseSensitive: false)
          .allMatches(html)) {
    // 注释里的 `body{background:…}` 不生效，先摘掉
    final String text = block.group(1)!.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    for (final RegExpMatch rule
        in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(text)) {
      if (_isPageSelector(rule.group(1)!) && _declaresBackground(rule.group(2)!)) {
        return true;
      }
    }
  }
  for (final RegExpMatch tag in RegExp(
    r'<(?:html|body)\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html)) {
    final String element = tag.group(0)!;
    // `<body bgcolor="#fff">` 这种上古写法也算作者管了背景
    if (RegExp(r'\sbgcolor\s*=', caseSensitive: false).hasMatch(element)) {
      return true;
    }
    // 内联样式挂的就是整页那一层，本身就是一串声明，不需要选择器
    final RegExpMatch? style = RegExp(
      r'''style\s*=\s*("([^"]*)"|'([^']*)')''',
      caseSensitive: false,
    ).firstMatch(element);
    final String? css = style == null ? null : (style.group(2) ?? style.group(3));
    if (css != null && _declaresBackground(css)) {
      return true;
    }
  }
  return false;
}

/// 一串声明里有没有背景（`background` 简写与 `background-color` 都算）。
bool _declaresBackground(String declarations) => RegExp(
      r'(?:^|[;\s])background(?:-color)?\s*:',
      caseSensitive: false,
    ).hasMatch(declarations);

/// 选择器组里有没有一项命中的是整页（`html` / `body` / `:root` / `*`）。
bool _isPageSelector(String selectors) => selectors.split(',').any((String raw) {
      final String selector = raw.trim().toLowerCase();
      return selector == 'html' ||
          selector == 'body' ||
          selector == ':root' ||
          selector == '*';
    });

/// 把 [css] 作为一段 `<style>` 注入 [html]。
///
/// 位置：紧随 `<head>` 开始标签 → 没有 head 就紧随 `<!doctype>` → 两者都没有才前置。
///
/// ⚠️ **绝不能插到 doctype 之前**：doctype 前出现任何内容都会让浏览器退回**怪异模式**
/// （quirks mode），盒模型随之改变，整页变形 —— 这就是后面那两段 fallback 存在的理由。
///
/// 插在文档**靠前**是有意的：作者自己的样式在后面、优先级更高，我们只做兜底
/// （页面自己声明了底色就让它保持自己的底色，同 R101 的口径）。样式表内也一样，
/// 所以 `html,body{background}` 这种兜底规则会被作者后面的声明覆盖。
///
/// **唯一的例外是链接下划线**（调用方传进来的 CSS 里带 `!important`，见 R108）：
/// 底色是「作者没表态时替他兜底」，而链接下划线是「作者表态了也必须改」—— 因为在
/// 墨水屏上「下划线」是认出链接的唯一线索，作者那句 `text-decoration:none` 正是
/// 「靠颜色区分」的写法。`!important` 挡的是**同 / 更高特异性**的作者规则（普通
/// `a` 本来就压得过，见 `htmlPreviewCss` 的注释）。这个不对称是有意的，别当疏漏「统一」掉。
String injectStyleIntoHtml(String html, String css) {
  final String style = '<style>$css</style>';
  final RegExpMatch? head = RegExp(
    r'<head[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  if (head != null) {
    return html.replaceRange(head.end, head.end, style);
  }
  final RegExpMatch? doctype = RegExp(
    r'<!doctype[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  if (doctype != null) {
    return html.replaceRange(doctype.end, doctype.end, style);
  }
  return style + html;
}

/// 把一段**我们自己的**脚本挂到文档末尾（`</body>` 之前，没有就追加）。
///
/// 为什么挂末端而不是 `loadHtmlString` 之后 `runJavaScript`：OHOS 上没有可靠的
/// 「加载完成」回调（见 `markdown_view.dart` 的看门狗注释），早一步执行就落空。
/// 随文档一起解析执行，等于把「等页面就绪」交给浏览器自己排。
///
/// ⚠️ 调用前**必须**先用 [stripAuthorScripts] 摘掉作者的脚本：这个口子只为我们
/// 自己的脚本开（搜索命中定位见 `preview_focus.dart`、阅读位置见
/// `html_anchor.dart`），不能顺带把仓库里的任意 HTML 跑起来（原口径见 R45）。
String injectScriptIntoHtml(String html, String script) {
  final String tag = '<script>$script</script>';
  final RegExpMatch? body = RegExp(
    r'</body\s*>',
    caseSensitive: false,
  ).firstMatch(html);
  if (body != null) {
    return html.replaceRange(body.start, body.start, tag);
  }
  return '$html$tag';
}

/// 摘掉作者自己的脚本与内联事件属性（只在要为我们自己的脚本开 JS 时用）。
///
/// **为什么不直接用 DOMPurify**：HTML 预览保真优先（作者的颜色、字体、布局都得留），
/// 走白名单清洗会把整页拆成另一副样子。这里只摘「会执行代码」的两类东西：
///
/// 1. `<script>…</script>` 整段 —— 现在脚本本来就禁用，它们从没执行过，摘掉不改变
///    读者看到的画面；
/// 2. `on<事件>="…"` 内联处理器 —— 脚本一开，读者碰一下就可能触发
///    `onclick="fetch('/.git/config')"`，而预览页与回环资源服务同源（挂载仓库根），
///    足以读出凭据。
///
/// 残留风险（已评估并接受）：`<iframe srcdoc>`、`<meta http-equiv=refresh>` 之类
/// 的跳转仍要靠 `PreviewNavigationGuard` 兜底；我们只保证「不主动执行作者代码」。
String stripAuthorScripts(String html) {
  // 只摘**成对**的 `<script>…</script>`。
  //
  // 这里曾经还有一条「没有闭合标签就从 `<script` 删到文档末尾」的兜底，看起来很
  // 体贴，实际会把**整篇正文吃掉** —— 自闭合写法 `<script src="a.js"/>`、或者
  // 正文里恰好写了 `<script` 这几个字（教程、代码示例，我们自己的
  // `markdown_view.html` 就是这种），都会命中，读者看到的就是白屏。未闭合的
  // `<script>` 在浏览器里本来也会把后面吞成脚本，删不删都一样，不值得为它冒险。
  String out = html.replaceAll(
    RegExp(r'<script\b[^>]*>[\s\S]*?</script\s*>', caseSensitive: false),
    '',
  );
  // 内联事件：双引号 / 单引号 / 无引号三种写法都要管
  out = out.replaceAll(
    RegExp(
      r'''\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
      caseSensitive: false,
    ),
    '',
  );
  return out;
}

/// 这一页要不要在注入脚本前摘掉**作者的**脚本（纯判定，供单测钉住）。
///
/// 只对「别人的页面」摘：为定位 / 阅读位置而开脚本时，作者的 `<script>` 与内联
/// 事件不能跟着跑。
///
/// [ownPage] 为 true 的是**我们自己生成的页面**（看图那页）——那份 html 里的脚本
/// 就是我们的桥脚本，跟着一起摘的话缩放按钮点了不动、横滑与双击也不回报，整屏只剩
/// 静态图。所以「开着脚本」不等于「该摘」：判据是「我们要开脚本，且这页不是我们自己
/// 生成的」。
///
/// 其余开关各自代表一种「需要我们注入脚本」的能力：定位搜索命中（[focus]）、记阅读
/// 位置（[restore] / [anchor]）、章节清单（[outline]）、读到第几节（[section]）。
/// 任一为 true 就视为要开脚本。
bool stripsAuthorScripts({
  bool ownPage = false,
  bool focus = false,
  bool restore = false,
  bool anchor = false,
  bool outline = false,
  bool section = false,
}) => !ownPage && (focus || restore || anchor || outline || section);

/// 这一页在**脚本不执行**的前提下还有没有看得见的东西。
///
/// 判据：去掉注释、`<head>`、`<style>`、`<script>` 与所有标签后，还剩非空白文本；
/// 或者还剩图片类元素（`img` / `svg` / `canvas` / `video` / `hr` …）。
///
/// 为什么需要这条判据：`assets/web/markdown_view.html` 这类页面 body 里只有一个空
/// `<div id="content"></div>`（body 合计 70 多字符），正文全部由脚本渲染。预览一律
/// 不执行作者脚本（R45），于是整页纯白 —— 读者只会当成「这个文件打不开/坏了」，
/// 而真正的原因是**内容在脚本里**。调用方据此给一句说明，别让白屏自己说话。
///
/// 注意不能拿 `&nbsp;` 当内容：排版用的空段落满地都是，去掉实体后再判。
bool htmlHasVisibleContent(String html) {
  String body = html
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      // `noscript` **不**在剥离之列：脚本禁用时它的内容恰好是可见的
      .replaceAll(
        RegExp(
          r'<(head|style|script|template)\b[^>]*>[\s\S]*?</\1\s*>',
          caseSensitive: false,
        ),
        '',
      );
  // 图片类元素自己就是内容，没有文字也算「看得见」
  if (RegExp(
    r'<(img|svg|canvas|video|audio|iframe|object|embed|input|textarea|select|hr)\b',
    caseSensitive: false,
  ).hasMatch(body)) {
    return true;
  }
  final String text = body
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(
        RegExp(
          r'&(nbsp|ensp|emsp|thinsp|#160|#xa0|zwsp);',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[\s\u200b\ufeff]+'), '');
  return text.isNotEmpty;
}

/// 文档里有没有**相对**资源引用（`src` / `href` / CSS `url()`）。
///
/// 只用来决定「baseUrl 迟到时要不要重载」：没有相对引用的页面，两次提交的内容
/// 一模一样，重载只会让读者白挨一次闪烁（宿主据此决定要不要重新提交页面）。
///
/// 属性只在**标签内部**找：脚本里 `var href = a.getAttribute('href')` 这种赋值
/// 不是引用，拿整篇去扫会把「全内联的模板页」误判成有资源（踩过）。
bool htmlHasRelativeRefs(String html) {
  final RegExp attr = RegExp(
    r'''(?:src|href)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
    caseSensitive: false,
  );
  for (final RegExpMatch tag in RegExp(
    r'<[a-zA-Z][^>]*>',
  ).allMatches(html)) {
    for (final RegExpMatch match in attr.allMatches(tag.group(0)!)) {
      if (_isRelativeRef(match.group(1))) {
        return true;
      }
    }
  }
  final RegExp cssUrl = RegExp(
    r'''url\(\s*("[^"]*"|'[^']*'|[^)]*)\)''',
    caseSensitive: false,
  );
  for (final RegExpMatch match in cssUrl.allMatches(html)) {
    if (_isRelativeRef(match.group(1))) {
      return true;
    }
  }
  return false;
}

/// 这个引用要不要靠 baseUrl 解析（`#锚点`、`http:`、`data:`、`//host` 都不要）。
bool _isRelativeRef(String? raw) {
  final String value =
      (raw ?? '').trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  if (value.isEmpty || value.startsWith('#')) {
    return false;
  }
  return !RegExp(
    r'^(?:[a-z][a-z0-9+.-]*:|//)',
    caseSensitive: false,
  ).hasMatch(value);
}
