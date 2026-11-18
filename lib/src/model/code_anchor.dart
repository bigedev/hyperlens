import 'dart:convert';

import 'package:meta/meta.dart';

/// 代码视图里「读者滚到哪」的一帧位置。
///
/// **为什么需要**：源码视图是 `re_editor` 的一次性装配，换一篇文件就是新建
/// `CodeLineEditingController` —— 从内链/Zen 模式/编辑态返回时，读者被扔回第 1 行，
/// 长文件里还得自己再翻一遍（与 [PreviewPosition] 对 Markdown 解决的问题完全相同）。
///
/// **为什么主力还是「垂直偏移 + 当时的字号」，行号只是补充**：
/// - 代码视图不折行，行高只跟字号走，所以同一字号下像素偏移就是稳定位置；
/// - 字号变了整篇行高按比例缩放，同一个偏移会在另一行上 —— 记下当时的字号，
///   恢复时按比例换算，落回的还是同一行（见 [resolveOffset]）。这条路不碰
///   re_editor 的任何内部结构，稳。
/// - 换成「只记行号」不值当：re_editor 没有公开 offset → line 的入口，唯一的标尺是
///   `CodeIndicatorValue`（只有可见段落、且随滚动刷新），它还没就绪时就算不出行号。
///   所以行号只在**跨通道**时才用（见 [line]），并且在 CodeView 里现算，不在这里猜行高。
///
/// 与 [PreviewPosition] 一样是**纯 Dart**：可以在主机上单测（见
/// `test/model/code_anchor_test.dart`），不依赖 Flutter 或 WebView。
@immutable
class CodeAnchor {
  const CodeAnchor({
    required this.offset,
    required this.fontSize,
    this.line = 0,
    this.screenBottomLine = 0,
  });

  /// 当时的垂直滚动偏移（逻辑像素，即 `ScrollController.offset`）。
  final double offset;

  /// 当时正文的字号（逻辑像素）。恢复时按它的比例换算 [offset]。
  ///
  /// 0 表示「不知道」：此时只能原样使用 [offset]（老版本写下的记忆、
  /// 或调用方没给字号）。不要把它当合法字号传进 [resolveOffset] 的除法。
  final double fontSize;

  /// 视口顶端那一行的行号（1 起；0 = 算不出来）。
  ///
  /// 与 [offset] 是同一件事的两种刻度：像素偏移只对本机字号/字体有效，
  /// 而**行号是预览侧也认的坐标** —— 读者在 Markdown 预览里读到某段切到源码，
  /// 交接用的就是它（见 `SourceAddress.line`）。换算靠 CodeView 里的标尺
  /// （re_editor 的可见段落），不在这里猜行高。
  final int line;

  /// 视口**最后一行**的行号（1 起；0 = 算不出来）。
  ///
  /// 只给大纲判「下一节的标题是否已经上屏」用（见 `CodeOutline.currentForScreen`）。
  /// 它是**这一帧的观测量**，不是位置本身：**不持久化、不参与相等性** —— 恢复位置只要
  /// [offset] 与 [line] 就够了。
  final int screenBottomLine;

  /// 「从头看」：新打开的文件要**显式**落回顶部。
  static const CodeAnchor top = CodeAnchor(offset: 0, fontSize: 0);

  /// 把记录时的偏移换算到 [currentFontSize] 下的偏移。
  ///
  /// 行高与字号成正比 ⇒ 偏移按字号比例缩放就落在同一行上。字号未知（≤0）时
  /// 原样返回 —— 宁可差几行，也不要因为除零把位置算成 NaN（`jumpTo` 会抛）。
  double resolveOffset(double currentFontSize) {
    if (fontSize <= 0 || currentFontSize <= 0) {
      return offset;
    }
    return offset * (currentFontSize / fontSize);
  }

  /// 解析一条持久化的锚点；解析不出来返回 null（当作「没有位置」）。
  ///
  /// 收的通常是 `toJson` 出来的 map；也容忍 JSON 字符串（与 `PreviewAnchor`
  /// 同一个口径，方便两边共用一套读写）。
  static CodeAnchor? tryParse(Object? value) {
    Object? raw = value;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (raw is! Map) {
      return null;
    }
    final Object? offset = raw['offset'];
    if (offset is! num) {
      // 少关键字段：宁可当「没有位置」（回到顶部），也不要还原到随机地方
      return null;
    }
    final Object? fontSize = raw['fontSize'];
    final Object? line = raw['line'];
    return CodeAnchor(
      offset: offset.toDouble(),
      fontSize: fontSize is num ? fontSize.toDouble() : 0,
      // 老版本写下的位置没有行号：按「算不出来」处理，退回像素偏移
      line: line is num ? line.toInt() : 0,
    );
  }

  /// 写进浏览记忆（`data/prefs/browse_prefs.dart`）的形态。
  ///
  /// [line] 为 0（算不出来）时不写这个键 —— 与 `PreviewAnchor.toJson` 同一个口径。
  Map<String, Object?> toJson() => <String, Object?>{
        'offset': offset,
        'fontSize': fontSize,
        if (line > 0) 'line': line,
      };

  @override
  bool operator ==(Object other) =>
      other is CodeAnchor &&
      other.offset == offset &&
      other.fontSize == fontSize &&
      other.line == line;

  @override
  int get hashCode => Object.hash(offset, fontSize, line);

  @override
  String toString() => 'CodeAnchor(offset: ${offset.round()}, '
      'fontSize: ${fontSize.round()}, line: $line)';
}
