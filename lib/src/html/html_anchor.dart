/// HTML 预览的**阅读位置通道**：注入页面的脚本 + 回执解析（纯逻辑，可单测）。
///
/// **为什么 HTML 需要单独一套**：Markdown 的锚点是「第几块 + 块内偏移」，那套坐标
/// 建立在 `#content` 的顶级子块上 —— HTML 是作者自己的页面，没有这个结构约定，
/// 只能按像素（`window.scrollY`）记。落点语义仍然复用 [PreviewAnchor]：
/// `block = -1` 正是它文档里写的「算不出来、只能靠 scrollY」那一档，
/// 于是浏览栈与跨会话记忆**一套类型走两条通道**，不必再分叉。
///
/// **为什么现在允许跑脚本**（与 R45「作者页面不执行脚本」的关系）：
/// R45 挡的是**仓库里的任意 HTML**。这里注入的是我们自己的两段固定脚本（上报 +
/// 还原），调用方在注入前已经用 `stripAuthorScripts` 把作者的 `<script>` 与内联
/// 事件整段摘掉 —— 页面里能执行的只剩我们这段。所以「开脚本」不等于「放作者代码
/// 出去跑」，安全边界没有挪动（同 `preview_focus.dart` 已有的做法）。
///
/// **为什么上报要节流、还原要「按住」**：与 Markdown 模板里 `mdWatchAnchor` /
/// `mdHold` 完全同一组理由 —— 滚动中每帧上报会把通道刷爆；而图片/字体是异步到的，
/// 文档高度会在加载后继续变，落一次位压不住（读者看到的是「跳回来又滑走」）。
library;

import 'dart:convert';

import '../model/preview_anchor.dart';

/// 回执前缀：`scroll <锚点 JSON>`。
///
/// 与 Markdown 的 `top <凭据> <JSON>` **有意不同**：那边带渲染凭据（要丢迟到消息），
/// HTML 预览每次提交都是整页重载、页面自己就是我们注入的这段，不存在上一页还在报
/// 的时序问题；少一个字段就少一处可能对不上的地方。
const String kHtmlAnchorPrefix = 'scroll ';

