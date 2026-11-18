/// HTML 预览的**阅读位置通道**：注入页面的脚本 + 回执解析（纯逻辑，可单测）。
///
/// **为什么 HTML 需要单独一套**：Markdown 的地址是源码行，那套坐标建立在
/// `#content` 的 token 边界上 —— HTML 是作者自己的页面，既没有源码行号，也没有
/// 「第几块」的结构约定，只能按**节点**记（[DomAddress]，例如
/// `body>div#main>p:nth(3)`）。
///
/// 旧版这里按像素（`window.scrollY`）记，位置锚点与 Markdown 共用 `PreviewAnchor`
/// （现为 `PreviewPosition`）。
/// 那条路在「文件被改过」「窗口尺寸变了」时会把读者扔到与新页面无关的地方，且
/// 让 Dart 侧多出「这次是不是猜的」分支；现在统一成路径，解析不到就回顶部
/// （见 `docs/plan/preview-plugin-and-ast-plan.md` §9.2）。
///
/// **为什么现在允许跑脚本**（与「作者页面不执行脚本」的关系）：那条规矩挡的是
/// **仓库里的任意 HTML**。这里注入的是我们自己的固定脚本（上报 + 还原），调用方
/// 在注入前已经用 `stripAuthorScripts` 把作者的 `<script>` 与内联事件整段摘掉 ——
/// 页面里能执行的只剩我们这段。所以「开脚本」不等于「放作者代码出去跑」，
/// 安全边界没有挪动（同 `preview_focus.dart` 已有的做法）。
///
/// **为什么上报要节流、还原要「按住」**：与 Markdown 模板里 `mdWatchAnchor` /
/// `mdHold` 完全同一组理由 —— 滚动中每帧上报会把通道刷爆；而图片/字体是异步到的，
/// 文档高度会在加载后继续变，落一次位压不住（读者看到的是「跳回来又滑走」）。
library;

import 'dart:convert';

import '../model/preview_position.dart';
import '../protocol/hyperlens_bridge.dart';

/// 回执前缀：`scroll <位置 JSON>`。
///
/// 与 Markdown 的 `top <凭据> <JSON>` **有意不同**：那边带渲染凭据（要丢迟到消息），
/// HTML 预览每次提交都是整页重载、页面自己就是我们注入的这段，不存在上一页还在报
/// 的时序问题；少一个字段就少一处可能对不上的地方。
const String kHtmlAnchorPrefix = 'scroll ';

