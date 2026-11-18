import 'dart:convert';

import 'package:meta/meta.dart';

/// Markdown 预览里「读者停在哪一块」的一帧位置。
///
/// **为什么需要**：预览是一次性的 `loadHtmlString` 提交（由宿主一次性提交整页），
/// 换一篇文档就是整页重建 —— 从内链跳走再按返回时，读者被弹回文档开头，
/// 还得自己重新翻一遍（真机实测：返回后与「刚打开这篇」逐像素一致）。
/// 把离开时看到的位置记下来，返回时按同一块放回去。
///
/// **为什么记「块 + 块内偏移」而不是 `window.scrollY`**：阅读区有
/// 小/中/大 字号偏好，字号一变整篇重排，同一个 scrollY 落在完全不同的段落上；
/// 而「视口顶端是第几块 + 块内滚过去多少」重排后仍是同一段。与仓库里既有的
/// `CodeFocus`（按行定位搜索命中）是同一个思路。
///
/// 字段与模板 `assets/web/markdown_view.html` 里的 `mdTopAnchor()` /
/// `mdRestore()` 一一对应，改一边必须改另一边。
///
/// 除块号外还带一个 [line]（源码行号）：预览与**源码视图**（[CodeAnchor]）本来
/// 各记各的位置，读者在预览里读到一段、切到源码却落回「上次源码停的地方」。
/// 行号是两条通道都认的坐标，切视图时用它交接（见 `file_document_view.dart`
/// 的 `_handOff`）。
@immutable
class PreviewAnchor {
  const PreviewAnchor({
    required this.block,
    required this.offset,
    required this.scrollY,
    this.line = 0,
    this.bottomLine = 0,
  });

  /// 视口顶端所在的那个**顶级子块**（h1 / p / ul / pre / table…）的序号。
  ///
  /// -1 表示算不出来（文档比一屏还短、或页面结构陌生），此时只能靠 [scrollY]。
  final int block;

  /// 该块的顶端被滚过去多少（逻辑像素）。
  ///
  /// 只靠 [block] 不够：一个长代码块能占好几屏，块号不变而位置差很远。
  final double offset;

  /// 当时的 `window.scrollY`：页面结构与记录时对不上（[block] 越界）时的退路。
  final double scrollY;

  /// 视口顶端那一段在**源码里的起始行号**（1 起；0 = 算不出来）。
  ///
  /// 预览与源码是两条渲染通道，各自只记自己那套坐标（这里的块号 + 块内偏移、
  /// [CodeAnchor] 的像素偏移），互相听不懂。行号是两边都认的公共坐标：
  /// 读者在预览里读到某段、切到源码，就靠它落到同一处，反之亦然。
  ///
  /// 页面渲染时用 marked 的词法结果给每个顶级块记下起始行（模板里的
  /// `mdBlockLines`），上报时按块内行数插值算出来 —— 所以它比 [block] 细，
  /// 长段落 / 长代码块里也能对上号。
  final int line;

  /// 视口**底部**那一段在源码里的行号（1 起；0 = 算不出来）。
  ///
  /// 只给章节高亮判「下一节的标题上屏没有」用（见
  /// `MarkdownOutline.currentForScreen`）。与 [CodeAnchor.screenBottomLine] 同性质：
  /// **这一帧的观测量** —— 不持久化、不写进 `payload.restore`、不参与相等性。
  final int bottomLine;

  /// 「从头看」：新打开的文档要**显式**落回顶部。
  ///
  /// 不显式说一句的话，ArkWeb 会把上一篇的滚动位置留给下一篇（实测：跳转后的
  /// 新文档停在半中腰，scrollY ≈ 700），读者一进来就找不到开头。
  /// 注意落位在模板里是「按住一小会儿」（见 `mdHold`）—— 落一次压不住那次回抖。
  static const PreviewAnchor top =
      PreviewAnchor(block: -1, offset: 0, scrollY: 0);

  /// 解析 JS 回传的一条锚点；解析不出来返回 null（当作「没有位置」）。
  ///
  /// 收的通常是 JS 侧 `JSON.stringify` 出来的**字符串**，也容忍已解好的 Map。
  static PreviewAnchor? tryParse(Object? value) {
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
    final Object? block = raw['block'];
    final Object? scrollY = raw['scrollY'];
    if (block is! num || scrollY is! num) {
      // 少关键字段：宁可当「没有位置」（回到顶部），也不要还原到随机地方
      return null;
    }
    final Object? offset = raw['offset'];
    final Object? line = raw['line'];
    final Object? bottomLine = raw['bottomLine'];
    return PreviewAnchor(
      block: block.toInt(),
      offset: offset is num ? offset.toDouble() : 0,
      scrollY: scrollY.toDouble(),
      // 老版本写下的位置没有行号：按「算不出来」处理，退化为块级还原
      line: line is num ? line.toInt() : 0,
      bottomLine: bottomLine is num ? bottomLine.toInt() : 0,
    );
  }

  /// 写进模板的 `payload.restore`（宿主提交页面时替换）。
  ///
  /// [line] 为 0（算不出来）时**不写这个键**：HTML 预览的锚点和旧版记忆里都没有它，
  /// 少一个键既省载荷，也免得那些只认 `block`/`scrollY` 的通道多出一段噪声。
  Map<String, Object?> toJson() => <String, Object?>{
        'block': block,
        'offset': offset,
        'scrollY': scrollY,
        if (line > 0) 'line': line,
      };

  /// [bottomLine] **不在相等性里**：它是每帧的观测量（同 [CodeAnchor.screenBottomLine]），
  /// 进了相等性会让「位置没变、只是屏幕高度变了」被当成换了一处。
  @override
  bool operator ==(Object other) =>
      other is PreviewAnchor &&
      other.block == block &&
      other.offset == offset &&
      other.scrollY == scrollY &&
      other.line == line;

  @override
  int get hashCode => Object.hash(block, offset, scrollY, line);

  @override
  String toString() => 'PreviewAnchor(block: $block, '
      'offset: ${offset.round()}, scrollY: ${scrollY.round()}, '
      'line: $line, bottomLine: $bottomLine)';
}