/// 注入页面的脚本：上报节流 + 还原按住。
///
/// 保守写法（`var`、无箭头函数、无 `?.`）：与 `markdown_view.html` 同一口径 ——
/// 一段脚本语法不被支持会让**整段**失效，位置通道连带一起废掉。
const String kHtmlAnchorJs = r'''
var hyperLensAnchorTouched = false;   // 读者真的动过手：还原立刻收手，绝不跟他抢
var hyperLensAnchorHolding = false;   // 正在按住还原：这期间的 scroll 都是自己造成的
var hyperLensAnchorTimer = null;

function hyperLensAnchorPost(msg) {
  try {
    if (window.HyperLens && window.HyperLens.postMessage) { window.HyperLens.postMessage(msg); }
  } catch (e) { /* 非 WebView 环境忽略 */ }
}

function hyperLensAnchorTop() {
  var y = window.scrollY || document.documentElement.scrollTop || 0;
  /* block 恒为 -1：作者页面没有「第几块」的约定，只能按像素落回
     （见 preview_anchor.dart 里 block < 0 的语义）。
     sec = 现在读到第几节（`-1` = 这页没有标题），供章节抽屉高亮用。 */
  return { block: -1, offset: 0, scrollY: Math.round(y), sec: hyperLensSectionIndex() };
}

/* ── 章节（h1~h6）────────────────────────────────────────────────
   页面自己就是大纲的来源：`<h2>` 就是二级标题，不需要像 Markdown 那样从
   词法里反推。`<title>` 不收（浏览器标签栏上的文档名，不是正文第一节）；
   不可见的标题（折叠面板 / display:none）也跳过 —— 抽屉里点了滚不过去。 */
var hyperLensSectionsJson = '';

/* 目录跳转的「夹底」记录：`{ index, y }`。见 hyperLensSectionIndex / hyperLensScrollToSection。 */
var hyperLensSectionClamp = null;

/* 清单缓存（**文档坐标**：top = rect.top + scrollY）。
   为什么缓存：hyperLensSectionIndex() 搭在每 250ms 的位置回执里，每次重扫要
   querySelectorAll + 逐个 getBoundingClientRect —— 几百个标题的文档就是每停一次
   滚动的几百次布局读取。文档高度/宽度变了（折叠展开、图片撑开、旋转屏幕）就作废。 */
var hyperLensSectionCache = [];
var hyperLensSectionCacheKey = -1;

function hyperLensInvalidateSections() {
  hyperLensSectionCache = [];
  hyperLensSectionCacheKey = -1;
}

function hyperLensSections() {
  var scrollY = window.scrollY || document.documentElement.scrollTop || 0;
  var docH = document.documentElement.scrollHeight || 0;
  var docW = document.documentElement.clientWidth || 0;
  var key = docH * 100000 + docW;
  if (hyperLensSectionCacheKey === key) { return hyperLensSectionCache; }
  var out = [];
  var nodes = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    if (el.getClientRects().length === 0) { continue; }
    var text = (el.textContent || '').replace(/\s+/g, ' ').trim();
    if (text === '') { continue; }
    out.push({
      level: parseInt(el.tagName.charAt(1), 10),
      text: text,
      index: out.length,               /* 跳转按「第几个标题」定位 */
      top: Math.round(el.getBoundingClientRect().top + scrollY)  /* 文档坐标 */
    });
  }
  hyperLensSectionCache = out;
  hyperLensSectionCacheKey = key;
  return out;
}

/* 清单只在内容变了才发：位置回执每 250ms 一条，清单跟着刷会把通道刷爆。 */
function hyperLensSectionsPost() {
  var list = hyperLensSections();
  var brief = [];
  for (var i = 0; i < list.length; i++) {
    brief.push({ level: list[i].level, text: list[i].text, index: list[i].index });
  }
  var json = JSON.stringify(brief);
  if (json === hyperLensSectionsJson) { return; }
  hyperLensSectionsJson = json;
  hyperLensAnchorPost('outline ' + json);
}

/* 视口顶端那一行属于哪一节：先取「已经滚过顶线」的最后一个标题，再按与源码视图
   **完全相同**的判据交接 —— 这一节的标题还看得见就留它；滚出顶端、但下一节的
   标题已经上屏，就交给下一节。只看「谁滚过了顶线」会让高亮停在上一节
   （屏幕上早已是下一节的正文，真机上一眼就看得出来）。
   现算而不是缓存偏移 —— 图片/字体异步到达会让 offsetTop 变。 */
function hyperLensSectionIndex() {
  var list = hyperLensSections();
  if (list.length === 0) { return -1; }
  var scrollY = window.scrollY || document.documentElement.scrollTop || 0;
  /* 目录刚点过、页面被文档末尾夹住：认「点的就是这一节」（同 Markdown 的顶对齐夹底）。
     读者一动滚轮/手势，位置就对不上了，自然退回实际判据。 */
  if (hyperLensSectionClamp !== null &&
      Math.abs(hyperLensSectionClamp.y - scrollY) < 2) {
    return hyperLensSectionClamp.index;
  }
  var screenH = window.innerHeight || 0;
  var topEdge = scrollY + 4;
  var idx = -1;
  for (var i = 0; i < list.length; i++) {
    if (list[i].top <= topEdge) { idx = i; } else { break; }
  }
  if (idx < 0) { return 0; }  /* 首个标题之前算第一节（与 Markdown 同口径） */
  while (idx + 1 < list.length) {
    if (list[idx].top >= scrollY) { break; }              /* 标题还看得见 */
    if (list[idx + 1].top > scrollY + screenH) { break; }  /* 下一节标题还没上屏 */
    idx++;
  }
  return idx;
}

/* 吸顶 / 固定栏占掉的高度（作者页面很常见）：跳转要把标题落在它下面，
   而不是正好被盖住。只看贴在视口顶端那一条，取最靠下的边。 */
function hyperLensStickyInset() {
  var inset = 0;
  var nodes = document.querySelectorAll(
    'header, nav, [class*="sticky"], [class*="fixed"]');
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    var style = window.getComputedStyle(el);
    if (style.position !== 'fixed' && style.position !== 'sticky') { continue; }
    var rect = el.getBoundingClientRect();
    if (rect.height <= 0 || rect.width <= 0) { continue; }
    if (rect.top > 2) { continue; }
    if (rect.bottom > inset) { inset = rect.bottom; }
  }
  return Math.round(inset);
}

/* 目录点某一条：把那个标题顶到视口顶端（与源码视图「顶对齐」同一口径）。 */
function hyperLensScrollToSection(n) {
  var list = hyperLensSections();
  var inset = hyperLensStickyInset();  /* 有吸顶栏就别把标题塞到它下面 */
  for (var i = 0; i < list.length; i++) {
    if (list[i].index === n) {
      hyperLensAnchorTouched = true;  /* 读者点的是目录：别让还原脚本跟他抢 */
      var y = list[i].top - inset - 8;  /* top 是文档坐标，不用再加 scrollY */
      window.scrollTo(0, Math.max(0, y));
      /* 末尾几节顶不到顶端（页面已经到底）：记住「点的是这条」，
         下次判当前节时只要位置没被读者动过就认它（同 Markdown 的 _topAlignClamp） */
      hyperLensSectionClamp = {
        index: n,
        y: window.scrollY || document.documentElement.scrollTop || 0
      };
      hyperLensAnchorReport();
      return;
    }
  }
}

function hyperLensAnchorReport() {
  hyperLensAnchorPost('scroll ' + JSON.stringify(hyperLensAnchorTop()));
}

function hyperLensAnchorSchedule(delay) {
  if (hyperLensAnchorHolding) { return; }
  if (hyperLensAnchorTimer !== null) { clearTimeout(hyperLensAnchorTimer); }
  hyperLensAnchorTimer = setTimeout(function () {
    hyperLensAnchorTimer = null;
    hyperLensAnchorReport();
  }, delay);
}

/* 落一次位。scrollY 之外的字段不看（作者页面没有块坐标）。 */
function hyperLensAnchorRestore(a) {
  if (!a || typeof a.scrollY !== 'number') { return; }
  window.scrollTo(0, Math.max(0, a.scrollY));
}

/* 按住 1.5s：图片/字体异步到达会改变文档高度，一次落位压不住。
   读者一动就放手（见 hyperLensAnchorTouched）。 */
function hyperLensAnchorHold(a) {
  if (!a) { return; }
  var until = Date.now() + 1500;
  hyperLensAnchorHolding = true;
  (function stick() {
    if (hyperLensAnchorTouched) { hyperLensAnchorHolding = false; return; }
    hyperLensAnchorRestore(a);
    if (Date.now() < until) {
      setTimeout(stick, 100);
    } else {
      hyperLensAnchorHolding = false;
    }
  })();
}

window.addEventListener('scroll', function () { hyperLensAnchorSchedule(250); }, { passive: true });
window.addEventListener('touchstart', function () { hyperLensAnchorTouched = true; }, { passive: true });
window.addEventListener('touchend', function () { hyperLensAnchorTouched = true; hyperLensAnchorSchedule(30); }, { passive: true });
window.addEventListener('wheel', function () { hyperLensAnchorTouched = true; }, { passive: true });
/* 点链接前先报一次当前位置：读者常常「滚到目标就立刻点走」，
   那一枪必须发生在导航被拦下之前（Dart 侧据此把离开的位置压进浏览栈）。 */
document.addEventListener('click', function () { hyperLensAnchorReport(); }, true);
window.__hyperLensReportAnchor = hyperLensAnchorReport;
''';

