/// HTML 预览的**章节清单**：页面里的 `<h1>~<h6>` 与 ARIA 语义标题
/// （`role="heading"`，层级取 `aria-level`；纯逻辑，可单测）。
///
/// 与 Markdown 的差别只有两处，其余（抽屉、折叠、当前节高亮、点击跳转）完全共用：
///
/// 1. **层级来自标签名**：`<h2>` 就是二级标题，不需要像 Markdown 那样数井号；
///    没有 h 标签时退回 `aria-level`（缺省 2，超过 6 按 6）。
///    **一个标题只留一条**：既是 `<h3>` 又带 `role="heading"` 时按标签算层级；
///    标题套标题（`<div role="heading"><h3>…</h3></div>`）只留外层。
///    `<title>` 不算（那是浏览器标签栏上的文档名，不是正文第一节）。
/// 2. **地址是 DOM 路径**（[DomAddress]），不是源码行号：作者页面没有行号可换算
///    （见 `html_anchor.dart`）。于是「现在读到哪一节」仍由**页面自己**算
///    （它拿得到实时的 `offsetTop`），回执里带一个 `sec` 下标，与位置一起由
///    `parseHtmlAnchorWithSection` 解出来 —— Dart 侧不跑 Markdown 那套行号判据。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'document_outline.dart';
import 'preview_position.dart';

/// 清单回执前缀：`outline <JSON>`。
///
/// 与阅读位置回执（`scroll <JSON>`，见 `html_anchor.dart`）分开：位置每滚停一次
/// 就来一条，清单只在**页面内容变了**（换文件、改窗口尺寸后重扫）才发。
const String kHtmlOutlinePrefix = 'outline ';

/// 一篇 HTML 页面的章节清单。
@immutable
class HtmlOutline extends DocumentOutline {
  const HtmlOutline(super.entries);

  static const HtmlOutline empty = HtmlOutline(<OutlineEntry>[]);

  /// 页面报来的「当前节」下标 → 有效下标；越界或空清单返回 -1。
  ///
  /// 页面按同一份文档顺序扫标题，所以下标可以直用；越界只可能是「页面刚重扫、
  /// 清单还没送到」，这时不高亮比高亮错一条好。
  int sectionAt(int index) {
    if (entries.isEmpty || index < 0 || index >= entries.length) {
      return -1;
    }
    return index;
  }

  /// 解析页面回传的清单载荷（`outline <json>` 的后半段）。
  ///
  /// **单条坏了丢那一条**：目录少一行不影响阅读，而这行代码跑在「预览是否渲染
  /// 成功」的路径旁边 —— 抛异常会让人以为整页白屏（与 `MarkdownOutline.parse` 同）。
  static HtmlOutline parse(Object? value) {
    Object? raw = value;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return empty;
      }
    }
    if (raw is! List) {
      return empty;
    }
    final List<OutlineEntry> entries = <OutlineEntry>[];
    for (final Object? item in raw) {
      if (item is! Map) {
        continue;
      }
      final Object? level = item['level'];
      final Object? path = item['path'];
      final Object? text = item['text'];
      if (level is! num || path is! String || path.isEmpty) {
        continue;
      }
      final int lv = level.toInt();
      if (lv < 1 || lv > 6) {
        continue;
      }
      final Object? id = item['id'];
      entries.add(OutlineEntry(
        level: lv,
        text: text is String ? text : '',
        address: DomAddress(path),
        // 页面没给 id 也无所谓：跳转按路径算，不靠页内锚点
        id: id is String ? id : '',
      ));
    }
    return entries.isEmpty ? empty : HtmlOutline(entries);
  }

  /// 解析一条 WebView 回执；不是清单回执时返回 null（交给别的通道处理）。
  static HtmlOutline? parseReport(String message) {
    if (!message.startsWith(kHtmlOutlinePrefix)) {
      return null;
    }
    return parse(message.substring(kHtmlOutlinePrefix.length));
  }
}
