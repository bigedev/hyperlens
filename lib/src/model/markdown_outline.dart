/// Markdown 预览的**章节清单**（目录导航的数据模型）。
///
/// 为什么单独一个文件：清单是模板（`assets/web/markdown_view.html`）扫出来的
/// `h1~h6`，字段与回传格式一一对应；解析、缩进归一、反推「现在读到哪一节」
/// 都是纯逻辑 —— 抽出来才能用单测钉住，真机上肉眼很难发现「缩进跳级」
/// 「当前小节差一条」这类偏差。
///
/// 与 [PreviewAnchor] 的关系：一条章节记的是**顶级子块序号**（[OutlineEntry.block]），
/// 和位置锚点是同一个坐标系 —— 于是「跳到某一节」可以直接复用块级滚动
/// （模板的 `mdScrollToBlock`），「返回时落回读到的位置」也自动落在同一节上。
///
/// 清单的**形状**（[OutlineEntry] / [DocumentOutline]）与 HTML 预览共用，见
/// `document_outline.dart`；这里只保留 Markdown 特有的坐标换算。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'document_outline.dart';

export 'document_outline.dart';

/// 一篇 Markdown 文档的章节清单。
@immutable
class MarkdownOutline extends DocumentOutline {
  const MarkdownOutline(super.entries);

  /// 没有章节：空文档、纯段落、或还没收到清单回执。
  static const MarkdownOutline empty = MarkdownOutline(<OutlineEntry>[]);

  /// [block] 这一块属于哪一节（清单下标）。
  ///
  /// 用二分：清单是**按 block 递增**的（模板顺序扫出来的），长文档里每次滚动都要问一次。
  ///
  /// **首个标题之前算第一节**（与代码大纲同一口径）：`[block] ≥ 0` 且清单非空时至少返回
  /// 0。抽屉里一条都不高亮会被读成「我点的那条丢了」—— 高亮的含义是「你现在读到哪」，
  /// 「在第一节前面的引子里」最接近的表述就是第一节。`[block] < 0` 才返回 -1。
  int currentFor(int block) {
    if (entries.isEmpty || block < 0) {
      return -1;
    }
    int low = 0;
    int high = entries.length - 1;
    int found = -1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (entries[mid].block <= block) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found < 0 ? 0 : found;
  }

  /// [line] 这一行属于哪一节（按**源码行号**二分）。
  ///
  /// 只在清单带行号时可用；首个标题之前算第一节，与 [currentFor] 同口径。
  int currentForLine(int line) {
    if (entries.isEmpty || line <= 0 || entries.first.line <= 0) {
      return -1;
    }
    int low = 0;
    int high = entries.length - 1;
    int found = -1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (entries[mid].line <= line) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found < 0 ? 0 : found;
  }

  /// 屏幕上该高亮哪一节：判据与源码态大纲一致 —— **这一节的标题还在不在屏幕的上半部分**。
  ///
  /// [topLine] / [bottomLine] 是预览回执给的视口顶 / 底部的源码行号（0 = 算不出来）；
  /// [block] 是顶端所在的顶级子块，老回执（没有行号）时按块级判法退化。
  ///
  /// - 标题还看得见（`line >= topLine`）⇒ 就是它；
  /// - 标题滚出顶端、但下一节的标题还没进屏幕上半部分 ⇒ 仍算它（屏幕上大部分还是
  ///   这一节的正文）；
  /// - 都不挡 ⇒ 交给下一节。
  ///
  /// **中线**这条与 `CodeOutline.currentForScreen` 同一口径、同一理由：一屏 40+ 行的
  /// 平板上，下一节标题在下半屏露头就交接，会让高亮跑到眼里还没读到的章节
  /// （2026-11-06 MatePad Mini 反馈）。
  ///
  /// 为什么不再只看 [block]：块级判法等于「顶端那一块属于谁」，标题滚出视口后
  /// 高亮仍停在上一节（与源码态被否掉的旧判据同一个毛病）。
  int currentForScreen(int topLine, int bottomLine, {int block = -1}) {
    if (entries.isEmpty) {
      return -1;
    }
    if (topLine <= 0 || entries.any((OutlineEntry e) => e.line <= 0)) {
      return currentFor(block); // 老回执 / 个别块缺行号：退回块级（旧行为）
    }
    int index = currentForLine(topLine);
    if (index < 0 || bottomLine < topLine) {
      return index;
    }
    // 交接线：屏幕中线。下一节的标题要**越过**它才算在读下一节（压线不算）。
    final int handoverLine = topLine + ((bottomLine - topLine) >> 1);
    while (index + 1 < entries.length) {
      if (entries[index].line >= topLine) {
        break; // 标题还看得见
      }
      if (entries[index + 1].line >= handoverLine) {
        break; // 下一节的标题还没进上半屏（压线不算）
      }
      index++;
    }
    return index;
  }

  /// 解析模板回传的清单载荷（`outline <凭据> <json>` 的后半段）。
  ///
  /// 收的通常是 JS `JSON.stringify` 出来的字符串，也容忍已解好的 List
  /// （与 [PreviewAnchor.tryParse] 同一个口径）。
  ///
  /// **单条坏了就丢那一条，不整体失败**：目录缺一行不影响阅读，而这行代码跑在
  /// 「预览是否渲染成功」的路径旁边 —— 抛异常会让人以为整篇白屏。
  static MarkdownOutline parse(Object? value) {
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
      final Object? block = item['block'];
      final Object? text = item['text'];
      if (level is! num || block is! num) {
        continue;
      }
      final int lv = level.toInt();
      final int blk = block.toInt();
      if (lv < 1 || lv > 6 || blk < 0) {
        continue;
      }
      final Object? id = item['id'];
      final Object? line = item['line'];
      entries.add(OutlineEntry(
        level: lv,
        text: text is String ? text : '',
        block: blk,
        id: id is String ? id : '',
        // 老版本模板没回 line：按「算不出来」处理，高位判据自动退化到块级
        line: line is num ? line.toInt() : 0,
      ));
    }
    if (entries.isEmpty) {
      return empty;
    }
    // 模板是按文档顺序扫的；万一顺序乱了，二分定位会给出错答案，这里先保证单调
    entries.sort((OutlineEntry a, OutlineEntry b) => a.block.compareTo(b.block));
    return MarkdownOutline(entries);
  }
}
