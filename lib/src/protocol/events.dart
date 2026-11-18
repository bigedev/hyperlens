/// 页面 → Dart 的回执：**Markdown 与 HTML 共用一套信封与一套解析**。
///
/// 信封（见 [HyperlensBridge]）：
///
/// ```text
/// <前缀><凭据> <载荷>        // 带凭据（Markdown）
/// <前缀>- <载荷>             // 无凭据（HTML：整页重载，没有「上一页还在报」）
/// <前缀><载荷>               // 只有 link / anchor 这两条不带凭据
/// ```
///
/// 为什么是一个 parse 而不是每种文档一个：这两条通道的**概念**是同一套 ——
/// 页面就绪、阅读位置、章节清单、语法树、命中高亮。分成两个解析器之后，
/// 「HTML 的 `outline` 被 Markdown 的拆包规则切歪」这类错会在没有任何报错的情况下
/// 发生（拆包靠「第一个空格」，而清单 JSON 里只要有空格就会被切开）。
///
/// 与「收到之后怎么办」分开：这里只做格式解析，纯函数，能在主机上单测；
/// 会话、看门狗、导航策略留给调用方。
library;

import 'dart:convert';

import '../model/html_outline.dart';
import '../model/markdown_outline.dart';
import '../model/preview_position.dart';
import '../model/preview_syntax.dart';
import 'hyperlens_bridge.dart';

/// 一条预览回执。
sealed class PreviewEvent {
  const PreviewEvent();

  /// 解析一条回执。认不出来的一律归到 [PreviewUnknownMessage]（上层当状态文字显示）。
  static PreviewEvent parse(String message) {
    if (message.startsWith(HyperlensBridge.receiptPrefix)) {
      final (String?, String?) split =
          _split(message, HyperlensBridge.receiptPrefix);
      if (split.$2 == null) {
        return PreviewUnknownMessage(message);
      }
      return PreviewRenderReady(token: split.$1, result: split.$2!);
    }
    if (message.startsWith(HyperlensBridge.linkPrefix)) {
      final String encoded =
          message.substring(HyperlensBridge.linkPrefix.length);
      String href = encoded;
      try {
        href = Uri.decodeComponent(encoded);
      } on ArgumentError {
        // 转义异常时按原样交给上层，上层还会再判一次
      }
      return PreviewLinkTapped(href);
    }
    if (message.startsWith(HyperlensBridge.positionPrefix)) {
      final (String?, String?) split =
          _split(message, HyperlensBridge.positionPrefix);
      if (split.$2 == null) {
        return PreviewUnknownMessage(message);
      }
      final Object? raw = _decodeOrNull(split.$2!);
      return PreviewPositionReported(
        token: split.$1,
        position: PreviewPosition.tryParse(raw),
        viewport: PreviewViewport.parse(raw),
        section: _sectionOf(raw),
      );
    }
    if (message.startsWith(HyperlensBridge.outlinePrefix)) {
      final (String?, String?) split =
          _split(message, HyperlensBridge.outlinePrefix);
      if (split.$2 == null) {
        return PreviewUnknownMessage(message);
      }
      return PreviewOutlineReported(
        token: split.$1,
        outline: _parseOutline(split.$2!),
      );
    }
    if (message.startsWith(HyperlensBridge.astPrefix)) {
      final (String?, String?) split =
          _split(message, HyperlensBridge.astPrefix);
      if (split.$2 == null) {
        return PreviewUnknownMessage(message);
      }
      return PreviewSyntaxReported(
        token: split.$1,
        tree: PreviewSyntaxTree.parse(split.$2!),
      );
    }
    if (message.startsWith(HyperlensBridge.focusPrefix)) {
      final (String?, String?) split =
          _split(message, HyperlensBridge.focusPrefix);
      if (split.$2 == null) {
        return PreviewUnknownMessage(message);
      }
      return PreviewFocusApplied(token: split.$1, count: int.tryParse(split.$2!.trim()));
    }
    if (message.startsWith(HyperlensBridge.anchorPrefix)) {
      return PreviewAnchorScrolled(
        message.substring(HyperlensBridge.anchorPrefix.length),
      );
    }
    return PreviewUnknownMessage(message);
  }

