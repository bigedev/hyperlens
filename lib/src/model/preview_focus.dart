import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

/// 搜索命中在**预览**里的落点：一段要亮的文字 + 它是全文第几次出现。
///
/// **为什么不能复用 [PreviewAnchor]**：锚点是「读者停在哪一块」（服务返回时的位置
/// 还原），块号来自 `#content` 的顶级子块；而搜索命中的坐标是**源码里的行列**，
/// 渲染成 HTML 之后既没有行号、也没有「块」能对上（一个列表项里的第三个词，与它是
/// 第几块毫无关系）。能跨过渲染这一层的只有**文字本身**，所以这里送的是片段文本。
///
/// 消歧靠 [occurrence]：同一个词在文档里出现十次，得知道该滚到第几处（Dart 侧用
/// 源码算，见 [fromLineColumn]）。JS 侧找到不足这么多个时退到最后一个，一处都找不到
/// 就什么都不做 —— 宁可停在开头，也不要滚到随机位置。
@immutable
class PreviewFocus {
  const PreviewFocus({required this.needle, required this.occurrence});

  /// 要高亮并滚到的片段（源码里那段文字，渲染后会作为文本节点存在）。
  final String needle;

  /// [needle] 在**全文**里第几次出现（0 起）。
  final int occurrence;

  /// 从源码的行列区间推出焦点；给不出**可信**的片段时返回 null。
  ///
  /// [line] 1 起；[column] / [length] 同样 1 起（与 `CodeFocus` 同口径）。
  /// 三个前提任一不成立就不做定位：
  /// - 行号越界 / 列号越界（文件在搜索之后被改过）；
  /// - 片段是空白（预览里一个空格既看不见也没法高亮）；
  /// - [line] 落在 `\n` 之外的 CR 上（CRLF 文档）：行内偏移按 `\n` 切分算，
  ///   行尾多出的 `\r` 只会让片段末尾多一个不可见字符，这里顺手剔掉。
  ///
  /// 注意**不校验**切片处是否真等于搜索词：调用方手里的文本可能是内联了图片的
  /// （回环资源服务起不来时），行内的列偏移会往后挪一段。此时切出来的仍是一段
  /// 真实存在、且离命中很近的文字 —— 退一步是「亮错一个词」，比整篇不定位好。
  static PreviewFocus? fromLineColumn({
    required String text,
    required int line,
    required int? column,
    required int? length,
  }) {
    if (text.isEmpty || line < 1 || column == null || length == null) {
      return null;
    }
    if (column < 1 || length <= 0) {
      return null;
    }
    // 行首：逐行数 `\n`。命中在第 500 行时这是 500 次 indexOf —— 只发生一次
    // （打开文件那一刻），与「全文 indexOf」比可以忽略。
    int lineStart = 0;
    for (int i = 1; i < line; i++) {
      final int nl = text.indexOf('\n', lineStart);
      if (nl < 0) {
        return null; // 行号越界：这份文本里没有那一行
      }
      lineStart = nl + 1;
    }
    int lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = text.length;
    }
    if (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x0D) {
      lineEnd--; // CRLF：把 `\r` 排除在行文本之外
    }
    final int base = lineStart + (column - 1);
    final int end = math.min(base + length, lineEnd);
    if (base < lineStart || base >= end || end > text.length) {
      return null;
    }
    final String needle = text.substring(base, end);
    if (needle.trim().isEmpty) {
      return null;
    }
    // 第几次出现：只数到命中起点之前的那些
    int occurrence = 0;
    int at = text.indexOf(needle);
    while (at >= 0 && at < base) {
      occurrence++;
      at = text.indexOf(needle, at + 1);
    }
    return PreviewFocus(needle: needle, occurrence: occurrence);
  }

  /// 写进 Markdown 模板载荷的 `payload.focus`（见 [buildMarkdownPayload]）。
  Map<String, Object?> toJson() => <String, Object?>{
        'needle': needle,
        'occurrence': occurrence,
      };

  @override
  bool operator ==(Object other) =>
      other is PreviewFocus &&
      other.needle == needle &&
      other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(needle, occurrence);

  @override
  String toString() => 'PreviewFocus("$needle" #$occurrence)';
}

