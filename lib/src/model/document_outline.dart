/// 预览侧「章节清单」的通用模型：一条标题 + 一整个清单。
///
/// **为什么要从 Markdown 里提出来**：HTML 预览现在也出章节（`<h1>~<h6>`，见
/// `html_outline.dart`），抽屉、折叠、当前节高亮都是同一套，只有「清单从哪儿来、
/// 坐标怎么算」不同 —— 那部分留在各自的 [MarkdownOutline] / `HtmlOutline` 里，
/// 这里只放两边共用的形状。
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// 目录里的一条标题。
@immutable
class OutlineEntry {
  const OutlineEntry({
    required this.level,
    required this.text,
    required this.block,
    this.id = '',
    this.line = 0,
  });

  /// 原始标题层级（`h1` 为 1，最大 6；Markdown 的 `#` 同为 1）。
  final int level;

  /// 标题文本（已 trim；只取文本，不含内联标记）。
  final String text;

  /// 这一条在**预览体坐标系**里的序号。
  ///
  /// Markdown 是 `#content` 的顶级子块序号（与 `PreviewAnchor.block` 同一坐标系），
  /// HTML 是「全文第几个标题」（页面按标题元素滚动，见 `html_anchor.dart`）。
  final int block;

  /// 页内锚点 id（Markdown 由模板生成 GitHub 风格 slug；HTML 用作者自己的 id）。
  ///
  /// 目录点击不靠它（直接用 [block] 滚动），留着是为了排查「文档里 `[x](#小节)`
  /// 点不动」这类问题。
  final String id;

  /// 这个标题在**源码里**的起始行号（1 起；0 = 算不出来，如 HTML 预览）。
  final int line;

  @override
  bool operator ==(Object other) =>
      other is OutlineEntry &&
      other.level == level &&
      other.text == text &&
      other.block == block &&
      other.id == id &&
      other.line == line;

  @override
  int get hashCode => Object.hash(level, text, block, id, line);

  @override
  String toString() => 'OutlineEntry(h$level「$text」@$block/$line)';
}

/// 一篇文档的章节清单。
@immutable
class DocumentOutline {
  const DocumentOutline(this.entries);

  final List<OutlineEntry> entries;

  /// 没有章节：空文档、纯段落、或还没收到清单回执。
  static const DocumentOutline empty = DocumentOutline(<OutlineEntry>[]);

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  int get length => entries.length;

  /// 内容是否与 [other] 一样（同序、同层级、同标题、同块号）。
  ///
  /// **为什么要它，而不是比对象身份**：模板每渲一次页就回传一份**新**清单 —— 换字号、
  /// 换底色、系统主题切换（应用默认「跟随系统」）都会整页重渲。用 `identical` 判「换没
  /// 换清单」，这些重渲都会被当成「换了一篇」，折叠状态随之清空；读者看到的是「划了
  /// 一会儿再打开抽屉，折叠没了」。按内容比才对得上本意：内容变了才叫换了清单。
  bool sameContentAs(DocumentOutline other) {
    if (identical(this, other)) {
      return true;
    }
    if (entries.length != other.entries.length) {
      return false;
    }
    for (int i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) {
        return false;
      }
    }
    return true;
  }

  /// 缩进基准层 —— 清单里**最外层**标题的层级。
  ///
  /// 不写死 1：很多文档从 `##` 起步（README 常见），按 1 算会让整篇多缩进一层。
  int get baseLevel =>
      entries.isEmpty ? 1 : entries.map((OutlineEntry e) => e.level).reduce(math.min);

  /// 第 [index] 条相对基准层的缩进层数（0 起）；越界按 0。
  ///
  /// 上限 3：再深的标题在手机竖屏上会挤成一条缝，缩进到此为止。
  int indentOf(int index) {
    if (index < 0 || index >= entries.length) {
      return 0;
    }
    final int depth = entries[index].level - baseLevel;
    return depth.clamp(0, 3);
  }
}
