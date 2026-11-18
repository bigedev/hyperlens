import 'dart:convert';

import '../model/markdown_outline.dart';
import '../model/preview_position.dart';
import '../model/preview_syntax.dart';
import '../protocol/hyperlens_bridge.dart';

/// 页面 → Dart 的回执（模板 `markdown_view.html` 里 `HyperLens.postMessage` 的约定）。
///
/// 从 `markdown_view.dart` 拆出来：这些消息的**格式解析**与「收到之后怎么办」是两件事，
/// 前者是纯函数（能直接在主机上测，不用起 WebView），后者牵扯会话、看门狗与导航策略，
/// 留在 State 里。
///
/// 约定（前缀后跟一个空格）：
/// - `render <凭据> <结果>` —— 页面**跑到了末尾那段脚本**，是「这次加载真的渲染了」的
///   唯一凭据（见 `markdown_view.dart` 的渲染看门狗）；
/// - `link <编码后的 href>` —— 链接被捕获阶段拦下，交给上层判断去外链还是仓内跳转；
/// - `top <凭据> <位置 JSON>` —— 阅读位置（`line`）与这一帧的观测量（`bottomLine`）；
/// - `outline <凭据> <清单 JSON>` —— 章节清单（一篇一次）；
/// - `ast <凭据> <树 JSON>` —— 语法树骨架（Markdown，一篇一次）；HTML 那条没有
///   凭据，直接是 `ast <树 JSON>`，见 [_splitAst]；
/// - `focus <凭据> <处数>` —— 搜索命中已高亮并滚到（处数为 0 表示没找到），只记日志；
/// - `anchor <目标>` —— 页内锚点已由页面自己滚好，只记日志。
///
/// 三条带凭据的消息必须校验凭据：换文档时旧页面还在收尾，它的位置 / 清单属于上一篇。
sealed class MarkdownEvent {
  const MarkdownEvent();

  /// 解析一条回执。认不出来的一律归到 [UnknownMessage]（上层当状态文字显示）。
  static MarkdownEvent parse(String message) {
    if (message.startsWith(HyperlensBridge.receiptPrefix)) {
      final (String? token, String? rest) = _splitToken(
        message,
        HyperlensBridge.receiptPrefix,
      );
      if (token == null || rest == null) {
        return UnknownMessage(message);
      }
      return RenderReady(token: token, result: rest);
    }
    if (message.startsWith(_linkPrefix)) {
      final String encoded = message.substring(_linkPrefix.length);
      String href = encoded;
      try {
        href = Uri.decodeComponent(encoded);
      } on ArgumentError {
        // 转义异常时按原样交给上层，上层还会再判一次
      }
      return LinkTapped(href);
    }
    if (message.startsWith(_topPrefix)) {
      final (String? token, String? rest) = _splitToken(message, _topPrefix);
      if (token == null || rest == null) {
        return UnknownMessage(message);
      }
      return PositionReported(
        token: token,
        position: PreviewPosition.tryParse(rest),
        viewport: PreviewViewport.parse(_decodeOrNull(rest)),
      );
    }
    if (message.startsWith(_outlinePrefix)) {
      final (String? token, String? rest) = _splitToken(message, _outlinePrefix);
      if (token == null || rest == null) {
        return UnknownMessage(message);
      }
      return OutlineReported(token: token, outline: MarkdownOutline.parse(rest));
    }
    if (message.startsWith(_astPrefix)) {
      final (String? token, String? rest) = _splitAst(message);
      if (rest == null) {
        return UnknownMessage(message);
      }
      return SyntaxReported(
        token: token,
        tree: PreviewSyntaxTree.parse(rest),
      );
    }
    if (message.startsWith(_focusPrefix)) {
      final (String? token, String? rest) = _splitToken(message, _focusPrefix);
      if (token == null || rest == null) {
        return UnknownMessage(message);
      }
      return FocusApplied(token: token, count: int.tryParse(rest.trim()));
    }
    if (message.startsWith(_anchorPrefix)) {
      return AnchorScrolled(message.substring(_anchorPrefix.length));
    }
    return UnknownMessage(message);
  }