/// 页面里「按片段定位并高亮」的那段脚本（**Markdown 与 HTML 预览共用**）。
///
/// 一份源码两处用：
/// - Markdown 模板用 `/*__FOCUS_JS__*/` 占位把它内联进去（见 `buildMarkdownHtml`），
///   渲染成功后由页面自己调 [previewFocusCall] 生成的那句；
/// - HTML 预览的脚本平时是关的，只在「从搜索命中打开」时开口子，
///   由 Dart 侧 `runJavaScript` 把「源码 + 调用」一起塞进去。
///
/// 为什么两边不各写一份：两边一旦漂移，表现是「一种文档能定位、另一种不动」，
/// 而这种差异在主机上测不出来（`flutter_tester` 里没有 WebViewPlatform，见 R131）。
///
/// **实现口径**：
/// - `TreeWalker` 只走文本节点，跳过 `script` / `style` / 已经包过的 `mark`；
/// - 一处命中被行内标签（`<strong>`、`<code>`）切开时 `surroundContents` 会抛
///   `InvalidStateError`，那一处就跳过 —— 宁可少亮一处，也不要为了它把作者的
///   标签结构拆坏（A 方案的已知局限，见 design.md §6.6）；
/// - 滚到**视口中间**（`block:'center'`）而不是顶端：命中常常紧跟在标题下面，
///   贴顶会把上文切掉，读者看不出这是哪一节里的。
const String kPreviewFocusJs = r'''
function hyperLensClearFocus() {
  var host = document.getElementById('content') || document.body;
  if (!host) { return; }
  var marks = host.querySelectorAll('mark[data-hyperlens-focus]');
  for (var i = 0; i < marks.length; i++) {
    var mark = marks[i];
    var parent = mark.parentNode;
    if (!parent) { continue; }
    while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
    parent.removeChild(mark);
  }
  // 拆完 mark 后文本节点是碎的：合并回去，否则下一次查找会被节点边界挡住
  if (host.normalize) { host.normalize(); }
}

function hyperLensMarkNeedle(host, needle) {
  var marks = [];
  if (!needle) { return marks; }
  var walker = document.createTreeWalker(host, 4 /* SHOW_TEXT */, null, false);
  var nodes = [];
  var node;
  while ((node = walker.nextNode())) { nodes.push(node); }
  for (var i = 0; i < nodes.length; i++) {
    var textNode = nodes[i];
    var tag = textNode.parentNode ? textNode.parentNode.nodeName.toUpperCase() : '';
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'MARK' || tag === 'TEXTAREA') {
      continue;
    }
    var text = textNode.nodeValue || '';
    var index = text.indexOf(needle);
    while (index >= 0) {
      var range = document.createRange();
      range.setStart(textNode, index);
      range.setEnd(textNode, index + needle.length);
      var mark = document.createElement('mark');
      mark.setAttribute('data-hyperlens-focus', '1');
      try {
        range.surroundContents(mark);
      } catch (e) {
        index = text.indexOf(needle, index + 1);
        continue;
      }
      marks.push(mark);
      // 包好之后这个文本节点只剩前半段，后半段是 mark 的下一个兄弟节点
      textNode = mark.nextSibling;
      if (!textNode || textNode.nodeType !== 3) { break; }
      text = textNode.nodeValue || '';
      index = text.indexOf(needle);
    }
  }
  return marks;
}

/* 返回亮起来的处数（0 = 没找到）：Dart 侧只用来打日志，别据此改状态。 */
function hyperLensApplyFocus(focus) {
  if (!focus || !focus.needle) { return 0; }
  hyperLensClearFocus();
  var host = document.getElementById('content') || document.body;
  if (!host) { return 0; }
  var marks = hyperLensMarkNeedle(host, focus.needle);
  if (!marks.length) { return 0; }
  var index = focus.occurrence;
  if (typeof index !== 'number' || index < 0) { index = 0; }
  if (index >= marks.length) { index = marks.length - 1; }
  var target = marks[index];
  if (target.scrollIntoView) { target.scrollIntoView({ block: 'center' }); }
  return marks.length;
}
''';

/// 页面里调用上面那段脚本的一句（JSON 已转义，可安全内联进 `<script>`）。
String previewFocusCall(PreviewFocus focus) =>
    'hyperLensApplyFocus(${_jsJson(focus.toJson())});';

/// 给 HTML 预览用的「源码 + 调用」：脚本模式下一次性塞进页面。
String previewFocusScript(PreviewFocus focus) =>
    '$kPreviewFocusJs\n${previewFocusCall(focus)}';

/// `jsonEncode` 的结果直接放进 JS 是安全的，唯独 `<` 要转义 —— 内联进 `<script>`
/// 时它可能被解析成标签（与 `buildMarkdownPayload` 同一口径）。
String _jsJson(Object? value) =>
    jsonEncode(value).replaceAll('<', r'\u003c');
