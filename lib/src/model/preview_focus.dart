import 'dart:math' as math;

import 'package:meta/meta.dart';

/// 搜索命中在**预览**里的落点：一段要亮的文字 + 它是全文第几次出现。
///
/// **为什么不能复用 [PreviewPosition]**：锚点是「读者停在哪一块」（服务返回时的位置
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

  /// 写进 Markdown 模板载荷的 `payload.focus`（见 `buildMarkdownPayload`）。
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
