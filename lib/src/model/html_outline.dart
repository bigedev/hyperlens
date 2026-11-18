/// HTML 预览的**章节清单**：页面里的 `<h1>~<h6>`（纯逻辑，可单测）。
///
/// 与 Markdown 的差别只有两处，其余（抽屉、折叠、当前节高亮、点击跳转）完全共用：
///
/// 1. **层级来自标签名**：`<h2>` 就是二级标题，不需要像 Markdown 那样数井号；
///    `<title>` 不算（那是浏览器标签栏上的文档名，不是正文第一节）。
/// 2. **没有源码行号**：作者页面是 WebView 渲染出来的，行号换算不出来
///    （见 `html_anchor.dart` 里 `block = -1` 的理由）。于是「现在读到哪一节」
///    由**页面自己**算（它拿得到实时的 `offsetTop`），回执里带一个 `sec` 下标，
///    与位置锚点一起由 `parseHtmlAnchorWithSection` 解出来 —— Dart 侧不跑
///    `MarkdownOutline.currentForScreen` 那套行号判据。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'document_outline.dart';

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
      final Object? index = item['index'];
      final Object? text = item['text'];
      if (level is! num || index is! num) {
        continue;
      }
      final int lv = level.toInt();
      final int idx = index.toInt();
      if (lv < 1 || lv > 6 || idx < 0) {
        continue;
      }
      entries.add(OutlineEntry(
        level: lv,
        text: text is String ? text : '',
        // 与 `PreviewAnchor.block` 不同源：HTML 的这个数是「第几个标题」，
        // 跳转就是 `hyperLensScrollToSection(block)`
        block: idx,
        // 页面没给 id 也无所谓：跳转按标题元素算，不靠页内锚点
        line: 0,
      ));
    }
    if (entries.isEmpty) {
      return empty;
    }
    // 页面按文档顺序扫；万一顺序乱了，「当前节」下标会与列表对不上
    entries.sort((OutlineEntry a, OutlineEntry b) => a.block.compareTo(b.block));
    return HtmlOutline(entries);
  }

  /// 解析一条 WebView 回执；不是清单回执时返回 null（交给别的通道处理）。
  static HtmlOutline? parseReport(String message) {
    if (!message.startsWith(kHtmlOutlinePrefix)) {
      return null;
    }
    return parse(message.substring(kHtmlOutlinePrefix.length));
  }
}