  /// 把 JSON 文本解成对象；认不出来返回 null（观测量那边按「没带」处理）。
  static Object? _decodeOrNull(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// 拆 `ast` 回执：Markdown 是 `<凭据> <JSON>`，HTML 那条**没有凭据**
  /// （整页重载，不存在上一页还在报的时序问题）。
  ///
  /// 判据是「空格后第一截能不能直接当 JSON 开头」：凭据形如
  /// `<序号>:<指纹>`，永远不以 `{` / `[` 开头，所以不会误吞。
  static (String?, String?) _splitAst(String message) {
    final String rest = message.substring(_astPrefix.length);
    if (rest.startsWith('{') || rest.startsWith('[')) {
      return (null, rest);
    }
    return _splitToken(message, _astPrefix);
  }

  /// 把 `<前缀><凭据> <其余>` 拆成两截；格式不对（没有分隔空格）返回两个 null。
  static (String?, String?) _splitToken(String message, String prefix) {
    final String rest = message.substring(prefix.length);
    final int sep = rest.indexOf(' ');
    if (sep <= 0) {
      return (null, null);
    }
    return (rest.substring(0, sep), rest.substring(sep + 1));
  }

  // 回执前缀全部定义在 [HyperlensBridge]：模板是资源文件、Dart 这边也只有一份，
  // 两边靠那些常量与模板注释互相指认。
  static const String _linkPrefix = HyperlensBridge.linkPrefix;
  static const String _topPrefix = HyperlensBridge.positionPrefix;
  static const String _outlinePrefix = HyperlensBridge.outlinePrefix;
  static const String _astPrefix = HyperlensBridge.astPrefix;
  static const String _focusPrefix = HyperlensBridge.focusPrefix;
  static const String _anchorPrefix = HyperlensBridge.anchorPrefix;
}

/// 渲染回执：[result] 是页面给的一句话（`ok（…）` / `empty` / `no-marked` / `异常: …`）。
final class RenderReady extends MarkdownEvent {
  const RenderReady({required this.token, required this.result});

  final String token;
  final String result;

  @override
  bool operator ==(Object other) =>
      other is RenderReady && other.token == token && other.result == result;

  @override
  int get hashCode => Object.hash(token, result);

  @override
  String toString() => 'RenderReady($token, $result)';
}

/// 用户点了链接（[href] 已解码）。
final class LinkTapped extends MarkdownEvent {
  const LinkTapped(this.href);

  final String href;

  @override
  bool operator ==(Object other) => other is LinkTapped && other.href == href;

  @override
  int get hashCode => href.hashCode;

  @override
  String toString() => 'LinkTapped($href)';
}

/// 阅读位置回执：**地址**（[position]）与**这一帧的观测量**（[viewport]）分开带。
///
/// [position] 为 null 表示 JSON 认不出来（丢弃即可，不要当顶部）；
/// [viewport] 恒非 null（缺字段就是空观测），它只服务章节高亮。
final class PositionReported extends MarkdownEvent {
  const PositionReported({
    required this.token,
    required this.position,
    this.viewport = PreviewViewport.empty,
  });

  final String token;
  final PreviewPosition? position;
  final PreviewViewport viewport;

  @override
  bool operator ==(Object other) =>
      other is PositionReported &&
      other.token == token &&
      other.position == position &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(token, position, viewport);

  @override
  String toString() => 'PositionReported($token, $position)';
}

/// 章节清单回执。
final class OutlineReported extends MarkdownEvent {
  const OutlineReported({required this.token, required this.outline});

  final String token;
  final MarkdownOutline outline;

  @override
  bool operator ==(Object other) =>
      other is OutlineReported &&
      other.token == token &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(token, outline);

  @override
  String toString() => 'OutlineReported($token, $outline)';
}

/// 语法树回执（骨架模式）。
///
/// Markdown 带凭据（[token] 非 null），与 `top` / `outline` 同一条规则：换文档时旧
/// 页面的回执必须被丢弃。HTML 那条没有凭据（[token] 为 null）—— 每次提交都是整页
/// 重载，不存在「上一页还在报」。
final class SyntaxReported extends MarkdownEvent {
  const SyntaxReported({required this.token, required this.tree});

  final String? token;
  final PreviewSyntaxTree tree;

  @override
  bool operator ==(Object other) =>
      other is SyntaxReported && other.token == token && other.tree == tree;

  @override
  int get hashCode => Object.hash(token, tree);

  @override
  String toString() => 'SyntaxReported($token, $tree)';
}

/// 搜索命中已高亮并滚到；[count] 是全文亮起来的处数（null = 回执读不出数字）。
///
/// **只用于日志**：高亮是增强，没亮起来也不该让页面进入某种「失败态」——
/// 读者手里的文档已经能读，别为一条定位再去打扰他。
final class FocusApplied extends MarkdownEvent {
  const FocusApplied({required this.token, required this.count});

  final String token;
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is FocusApplied && other.token == token && other.count == count;

  @override
  int get hashCode => Object.hash(token, count);

  @override
  String toString() => 'FocusApplied($token, $count)';
}

/// 页内锚点已滚动到位（只用于日志）。
final class AnchorScrolled extends MarkdownEvent {
  const AnchorScrolled(this.target);

  final String target;

  @override
  bool operator ==(Object other) =>
      other is AnchorScrolled && other.target == target;

  @override
  int get hashCode => target.hashCode;

  @override
  String toString() => 'AnchorScrolled($target)';
}

/// 认不出的回执：原样交给上层当状态文字（页面与 Dart 版本不同步时别炸）。
final class UnknownMessage extends MarkdownEvent {
  const UnknownMessage(this.raw);

  final String raw;

  @override
  bool operator ==(Object other) =>
      other is UnknownMessage && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'UnknownMessage($raw)';
}