  /// 把 `<前缀><凭据> <载荷>` 拆成（凭据, 载荷）；凭据为 [HyperlensBridge.noToken]
  /// 时返回 null（= 这份文档没有凭据）。
  ///
  /// 格式不对（没有分隔空格）返回 `(null, null)` —— 上层归到 [PreviewUnknownMessage]，
  /// 别把「认不出的消息」当成「没有凭据的正常消息」。
  static (String?, String?) _split(String message, String prefix) {
    final String rest = message.substring(prefix.length);
    final int sep = rest.indexOf(' ');
    if (sep <= 0) {
      return (null, null);
    }
    final String token = rest.substring(0, sep);
    final String payload = rest.substring(sep + 1);
    if (token == HyperlensBridge.noToken) {
      return (null, payload);
    }
    return (token, payload);
  }

  /// 把 JSON 文本解成对象；认不出来返回 null（各字段自己按「没带」处理）。
  static Object? _decodeOrNull(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// 「现在读到第几节」（HTML 页面自己算，0 起；Markdown 侧由调用方按大纲算，
  /// 回执里没有这个字段 → null）。
  static int? _sectionOf(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? sec = raw['sec'];
    if (sec is! num) {
      return null;
    }
    final int index = sec.toInt();
    return index < 0 ? null : index;
  }

  /// 章节清单：两种格式**同一条回执**，按条目上的坐标判断来源。
  ///
  /// Markdown 的条目带 `line`，HTML 的带 `path`（见 `PreviewOutlineEntry.address`）；
  /// 空清单按 Markdown 处理 —— 两种空清单在调用方眼里没有区别，而
  /// `PreviewMarkdownOutline` 是最早的形状。
  static PreviewOutline _parseOutline(String payload) {
    Object? raw;
    try {
      raw = jsonDecode(payload);
    } on FormatException {
      return PreviewMarkdownOutline.empty;
    }
    for (final Object? entry in _entriesOf(raw)) {
      if (entry is Map && (entry['path'] is String) &&
          (entry['path'] as String).isNotEmpty) {
        return PreviewHtmlOutline.parse(raw);
      }
    }
    return PreviewMarkdownOutline.parse(raw);
  }

  static List<Object?> _entriesOf(Object? raw) {
    if (raw is List) {
      return raw;
    }
    if (raw is Map) {
      final Object? entries = raw['entries'];
      if (entries is List) {
        return entries;
      }
    }
    return const <Object?>[];
  }
}

/// 渲染就绪：[result] 是页面给的一句话（`ok（…）` / `empty` / `no-marked` / `异常: …`）。
///
/// 两种文档都发这一条：Markdown 是「脚本跑到了末尾」，HTML 是「注入的脚本跑到了
/// 末尾」—— 对调用方是同一个意思：这次提交的页面真的活着。
final class PreviewRenderReady extends PreviewEvent {
  const PreviewRenderReady({required this.token, required this.result});

  /// null = 这份文档没有凭据（HTML）。
  final String? token;
  final String result;

  @override
  bool operator ==(Object other) =>
      other is PreviewRenderReady && other.token == token && other.result == result;

  @override
  int get hashCode => Object.hash(token, result);

  @override
  String toString() => 'PreviewRenderReady($token, $result)';
}

/// 用户点了链接（[href] 已解码）。
final class PreviewLinkTapped extends PreviewEvent {
  const PreviewLinkTapped(this.href);

  final String href;

  @override
  bool operator ==(Object other) => other is PreviewLinkTapped && other.href == href;

  @override
  int get hashCode => href.hashCode;

