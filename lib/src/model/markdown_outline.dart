/// Markdown 预览的**章节清单**（目录导航的数据模型）。
///
/// 为什么单独一个文件：清单是模板（`assets/web/markdown_view.html`）扫出来的
/// `h1~h6`，字段与回传格式一一对应；解析、缩进归一、反推「现在读到哪一节」
/// 都是纯逻辑 —— 抽出来才能用单测钉住，真机上肉眼很难发现「缩进跳级」
/// 「当前小节差一条」这类偏差。
///
/// 每条的地址是**标题所在的源码行**（[SourceAddress]）：与位置回执同一个坐标，
/// 于是「跳到某一节」与「返回时落回读到的位置」走同一条滚动原语
/// （模板的 `mdScrollToLine`），两套判据不会各算各的。
///
/// 清单的**形状**（[OutlineEntry] / [DocumentOutline]）与 HTML 预览共用，见
/// `document_outline.dart`；这里只保留 Markdown 特有的坐标换算。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'document_outline.dart';
import 'preview_position.dart';

export 'document_outline.dart';

/// 一篇 Markdown 文档的章节清单。
@immutable
class MarkdownOutline extends DocumentOutline {
  const MarkdownOutline(super.entries);

  /// 没有章节：空文档、纯段落、或还没收到清单回执。
  static const MarkdownOutline empty = MarkdownOutline(<OutlineEntry>[]);

  /// [line] 这一行属于哪一节（清单下标）。
  ///
  /// 用二分：清单是**按行号递增**的（模板顺序扫出来的），长文档里每次滚动都要问一次。
  ///
  /// **首个标题之前算第一节**（与代码大纲同一口径）：`[line] > 0` 且清单非空时至少
  /// 返回 0。抽屉里一条都不高亮会被读成「我点的那条丢了」—— 高亮的含义是「你现在
  /// 读到哪」，「在第一节前面的引子里」最接近的表述就是第一节。`[line] <= 0` 才返回 -1。
  int sectionAtLine(int line) {
    if (entries.isEmpty || line <= 0) {
      return -1;
    }
    int low = 0;
    int high = entries.length - 1;
    int found = -1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (_lineOf(entries[mid]) <= line) {
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
  /// [viewport] 是位置回执给的观测量（视口顶 / 底那一带的源码行）；顶行为 null 表示
  /// 这条回执没有行号，返回 -1（不猜）。
  ///
  /// - 标题还看得见（`line >= topLine`）⇒ 就是它；
  /// - 标题滚出顶端、但下一节的标题还没进屏幕上半部分 ⇒ 仍算它（屏幕上大部分还是
  ///   这一节的正文）；
  /// - 都不挡 ⇒ 交给下一节。
  ///
  /// **中线**这条与 `CodeOutline.currentForScreen` 同一口径、同一理由：一屏 40+ 行的
  /// 平板上，下一节标题在下半屏露头就交接，会让高亮跑到眼里还没读到的章节
  /// （2026-11-06 MatePad Mini 反馈）。
  int sectionAtViewport(PreviewViewport viewport) {
    final int? topLine = viewport.topLine;
    if (entries.isEmpty || topLine == null) {
      return -1;
    }
    int index = sectionAtLine(topLine);
    if (index < 0) {
      return -1;
    }
    final int bottomLine = viewport.bottomLine ?? topLine;
    if (bottomLine < topLine) {
      return index;
    }
    // 交接线：屏幕中线。下一节的标题要**越过**它才算在读下一节（压线不算）。
    final int handoverLine = topLine + ((bottomLine - topLine) >> 1);
    while (index + 1 < entries.length) {
      if (_lineOf(entries[index]) >= topLine) {
        break; // 标题还看得见
      }
      if (_lineOf(entries[index + 1]) >= handoverLine) {
        break; // 下一节的标题还没进上半屏（压线不算）
      }
      index++;
    }
    return index;
  }

  /// 一条清单项的源码行；不是 [SourceAddress] 时按 0（本清单里不会出现）。
  static int _lineOf(OutlineEntry entry) =>
      entry.address is SourceAddress ? (entry.address as SourceAddress).line : 0;

  /// 解析模板回传的清单载荷（`outline <凭据> <json>` 的后半段）。
  ///
  /// 收的通常是 JS `JSON.stringify` 出来的字符串，也容忍已解好的 List
  /// （与 `PreviewPosition.tryParse` 同一个口径）。
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
      final Object? line = item['line'];
      final Object? text = item['text'];
      if (level is! num || line is! num) {
        continue;
      }
      final int lv = level.toInt();
      final int ln = line.toInt();
      // 没有行号的标题给不出地址（跳不过去、也无法参与高亮），按坏条目丢掉
      if (lv < 1 || lv > 6 || ln < 1) {
        continue;
      }
      final Object? id = item['id'];
      entries.add(OutlineEntry(
        level: lv,
        text: text is String ? text : '',
        address: SourceAddress(ln),
        id: id is String ? id : '',
      ));
    }
    if (entries.isEmpty) {
      return empty;
    }
    // 模板是按文档顺序扫的；万一顺序乱了，二分定位会给出错答案，这里先保证单调
    entries.sort((OutlineEntry a, OutlineEntry b) =>
        (a.address as SourceAddress).line.compareTo(
          (b.address as SourceAddress).line,
        ));
    return MarkdownOutline(entries);
  }
}
