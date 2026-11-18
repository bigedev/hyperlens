/// 预览里的**地址**：读者停在哪一处，以及每帧的观测量。
///
/// 两件事分开表达，是这套模型唯一想守住的东西：
///
/// - **地址**（[PreviewPosition]）只有两种：Markdown 的源码行 [SourceAddress]、
///   HTML 的 DOM 路径 [DomAddress]。它会被持久化、会跨会话、会跨到源码视图。
/// - **观测量**（[PreviewViewport]）每帧都变，只服务「现在读到第几节」的高亮。
///
/// **为什么不再留「像素兜底」**：旧模型把 `block` / `offset` / `scrollY` 和 `line`
/// 平铺在同一个类里，看起来同等重要，实际后三者只是「前一个算不出来时的退路」。
/// 而那条退路在真机上从没被走到过（每块至少拿得到第 1 行），却给每个调用方多出
/// 「这次是不是猜的」这个分支；唯一真会失败的场景（文件已被改过）里，它还会把
/// 读者扔到与新文档毫无关系的位置。现在算不出来就是「回顶部 + 日志」，行为可解释。
///
/// 用 sealed 而不是「两个可空字段」：后者允许「两个都空」这个非法状态，只能靠断言
/// 守；sealed 让类型直接排除它。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// 一份文档里的位置。**要么源码行，要么 DOM 路径**，没有第三种。
@immutable
sealed class PreviewPosition {
  const PreviewPosition();

  /// 「从头」。
  ///
  /// Markdown 传 [SourceAddress] 的第 1 行；HTML 传 [DomAddress.body]。
  /// **不能省**：同一个 WebView 实例会把上一篇的滚动位置留给下一篇（真机实测
  /// 停在半腰），不显式说一句「回到开头」，新文档就继承旧位置。
  static const PreviewPosition top = SourceAddress(1);

  /// 写进模板载荷的形态（`payload.restore`）。
  ///
  /// Markdown 模板只认 `line`、HTML 脚本只认 `path` —— 各自忽略不认识的键，
  /// 所以这里不必按文档类型分叉。
  Map<String, Object?> toJson();

  /// 解析一条回执 / 一份旧记忆；认不出来返回 null（调用方按「没有地址」处理）。
  ///
  /// 兼容旧 JSON：老记忆里 `line` 与 `block` / `offset` / `scrollY` 是平铺的
  /// （见 `docs/plan/preview-plugin-and-ast-plan.md` §9.2）。有 `line` 就换算成
  /// [SourceAddress]，只剩像素的（老版 HTML 记忆）直接算「无地址」→ 回顶部。
  static PreviewPosition? tryParse(Object? value) {
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
    final Object? path = raw['path'];
    if (path is String && path.isNotEmpty) {
      return DomAddress(path);
    }
    final Object? line = raw['line'];
    if (line is num && line.toInt() > 0) {
      return SourceAddress(line.toInt());
    }
    // 只有 block / scrollY 的老记忆：地址丢失，回顶部比落到随机位置好
    return null;
  }
}

/// Markdown 的地址：**源码行号**（1 起）。
///
/// 只有它同时满足三件事：跨字号重排仍指向同一段、能换算回像素、能交给源码视图
/// （`CodeAnchor.line`）。所以 Markdown 的持久化位置只有这一个数。
@immutable
final class SourceAddress extends PreviewPosition {
  const SourceAddress(this.line) : assert(line >= 1, '行号 1 起，没有「第 0 行」');

  final int line;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'line': line};

  @override
  bool operator ==(Object other) => other is SourceAddress && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'SourceAddress(line: $line)';
}

/// HTML 的地址：**DOM 路径**，例如 `body>div#main>h2:nth(3)`。
///
/// 作者页面没有源码行号（`<script>` 摘掉后行号无从换算），也没有「第几块」的结构
/// 约定，只能按节点定位。段内 `:nth(k)` 是**同名兄弟里的第 k 个**（1 起），
/// 有 `id` 时用 `#id`（更稳，作者改结构也不至于全错）。
@immutable
final class DomAddress extends PreviewPosition {
  const DomAddress(this.path);

  /// 整页的「从头」。
  static const DomAddress body = DomAddress('body');

  final String path;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'path': path};

  @override
  bool operator ==(Object other) => other is DomAddress && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'DomAddress($path)';
}

/// 一帧的**观测量**：视口顶 / 底那一带在源码里的行号。
///
/// 只服务「现在读到第几节」的高亮（中线判据，见 `MarkdownOutline.sectionAtViewport`）。
/// **不持久化、不写进载荷、不进相等性** —— 它每帧都在变，进了相等性会让「位置没变、
/// 只是屏幕高度变了」被当成换了一处。
///
/// `null` 表示这条回执没带 / 这种文档没有行号（HTML 侧恒为 null）。
@immutable
class PreviewViewport {
  const PreviewViewport({this.topLine, this.bottomLine});

  final int? topLine;
  final int? bottomLine;

  static const PreviewViewport empty = PreviewViewport();

  /// 解析 `top <凭据> <json>` 里的观测字段；缺字段一律按 null。
  static PreviewViewport parse(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    final Object? top = raw['line'];
    final Object? bottom = raw['bottomLine'];
    return PreviewViewport(
      topLine: top is num && top.toInt() > 0 ? top.toInt() : null,
      bottomLine: bottom is num && bottom.toInt() > 0 ? bottom.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PreviewViewport &&
      other.topLine == topLine &&
      other.bottomLine == bottomLine;

  @override
  int get hashCode => Object.hash(topLine, bottomLine);

  @override
  String toString() =>
      'PreviewViewport(topLine: $topLine, bottomLine: $bottomLine)';
}
