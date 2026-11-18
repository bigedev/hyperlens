/// 「按片段定位并高亮」的页面脚本：**渲染期与运行期共用这一份**。
///
/// 只在本包内部用（不进 barrel）：对外只有两条入口 ——
/// `HyperlensPage.focus`（渲染时带进模板）与 `HyperlensCommands.forFocus()`
/// （对已经打开的页面补一次定位）。导出原始 JS 等于给使用方第二条路，两条迟早
/// 各自演化。
library;

import 'dart:convert';

import '../model/preview_focus.dart';
import 'hyperlens_bridge.dart';

/// 页面里「按片段定位并高亮」的那段脚本（**Markdown 与 HTML 预览共用**）。
///
/// 一份源码两处用：
/// - Markdown 模板用 `/*__FOCUS_JS__*/` 占位把它内联进去（见 `buildMarkdownHtml`），
///   渲染成功后由页面自己调 [previewFocusCall] 生成的那句；
/// - HTML 预览的脚本平时是关的，只在「从搜索命中打开」时开口子，
///   由 Dart 侧 `runJavaScript` 把「源码 + 调用」一起塞进去。
///
/// 为什么两边不各写一份：两边一旦漂移，表现是「一种文档能定位、另一种不动」，
/// 而这种差异在主机上测不出来（`flutter_tester` 里没有 WebViewPlatform）。
///
/// **实现口径**：
/// - `TreeWalker` 只走文本节点，跳过 `script` / `style` / 已经包过的 `mark`；
/// - 一处命中被行内标签（`<strong>`、`<code>`）切开时 `surroundContents` 会抛
///   `InvalidStateError`，那一处就跳过 —— 宁可少亮一处，也不要为了它把作者的
///   标签结构拆坏（已知局限，接受）；
/// - 滚到**视口中间**（`block:'center'`）而不是顶端：命中常常紧跟在标题下面，
///   贴顶会把上文切掉，读者看不出这是哪一节里的。
const String previewFocusJs = r'''
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

/// 「源码 + 调用」：脚本模式下一次性塞进页面。
///
/// 给了 [channelName] 时**顺带回一条 `focus` 回执**（凭据位写 [HyperlensBridge.noToken]）：
/// 两种文档对「命中亮了几处」的反馈因此是同一条消息（Markdown 模板自己发、带凭据）。
/// 不给就只亮不报 —— 那是「只要它亮，不关心结果」的用法。
String previewFocusScript(PreviewFocus focus, {String? channelName}) {
  if (channelName == null) {
    return '$previewFocusJs\n${previewFocusCall(focus)}';
  }
  // JS 里的字符串字面量单独拼，免得两套引号在这里打架
  final String message =
      "'${HyperlensBridge.focusPrefix}${HyperlensBridge.noToken} '";
  return '$previewFocusJs\n'
      '(function(){var n=hyperLensApplyFocus(${_jsJson(focus.toJson())});'
      'try{window.$channelName.postMessage($message+n);}catch(e){}})();';
}

/// `jsonEncode` 的结果直接放进 JS 是安全的，唯独 `<` 要转义 —— 内联进 `<script>`
/// 时它可能被解析成标签（与 `buildMarkdownPayload` 同一口径）。
String _jsJson(Object? value) =>
    jsonEncode(value).replaceAll('<', r'\u003c');