  @override
  String toString() => 'PreviewLinkTapped($href)';
}

/// 阅读位置回执：**地址**（[position]）与**这一帧的观测量**（[viewport]）分开带。
///
/// [position] 为 null 表示 JSON 认不出来（丢弃即可，不要当顶部）；
/// [viewport] 恒非 null（缺字段就是空观测），它只服务章节高亮；
/// [section] 是「现在读到第几节」（0 起），HTML 页面自己算，Markdown 侧为 null
/// —— 那边由调用方拿 [PreviewViewport] 与大纲算（中线判据）。
final class PreviewPositionReported extends PreviewEvent {
  const PreviewPositionReported({
    required this.token,
    required this.position,
    this.viewport = PreviewViewport.empty,
    this.section,
  });

  /// null = 这份文档没有凭据（HTML）。
  final String? token;
  final PreviewPosition? position;
  final PreviewViewport viewport;
  final int? section;

  @override
  bool operator ==(Object other) =>
      other is PreviewPositionReported &&
      other.token == token &&
      other.position == position &&
      other.viewport == viewport &&
      other.section == section;

  @override
  int get hashCode => Object.hash(token, position, viewport, section);

  @override
  String toString() =>
      'PreviewPositionReported($token, $position, section: $section)';
}

/// 章节清单回执。
///
/// [outline] 的运行时类型说明来源：[PreviewMarkdownOutline] 的条目带源码行，
/// [PreviewHtmlOutline] 的带 DOM 路径 —— 调用方按 [PreviewOutline] 的公共成员使用即可，
/// 要区分来源时用 `is`（例如「HTML 没有行号，别拿它做源码交接」）。
final class PreviewOutlineReported extends PreviewEvent {
  const PreviewOutlineReported({required this.token, required this.outline});

  /// null = 这份文档没有凭据（HTML）。
  final String? token;
  final PreviewOutline outline;

  @override
  bool operator ==(Object other) =>
      other is PreviewOutlineReported &&
      other.token == token &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(token, outline);

  @override
  String toString() => 'PreviewOutlineReported($token, $outline)';
}

/// 语法树回执（骨架模式）。
final class PreviewSyntaxReported extends PreviewEvent {
  const PreviewSyntaxReported({required this.token, required this.tree});

  /// null = 这份文档没有凭据（HTML）。
  final String? token;
  final PreviewSyntaxTree tree;

  @override
  bool operator ==(Object other) =>
      other is PreviewSyntaxReported && other.token == token && other.tree == tree;

  @override
  int get hashCode => Object.hash(token, tree);

  @override
  String toString() => 'PreviewSyntaxReported($token, $tree)';
}

/// 搜索命中已高亮并滚到；[count] 是全文亮起来的处数（null = 回执读不出数字）。
///
/// **只用于日志**：高亮是增强，没亮起来也不该让页面进入某种「失败态」——
/// 读者手里的文档已经能读，别为一条定位再去打扰他。
final class PreviewFocusApplied extends PreviewEvent {
  const PreviewFocusApplied({required this.token, required this.count});

  /// null = 这份文档没有凭据（HTML）。
  final String? token;
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is PreviewFocusApplied && other.token == token && other.count == count;

  @override
  int get hashCode => Object.hash(token, count);

  @override
  String toString() => 'PreviewFocusApplied($token, $count)';
}

/// 页内锚点已滚动到位（只用于日志）。
final class PreviewAnchorScrolled extends PreviewEvent {
  const PreviewAnchorScrolled(this.target);

  final String target;

  @override
  bool operator ==(Object other) =>
      other is PreviewAnchorScrolled && other.target == target;

  @override
  int get hashCode => target.hashCode;

  @override
  String toString() => 'PreviewAnchorScrolled($target)';
}

/// 认不出的回执：原样交给上层当状态文字（页面与 Dart 版本不同步时别炸）。
final class PreviewUnknownMessage extends PreviewEvent {
  const PreviewUnknownMessage(this.raw);

  final String raw;

  @override
  bool operator ==(Object other) =>
      other is PreviewUnknownMessage && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'PreviewUnknownMessage($raw)';
}