/// 注入页面的脚本：上报节流 + 还原按住 + 路径定位。
///
/// 通道名是占位符 `__HYPERLENS_CHANNEL__`，由 [htmlAnchorScript] 替换 —— 直接注入
/// 这份常量的话，`window.__HYPERLENS_CHANNEL__` 恒为 undefined，整条位置通道静默失效。
///
/// 保守写法（`var`、无箭头函数、无 `?.`）：与 `markdown_view.html` 同一口径 ——
/// 一段脚本语法不被支持会让**整段**失效，位置通道连带一起废掉。
const String _anchorJs = r'''
var hyperLensAnchorTouched = false;   // 读者真的动过手：还原立刻收手，绝不跟他抢
var hyperLensAnchorHolding = false;   // 正在按住还原：这期间的 scroll 都是自己造成的
var hyperLensAnchorTimer = null;

function hyperLensAnchorPost(msg) {
  try {
    if (window.__HYPERLENS_CHANNEL__ && window.__HYPERLENS_CHANNEL__.postMessage) {
      window.__HYPERLENS_CHANNEL__.postMessage(msg);
    }
  } catch (e) { /* 非 WebView 环境忽略 */ }
}

/* ── 节点路径（HTML 的地址）──────────────────────────────────────
   形如 `body>div#main>h2:nth(3)`：段内 `:nth(k)` 是**同名兄弟里的第 k 个**（1 起），
   有 `id` 时用 `#id`（作者改结构也不至于全错）。段名一律小写标签名。
   为什么用路径而不是像素：像素在「文件被改过 / 窗口尺寸变了」时指向毫无关系的
   地方；路径至少还落在同一个节点上，找不到就明确回顶部。 */
function hyperLensPathSeg(el) {
  var tag = (el.tagName || '').toLowerCase();
  /* body 单写一段：它是路径的起点，`:nth(1)` 只会让记忆里的地址更长、更容易失效 */
  if (el === document.body) { return 'body'; }
  if (el.id) { return tag + '#' + el.id; }
  var i = 1;
  var sib = el;
  while ((sib = sib.previousElementSibling)) {
    if (sib.tagName === el.tagName) { i++; }
  }
  return tag + ':nth(' + i + ')';
}

function hyperLensPathOf(el) {
  var parts = [];
  var node = el;
  while (node && node.nodeType === 1) {
    parts.unshift(hyperLensPathSeg(node));
    if (node === document.body || node === document.documentElement) { break; }
    node = node.parentElement;
  }
  return parts.join('>');
}

function hyperLensByPath(path) {
  if (!path) { return null; }
  var segs = String(path).split('>');
  var node = document.body;
  var started = false;
  for (var i = 0; i < segs.length; i++) {
    var seg = segs[i];
    if (!started) {
      /* 第一段通常是 body；万一作者页面结构怪（没有 body），就从当前节点找起 */
      if (seg.indexOf('body') === 0) { node = document.body; started = true; continue; }
      started = true;
    }
    if (!node) { return null; }
    var hash = seg.indexOf('#');
    if (hash > 0) {
      var byId = document.getElementById(seg.substring(hash + 1));
      if (!byId) { return null; }
      node = byId;
      continue;
    }
    var nth = /:nth\((\d+)\)$/.exec(seg);
    var tag = (nth ? seg.substring(0, nth.index) : seg).toUpperCase();
    var want = nth ? parseInt(nth[1], 10) : 1;
    var kids = node.children || [];
    var count = 0;
    var found = null;
    for (var k = 0; k < kids.length; k++) {
      if ((kids[k].tagName || '') !== tag) { continue; }
      count++;
      if (count === want) { found = kids[k]; break; }
    }
    if (!found) { return null; }
    node = found;
  }
  return node;
}

/* 元素**是否真的看得见**。
   只看 getClientRects() 不够：`<details>` 收起时，里面的内容在 Chromium 里仍然有
   layout box（用的是 content-visibility，不是 display:none），rects 非空却不可见 ——
   实测（2026-11-18，anchor-probe.html 的折叠小节）就被错收进了章节清单，而抽屉里
   点了它根本滚不过去。所以再显式查一遍「祖先 details 是否展开」。
   display:none / 零尺寸仍由 rects 挡住。 */
function hyperLensVisible(el) {
  if (!el || el.getClientRects().length === 0) { return false; }
  var node = el;
  while (node && node !== document.body) {
    if (node.tagName === 'DETAILS' && !node.open) { return false; }
    node = node.parentElement;
  }
  return true;
}

/* 视口顶端那一点落到的元素：位置地址的粒度就是它（通常是一个段落）。
   探测点 = 吸顶栏下沿再往下 12px：直接取 y=8 会命中吸顶栏本身（地址变成「栏」），
   而落在栏下沿、标题上边距那 1px 里则会退到**上一块**（实测：跳转到某节后地址
   记成了上一段，返回时那一节被推下去一点）。 */
function hyperLensTopElement() {
  var inset = hyperLensStickyInset();
  var probeY = inset + 12;
  var x = Math.min(8, (window.innerWidth || 1) - 1);
  var el = null;
  try { el = document.elementFromPoint(x, probeY); } catch (e) { el = null; }
  /* 往下钻到真正的那一块：命中的常是容器（`body` / `div#main` / 带内边距的外壳），
     而地址要落到「读者眼睛所在的那个段落」，否则还原只会回到容器顶端 ——
     实测：滚到第 4 节后地址退化成 `div#main`，等于每次返回都从头看。
     钻法：取**最后一个已经滚过探测线**的子块（它才是屏幕顶上那一块）。 */
  var guard = 0;
  while (el && guard++ < 12) {
    var kids = el.children || [];
    var next = null;
    for (var i = 0; i < kids.length; i++) {
      var r = kids[i].getBoundingClientRect();
      if (r.height <= 0 && r.width <= 0) { continue; }  /* 零尺寸跳过 */
      if (r.top <= probeY) { next = kids[i]; } else { break; }
    }
    if (!next) { break; }
    el = next;
  }
  return el || document.body;
}

function hyperLensAnchorTop() {
  /* sec = 现在读到第几节（`-1` = 这页没有标题），供章节抽屉高亮用；路径服务「回到
     同一处」。两者都要：高亮要的是结构位置，还原要的是具体节点。 */
  return { path: hyperLensPathOf(hyperLensTopElement()), sec: hyperLensSectionIndex() };
}

/* ── 章节（h1~h6 + 语义标题）──────────────────────────────────────
   页面自己就是大纲的来源：`<h2>` 就是二级标题，不需要像 Markdown 那样从
   词法里反推。`<title>` 不收（浏览器标签栏上的文档名，不是正文第一节）；
   不可见的标题（折叠面板 / display:none）也跳过 —— 抽屉里点了滚不过去。

   除标签外还认 ARIA 语义标题（`role="heading"`，层级取 `aria-level`）：有些页面
   用 `<div role="heading" aria-level="2">` 代替 h 标签（组件库、可访问性改造过的
   导出页）。**一个标题只留一条**，两条路各挡一半：
   - 同一个元素既是 `<h3>` 又带 `role="heading"`：并集选择器里 querySelectorAll
     只返回它一次，天然不重复；
   - 标题套标题（`<div role="heading"><h3>…</h3></div>`）：内层由
     `hyperLensInsideHeading` 跳过，只留外层。 */
var hyperLensSectionsJson = '';

/* 目录跳转的「夹底」记录：`{ path, y }`。见 hyperLensSectionIndex / hyperLensScrollToPath。 */
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

/* 标题里再套标题（`<div role="heading"><h3>…</h3></div>`，或组件库把 h 标签包进
   自己的标题壳里）：只留**外层**。同一个标题进抽屉两次，读者会以为文档写重了；
   而两条的落点相差不到一行，没有一条是错的 —— 留着不如去重。 */
function hyperLensInsideHeading(el) {
  var node = el.parentElement;
  while (node && node !== document.body) {
    var tag = (node.tagName || '').toUpperCase();
    if ((tag.length === 2 && tag.charAt(0) === 'H') ||
        node.getAttribute('role') === 'heading') {
      return true;
    }
    node = node.parentElement;
  }
  return false;
}

/* 一个标题节点是第几级。
   优先级：h 标签（作者写在标签上的语义最硬）→ `aria-level` → 2（`role="heading"`
   的规范默认层级）。`aria-level` 允许任意正整数，抽屉只到六级，超出按六级算；
   认不出的值退回默认，别让一条坏标记把整条清单的缩进带歪。 */
function hyperLensSectionLevel(el) {
  var tag = (el.tagName || '').toUpperCase();
  if (tag.length === 2 && tag.charAt(0) === 'H') {
    var n = parseInt(tag.charAt(1), 10);
    if (n >= 1 && n <= 6) { return n; }
  }
  var aria = parseInt(el.getAttribute('aria-level'), 10);
  if (!isNaN(aria) && aria >= 1) { return aria > 6 ? 6 : aria; }
  return 2;
}

function hyperLensSections() {
  var scrollY = window.scrollY || document.documentElement.scrollTop || 0;
  var docH = document.documentElement.scrollHeight || 0;
  var docW = document.documentElement.clientWidth || 0;
  var key = docH * 100000 + docW;
  if (hyperLensSectionCacheKey === key) { return hyperLensSectionCache; }
  var out = [];
  var nodes = document.querySelectorAll(
    'h1, h2, h3, h4, h5, h6, [role="heading"], [aria-level]');
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    if (!hyperLensVisible(el)) { continue; }
    /* 套在别的标题里就不收：一个标题只留一条 */
    if (hyperLensInsideHeading(el)) { continue; }
    var text = (el.textContent || '').replace(/\s+/g, ' ').trim();
    if (text === '') { continue; }
    out.push({
      level: hyperLensSectionLevel(el),
      text: text,
      path: hyperLensPathOf(el),                 /* 跳转按路径定位 */
      id: el.id || '',
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
    brief.push({ level: list[i].level, text: list[i].text, path: list[i].path, id: list[i].id });
  }
  var json = JSON.stringify(brief);
  if (json === hyperLensSectionsJson) { return; }
  hyperLensSectionsJson = json;
  hyperLensAnchorPost('outline ' + json);
}

/* 文档尺寸一变就重扫 + 重发清单。
   为什么需要：`<details>` 展开/收起、图片撑开、字体到位都**不会**触发 `load` 或
   `resize`，而它们既改清单（折叠里的标题可见了），也改「读到第几节」的下标 ——
   旧清单配新下标，抽屉高亮会指到别的条目上。
   实测（2026-11-18，notes/html/aria-heading-probe.html）：展开折叠后抽屉一直停在
   7 条，得换个字号触发整页重载才变 8 条；读者看到的正是「展开没反应」。
   没有 ResizeObserver 的环境退回 load / resize 两条（清单不实时，但不报错）。 */
var hyperLensResizeTimer = null;
function hyperLensWatchResize() {
  if (typeof ResizeObserver !== 'function' || !document.body) { return; }
  try {
    var observer = new ResizeObserver(function () {
      if (hyperLensResizeTimer) { clearTimeout(hyperLensResizeTimer); }
      /* 展开动画 / 连续撑开会来一串回调，攒一下再扫 */
      hyperLensResizeTimer = setTimeout(function () {
        hyperLensResizeTimer = null;
        hyperLensInvalidateSections();
        hyperLensSectionsPost();
        hyperLensAnchorSchedule(30);
      }, 120);
    });
    observer.observe(document.body);
  } catch (e) { /* 观察不上就算了：只是清单改回由 load / resize 更新 */ }
}

/* 视口顶端属于哪一节：先取「已经滚过顶线」的最后一个标题，再按与源码视图
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
    for (var c = 0; c < list.length; c++) {
      if (list[c].path === hyperLensSectionClamp.path) { return c; }
    }
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

/* 滚动原语（与 Markdown 的 mdScrollToLine 并列，协议里只允许这两条）：
   把一个节点顶到视口顶端（与源码视图「顶对齐」同一口径）。 */
function hyperLensScrollToPath(path) {
  var el = hyperLensByPath(path);
  if (!el) { return; }
  hyperLensAnchorTouched = true;  /* 读者点的是目录：别让还原脚本跟他抢 */
  var inset = hyperLensStickyInset();  /* 有吸顶栏就别把标题塞到它下面 */
  var scrollY = window.scrollY || document.documentElement.scrollTop || 0;
  var y = el.getBoundingClientRect().top + scrollY - inset - 8;
  window.scrollTo(0, Math.max(0, y));
  /* 末尾几节顶不到顶端（页面已经到底）：记住「点的是这条」，
     下次判当前节时只要位置没被读者动过就认它（同 Markdown 的顶对齐夹底） */
  hyperLensSectionClamp = {
    path: path,
    y: window.scrollY || document.documentElement.scrollTop || 0
  };
  hyperLensAnchorReport();
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

/* 落一次位：有路径就按节点（找不到就回顶部 —— 明确、可解释），没有路径也回顶部。
   不保留像素兜底：旧记忆里的 scrollY 在改过的页面上指向毫无关系的位置。 */
function hyperLensAnchorRestore(a) {
  var el = a && typeof a.path === 'string' ? hyperLensByPath(a.path) : null;
  if (!el || el === document.body) { window.scrollTo(0, 0); return; }
  var inset = hyperLensStickyInset();
  var scrollY = window.scrollY || document.documentElement.scrollTop || 0;
  var y = el.getBoundingClientRect().top + scrollY - inset;
  window.scrollTo(0, Math.max(0, y));
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

/// 通道名占位符：脚本是常量，通道名由使用方定，只能在拼装时替换。
///
/// 与 `markdown_view.html` 里那个 `__HYPERLENS_CHANNEL__` 同一口径 —— 页面与脚本都
/// 不能 import Dart 常量，只能靠占位符 + 替换。
const String _channelPlaceholder = '__HYPERLENS_CHANNEL__';

/// 生成要注入页面的整段脚本；[restore] 为 null 时**显式落回顶部**。
///
/// 为什么 null 也要落位：同一个 WebView 实例会沿用上一篇的滚动位置（Markdown 侧
/// 实测过：新文档一进来就停在半中腰），不显式说一句「回到 0」，新文件就继承旧位置。
///
/// [channelName] 必须与 WebView 侧 `addJavaScriptChannel` 注册的名字逐字一致
/// （默认 [HyperlensBridge.channelName]）：对不上的表现是脚本静默什么都不发 ——
/// 页面里那句 `if (window.<name>)` 只是守卫，通道不存在就整条位置链路哑掉。
String htmlAnchorScript(
  PreviewPosition? restore, {
  String channelName = HyperlensBridge.channelName,
}) {
  HyperlensBridge.checkChannelName(channelName);
  final String json = _jsJson(_restorePayload(restore));
  final String script =
      _anchorJs.replaceAll(_channelPlaceholder, channelName);
  return '$script\n'
      'hyperLensAnchorHold($json);\n'
      // 清单先发一次（脚本挂在 </body> 前，前面的标题已经解析完），
      // 再在 load / resize 后各补一次：图片撑开布局、旋转屏幕都会改可见性。
      // 这两处同时作废章节缓存 —— 缓存按文档高度判活，重排后必须重扫。
      'hyperLensSectionsPost();\n'
      // 之后的高度变化（折叠展开、图片撑开）也要重扫，见 hyperLensWatchResize
      'hyperLensWatchResize();\n'
      "window.addEventListener('load', function () { "
      'hyperLensInvalidateSections(); hyperLensSectionsPost(); '
      'if (!hyperLensAnchorTouched) { hyperLensAnchorHold($json); } });\n'
      "window.addEventListener('resize', function () { "
      'hyperLensInvalidateSections(); hyperLensAnchorSchedule(250); '
      'setTimeout(hyperLensSectionsPost, 250); }, { passive: true });';
}

/// 注入载荷：HTML 只认 `path`；拿到源码行地址（不该发生在 HTML 页上）时按顶部处理。
Map<String, Object?> _restorePayload(PreviewPosition? restore) {
  final PreviewPosition target = restore ?? DomAddress.body;
  return target is DomAddress ? target.toJson() : DomAddress.body.toJson();
}

/// 解析一条位置回执：一次解码同时拿到位置与「现在读到第几节」。
///
/// 合成一个函数是因为两条信息本来就装在**同一条** `scroll <json>` 里
/// （顶层 `path` + `sec`，见 [_anchorJs]）；分开解析会把同一个 JSON 解码两遍 ——
/// 每 250ms 一次的纯浪费，而且两边的容许度容易跑偏。
///
/// 不是位置回执、或 JSON 认不出来时返回 null（宁可回到顶部，也不要跳到随机位置）。
/// `section < 0` 表示这条回执没带 / 这页没有标题；`position == null` 表示旧页面
/// 只报了像素（那时按「无地址」处理）。
({PreviewPosition? position, int section})? parseHtmlAnchorWithSection(
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
  int section = -1;
  if (raw is Map) {
    final Object? sec = raw['sec'];
    if (sec is num) {
      section = sec.toInt();
    }
  }
  return (position: PreviewPosition.tryParse(raw), section: section);
}

/// 只要位置、不要章节时的便利入口（[parseHtmlAnchorWithSection] 的薄封装）。
PreviewPosition? parseHtmlAnchorReport(String message) =>
    parseHtmlAnchorWithSection(message)?.position;

/// `jsonEncode` 的结果放进 JS 是安全的，唯独 `<` 要转义 —— 内联进 `<script>` 时
/// 它可能被解析成标签（与 `preview_focus.dart` 同一口径）。
String _jsJson(Object? value) =>
    jsonEncode(value).replaceAll('<', r'\u003c');