/// 生成要注入页面的整段脚本；[restore] 为 null 时**显式落回顶部**。
///
/// 为什么 null 也要落位：同一个 WebView 实例会沿用上一篇的滚动位置（Markdown 侧
/// 实测过：新文档一进来就停在半中腰），不显式说一句「回到 0」，新文件就继承旧位置。
String htmlAnchorScript(PreviewAnchor? restore) {
  final PreviewAnchor target = restore ?? PreviewAnchor.top;
  final String json = _jsJson(target.toJson());
  return '$kHtmlAnchorJs\n'
      'hyperLensAnchorHold($json);\n'
      // 清单先发一次（脚本挂在 </body> 前，前面的标题已经解析完），
      // 再在 load / resize 后各补一次：图片撑开布局、旋转屏幕都会改可见性。
      // 这两处同时作废章节缓存 —— 缓存按文档高度判活，重排后必须重扫。
      'hyperLensSectionsPost();\n'
      "window.addEventListener('load', function () { "
      'hyperLensInvalidateSections(); hyperLensSectionsPost(); '
      'if (!hyperLensAnchorTouched) { hyperLensAnchorHold($json); } });\n'
      "window.addEventListener('resize', function () { "
      'hyperLensInvalidateSections(); hyperLensAnchorSchedule(250); '
      'setTimeout(hyperLensSectionsPost, 250); }, { passive: true });';
}

/// 解析一条位置回执：一次解码同时拿到锚点与「现在读到第几节」。
///
/// 合成一个函数是因为两条信息本来就装在**同一条** `scroll <json>` 里
/// （`sec` 字段，见 [kHtmlAnchorJs]）；分开解析会把同一个 JSON 解码两遍 ——
/// 每 250ms 一次的纯浪费，而且两边的容许度容易跑偏。
///
/// 不是位置回执、或 JSON 认不出来时返回 null（宁可回到顶部，也不要跳到随机偏移）。
/// `section < 0` 表示这条回执没带 / 这页没有标题。
({PreviewAnchor anchor, int section})? parseHtmlAnchorWithSection(
  String message,
) {
  if (!message.startsWith(kHtmlAnchorPrefix)) {
    return null;
  }
  final Object? raw;
  try {
    raw = jsonDecode(message.substring(kHtmlAnchorPrefix.length));
  } on FormatException {
    return null;
  }
  final PreviewAnchor? anchor = PreviewAnchor.tryParse(raw);
  if (anchor == null) {
    return null;
  }
  int section = -1;
  if (raw is Map) {
    final Object? sec = raw['sec'];
    if (sec is num) {
      section = sec.toInt();
    }
  }
  return (anchor: anchor, section: section);
}

/// 只要位置、不要章节时的便利入口（[parseHtmlAnchorWithSection] 的薄封装）。
PreviewAnchor? parseHtmlAnchorReport(String message) =>
    parseHtmlAnchorWithSection(message)?.anchor;

/// `jsonEncode` 的结果放进 JS 是安全的，唯独 `<` 要转义 —— 内联进 `<script>` 时
/// 它可能被解析成标签（与 `preview_focus.dart` 同一口径）。
String _jsJson(Object? value) =>
    jsonEncode(value).replaceAll('<', r'\u003c');
