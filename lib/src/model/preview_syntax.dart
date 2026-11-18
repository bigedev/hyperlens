/// 预览的**语法树**：一次解析得出的结构。
///
/// 存在的理由只有一条：渲染、大纲、锚点、AST 必须共享**同一次解析**，否则同一篇
/// 文档里的「第 12 行」在两处可能指向不同内容。所以这里只有**数据**，没有解析器 ——
/// Markdown 的树由页面用同一个 `marked.lexer()` 顺手收集，HTML 的树由浏览器
/// 自己的 `document` 遍历得出。Dart 侧只负责校验、截断与交付给调用方。
///
/// 与 [PreviewPosition] 的关系：节点上的 `line` 是 Markdown 的源码行（1 起），
/// `path` 是 HTML 的 DOM 路径 —— 与阅读位置**同一套坐标**。HTML 侧 `line` 恒为
/// null（作者页面没有可换算的行号），调用方必须能区分「没有行号」与「行号为 0」
/// —— 后者不存在，行号 1 起。
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'value_equality.dart';

/// 这份树是从哪种文档解析出来的。
///
/// 决定 `line` 还是 `path` 有意义；两者不会同时出现。
enum PreviewSourceKind {
  markdown,
  html;

  /// 回执 / 存档里的写法。认不出来返回 null（调用方按「不知道」处理）。
  static PreviewSourceKind? tryParse(Object? raw) => switch (raw) {
        'markdown' => markdown,
        'html' => html,
        _ => null,
      };

  String get wireName => switch (this) {
        PreviewSourceKind.markdown => 'markdown',
        PreviewSourceKind.html => 'html',
      };
}

/// 树的闸门。**页面侧照这些数字裁剪**，Dart 侧再兜一次底：
/// 一条被改坏的载荷不该把调用方的界面卡住。
///
/// 数值是初值 —— 实施后用三类语料实测（10 KB README / 200 KB 技术文档 /
/// 含 2000 段列表的生成文件），把「解析 + 序列化 + IPC」压在 `render` 回执之后
/// 150 ms 内。超预算就把 `text` 再截短，**而不是取消 AST**。
abstract final class PreviewSyntaxLimits {
  /// 节点数上限：超了就不再下钻，`truncated = true`。
  static const int maxNodes = 50000;

  /// 单节点文本上限（字符）。截断后补省略号。
  static const int maxTextLength = 120;

  /// 载荷总字节上限：超了页面降级为骨架并置 `truncated`。
  static const int maxBytes = 2 << 20;

  /// 最大深度：列表套列表的极端情况，超了停止下钻。
  static const int maxDepth = 8;
}

/// 一处**可疑**——不是「语法错误」。
///
/// Markdown 的解析器从不报错（写错只是被按另一条规则理解），浏览器的 HTML 解析器
/// 更是把所有错误悄悄修好。所以这一层给的是「大概率不是作者想要的样子」，每条
/// 都必须**说得出为什么**（[PreviewSyntaxIssue.detail]），否则宁可不报 —— 一个爱
/// 误报的面板，读者第二次就不看了。
enum PreviewSyntaxIssueKind {
  /// 代码围栏没闭合：marked 会把后面的整篇内容当成代码，表现是「突然整段变灰」。
  unclosedFence('unclosedFence'),

  /// 引用式链接 / 图片没有对应定义，按字面量渲染出来（`[文字][ref]`）。
  unresolvedReference('unresolvedReference'),

  /// 表格某一行与表头的列数不一致：marked 会按表头列数裁掉多出来的单元格。
  tableColumnMismatch('tableColumnMismatch'),

  /// HTML 标签没闭合，或结束标签对不上（浏览器已经修好了，但作者写错了）。
  unclosedTag('unclosedTag'),

  /// 客户端不认识的节点类型（页面与包的版本不同步）。
  unknownNodeType('unknownNodeType'),

  /// 这段 HTML 里的脚本被摘掉了（预览不执行作者脚本），因此内容可能不完整。
  strippedScript('strippedScript');

  const PreviewSyntaxIssueKind(this.wireName);

  final String wireName;

  static PreviewSyntaxIssueKind? tryParse(Object? raw) {
    for (final PreviewSyntaxIssueKind kind in values) {
      if (kind.wireName == raw) {
        return kind;
      }
    }
    return null;
  }
}

/// 一条问题：种类 + 一句人话 + 落在哪（源码行或 DOM 路径）。
@immutable
class PreviewSyntaxIssue {
  const PreviewSyntaxIssue({
    required this.kind,
    this.detail,
    this.line,
    this.path,
  });

  final PreviewSyntaxIssueKind kind;

  /// 一句话说明**为什么这么判**（例如「围栏 ``` 没闭合，后面的内容都成了代码」）。
  ///
  /// 由判定方给：页面侧判定的带页面自己的数据（列数、围栏字符），调用方直接展示。
  final String? detail;

  /// 1 起源码行；HTML 问题按行扫源码时也有，按 DOM 遍历时没有。
  final int? line;

  /// DOM 路径（HTML）。
  final String? path;

  bool get hasAnchor => line != null || (path != null && path!.isNotEmpty);

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.wireName,
        if (detail != null && detail!.isNotEmpty) 'detail': detail,
        if (line != null) 'line': line,
        if (path != null && path!.isNotEmpty) 'path': path,
      };

  static PreviewSyntaxIssue? parse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final PreviewSyntaxIssueKind? kind =
        PreviewSyntaxIssueKind.tryParse(raw['kind']);
    if (kind == null) {
      return null;
    }
    final Object? lineRaw = raw['line'];
    final Object? path = raw['path'];
    final Object? detail = raw['detail'];
    return PreviewSyntaxIssue(
      kind: kind,
      detail: detail is String && detail.isNotEmpty ? detail : null,
      line: lineRaw is num && lineRaw.toInt() > 0 ? lineRaw.toInt() : null,
      path: path is String && path.isNotEmpty ? path : null,
    );
  }

  /// 值相等：调用方拿它判断「这一份清单与上一份是不是同一份」—— 页面每次重渲都会
  /// 发一份新对象，按身份比会把每次重渲都当成「问题变了」（与 [PreviewOutlineEntry] 同因）。
  @override
  bool operator ==(Object other) =>
      other is PreviewSyntaxIssue &&
      other.kind == kind &&
      other.detail == detail &&
      other.line == line &&
      other.path == path;

  @override
  int get hashCode => Object.hash(kind, detail, line, path);

  @override
  String toString() => 'PreviewSyntaxIssue(${kind.wireName}'
      '${line != null ? ", line: $line" : ""}'
      '${path != null ? ", path: $path" : ""})';
}

/// 一个语法节点。
///
/// `type` 直接沿用 marked 的 token type（`heading` / `paragraph` / `code` /
/// `blockquote` / `list` / `table` / `hr` / `space` / `html`），扩展块
/// （`math` / `mermaid`）落在 `code` 上、靠 [lang] 区分。**不自造类型名** ——
/// 那是与渲染分叉的起点。
@immutable
class PreviewSyntaxNode {
  const PreviewSyntaxNode({
    required this.type,
    this.line,
    this.endLine,
    this.level = 0,
    this.lang,
    this.text = '',
    this.path,
    this.children = const <PreviewSyntaxNode>[],
  });

  /// marked token type（见类注释）。HTML 侧用节点自身语义（`div` / `p` / `h2`…）。
  final String type;

  /// 1 起源码行范围；HTML 恒为 null。
  final int? line;
  final int? endLine;

  /// heading 深度（1~6），其它 0。
  final int level;

  /// 代码围栏的语言。
  final String? lang;

  /// 纯文本摘要（已按 [PreviewSyntaxLimits.maxTextLength] 截断）。
  final String text;

  /// HTML 专用：`body>div#main>p:nth(3)`。
  final String? path;

  final List<PreviewSyntaxNode> children;

  bool get isHeading => level > 0;

  /// 写进回执 / 存档的形态。空值一律省略：1000 个节点里每个都带
  /// `"lang":null` 是白花几百 KB。
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        if (line != null) 'line': line,
        if (endLine != null) 'endLine': endLine,
        if (level > 0) 'level': level,
        if (lang != null && lang!.isNotEmpty) 'lang': lang,
        if (text.isNotEmpty) 'text': text,
        if (path != null && path!.isNotEmpty) 'path': path,
        if (children.isNotEmpty)
          'children':
              children.map((PreviewSyntaxNode n) => n.toJson()).toList(),
      };

  /// 值相等：节点树按内容比（[children] 递归比），页面重渲发来的新对象不会被当成
  /// 「结构变了」。没有这条，调用方只能用「节点数 + 第一个节点」这种近似判据。
  @override
  bool operator ==(Object other) =>
      other is PreviewSyntaxNode &&
      other.type == type &&
      other.line == line &&
      other.endLine == endLine &&
      other.level == level &&
      other.lang == lang &&
      other.text == text &&
      other.path == path &&
      sameValues(other.children, children);

  @override
  int get hashCode => Object.hash(
        type,
        line,
        endLine,
        level,
        lang,
        text,
        path,
        valuesHash(children),
      );

  @override
  String toString() => 'PreviewSyntaxNode($type, line: $line, '
      'level: $level, children: ${children.length})';
}

/// 一篇文档的语法树。
@immutable
class PreviewSyntaxTree {
  const PreviewSyntaxTree({
    required this.kind,
    this.version = currentVersion,
    this.nodes = const <PreviewSyntaxNode>[],
    this.truncated = false,
    this.nodeCount = 0,
    this.issues = const <PreviewSyntaxIssue>[],
  });

  /// 已知的 Markdown 节点类型（marked 核心 + 本包的扩展）。
  ///
  /// 白名单只用来提示「版本不同步」，不参与渲染：多报一条的成本是读者多看一眼，
  /// 漏报的成本是他以为面板坏了。扩展新增类型时必须同时加到这里。
  static const Set<String> knownMarkdownTypes = <String>{
    'heading', 'paragraph', 'code', 'blockquote', 'list', 'list_item',
    'table', 'hr', 'space', 'html', 'text', 'strong', 'em', 'link',
    'image', 'codespan', 'br', 'del', 'def', 'escape',
    // 本包的扩展（见 assets/web/markdown_view.html）
    'hyperLensMathBlock', 'hyperLensMermaid',
  };

  /// 载荷格式版本：解析侧据此判断要不要兼容老页面。
  static const int currentVersion = 1;

  static const PreviewSyntaxTree empty = PreviewSyntaxTree(
    kind: PreviewSourceKind.markdown,
  );

  final PreviewSourceKind kind;
  final int version;
  final List<PreviewSyntaxNode> nodes;

  /// 触到闸门：节点数 / 深度 / 字节数任一超限。
  final bool truncated;

  /// **未截断时**的真实节点数（含 children）；0 表示载荷没带，按实际节点数算。
  final int nodeCount;

  /// 这一篇的问题清单（可空）。节点级问题按 [PreviewSyntaxIssue.line] /
  /// [PreviewSyntaxIssue.path] 与节点对应，对不上的（例如整篇的脚本被摘掉）只在
  /// 面板顶部汇总。
  final List<PreviewSyntaxIssue> issues;

  /// 把「解析侧才发现的问题」并进来（例如 HTML 标签扫描只能看源码文本）。
  ///
  /// 去重按「种类 + 落点」：同一处同一个问题不该出现两次。
  PreviewSyntaxTree mergeIssues(List<PreviewSyntaxIssue> extra) {
    if (extra.isEmpty) {
      return this;
    }
    final Set<String> seen = <String>{
      for (final PreviewSyntaxIssue issue in issues) _issueKey(issue),
    };
    final List<PreviewSyntaxIssue> merged = <PreviewSyntaxIssue>[...issues];
    for (final PreviewSyntaxIssue issue in extra) {
      if (seen.add(_issueKey(issue))) {
        merged.add(issue);
      }
    }
    return PreviewSyntaxTree(
      kind: kind,
      version: version,
      nodes: nodes,
      truncated: truncated,
      nodeCount: nodeCount,
      issues: merged,
    );
  }

  static String _issueKey(PreviewSyntaxIssue issue) =>
      '${issue.kind.wireName}|${issue.line}|${issue.path}';

  bool get isEmpty => nodes.isEmpty;

  /// 树里实际拿到的节点数（含 children）。
  int get count => nodeCount > 0 ? nodeCount : _count(nodes);

  static int _count(List<PreviewSyntaxNode> nodes) {
    int total = 0;
    for (final PreviewSyntaxNode node in nodes) {
      total += 1 + _count(node.children);
    }
    return total;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.wireName,
        'version': version,
        if (nodes.isNotEmpty)
          'nodes': nodes.map((PreviewSyntaxNode n) => n.toJson()).toList(),
        if (truncated) 'truncated': true,
        if (issues.isNotEmpty)
          'issues':
              issues.map((PreviewSyntaxIssue i) => i.toJson()).toList(),
        'nodeCount': count,
      };

  /// 解析一条 `ast <凭据> <json>` 的后半段（或一份存档）。
  ///
  /// 两种载荷都认：**数组**（模板最早发的就是 `JSON.stringify(syntaxNodes)`）与
  /// 带 `kind` / `truncated` 的**对象**（现在发的）。
  ///
  /// [fallbackKind] 在载荷没带 kind 时用 —— HTML 那条通道同样发数组，调用方自己
  /// 知道是哪种文档。认得出来的单条坏节点丢掉那一条（目录少一行不影响阅读，而在
  /// 这条路径上抛异常会让人以为整页坏了，与 `PreviewHtmlOutline.parse` 同口径）。
  static PreviewSyntaxTree parse(
    Object? value, {
    PreviewSourceKind fallbackKind = PreviewSourceKind.markdown,
  }) {
    Object? raw = value;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return PreviewSyntaxTree(kind: fallbackKind);
      }
    }
    final _Budget budget = _Budget();
    if (raw is List) {
      // 裸数组（模板最早发的形态）：没有 kind，按调用方给的算
      budget.checkTypes = fallbackKind == PreviewSourceKind.markdown;
      return PreviewSyntaxTree(
        kind: fallbackKind,
        nodes: _parseNodes(raw, budget, 0),
        truncated: budget.truncated,
        nodeCount: budget.total,
        issues: budget.issues,
      );
    }
    if (raw is Map) {
      final Object? kindRaw = raw['kind'];
      final PreviewSourceKind kind =
          PreviewSourceKind.tryParse(kindRaw) ?? fallbackKind;
      final Object? nodesRaw = raw['nodes'];
      final Object? version = raw['version'];
      final Object? nodeCountRaw = raw['nodeCount'];
      final int reported =
          nodeCountRaw is num ? nodeCountRaw.toInt() : 0;
      final Object? issuesRaw = raw['issues'];
      final List<PreviewSyntaxIssue> declared = issuesRaw is List
          ? issuesRaw
              .map(PreviewSyntaxIssue.parse)
              .whereType<PreviewSyntaxIssue>()
              .toList()
          : const <PreviewSyntaxIssue>[];
      budget.checkTypes = kind == PreviewSourceKind.markdown;
      return PreviewSyntaxTree(
        kind: kind,
        version: version is num ? version.toInt() : currentVersion,
        nodes: nodesRaw is List ? _parseNodes(nodesRaw, budget, 0) : const [],
        truncated: raw['truncated'] == true || budget.truncated,
        // 载荷带了「未截断前的真实节点数」就用它：被闸门砍掉的部分正是调用方
        // 需要知道「这里还差多少」的地方，按实际收到的数算会把它抹平。
        nodeCount: reported > budget.total ? reported : budget.total,
        // 页面自己判定的在前（带它那边的细节），解析侧补的在后
        issues: <PreviewSyntaxIssue>[...declared, ...budget.issues],
      );
    }
    return PreviewSyntaxTree(kind: fallbackKind);
  }

  static List<PreviewSyntaxNode> _parseNodes(
    List<Object?> raw,
    _Budget budget,
    int depth,
  ) {
    final List<PreviewSyntaxNode> out = <PreviewSyntaxNode>[];
    for (final Object? item in raw) {
      if (budget.truncated) {
        break;
      }
      if (item is! Map) {
        continue;
      }
      if (budget.total >= PreviewSyntaxLimits.maxNodes) {
        budget.truncated = true;
        break;
      }
      final PreviewSyntaxNode? node = _parseNode(item, budget, depth);
      if (node != null) {
        out.add(node);
      }
    }
    return out;
  }

  static PreviewSyntaxNode? _parseNode(
    Map<Object?, Object?> raw,
    _Budget budget,
    int depth,
  ) {
    final Object? type = raw['type'];
    if (type is! String || type.isEmpty) {
      return null;
    }
    budget.total += 1;
    final int level = _positiveInt(raw['level']) ?? 0;
    final String? lang = _nonEmpty(raw['lang']);
    final String? path = _nonEmpty(raw['path']);
    final int? line = _positiveInt(raw['line']);
    final int? endLine = _positiveInt(raw['endLine']);
    if (budget.checkTypes && !knownMarkdownTypes.contains(type)) {
      budget.noteUnknownType(type, line);
    }
    final Object? childrenRaw = raw['children'];
    List<PreviewSyntaxNode> children = const <PreviewSyntaxNode>[];
    if (childrenRaw is List && childrenRaw.isNotEmpty) {
      if (depth + 1 >= PreviewSyntaxLimits.maxDepth) {
        // 深度闸门：再往下是列表套列表的极端情况，收益不抵解析代价
        budget.truncated = true;
      } else {
        children = _parseNodes(childrenRaw, budget, depth + 1);
      }
    }
    return PreviewSyntaxNode(
      type: type,
      line: line,
      endLine: endLine,
      level: level > 6 ? 6 : level,
      lang: lang,
      text: _truncate(raw['text']),
      path: path,
      children: children,
    );
  }

  static String _truncate(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return '';
    }
    final String text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= PreviewSyntaxLimits.maxTextLength) {
      return text;
    }
    return '${text.substring(0, PreviewSyntaxLimits.maxTextLength)}…';
  }

  static int? _positiveInt(Object? raw) {
    if (raw is num) {
      final int value = raw.toInt();
      return value > 0 ? value : null;
    }
    return null;
  }

  static String? _nonEmpty(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  /// 值相等：`nodeCount` 不参与 —— 它只是「页面说有多少个」的附带信息，
  /// 同一批节点在不同截断档下报出来的数可以不同，拿它比会让同一棵树判成两份。
  @override
  bool operator ==(Object other) =>
      other is PreviewSyntaxTree &&
      other.kind == kind &&
      other.version == version &&
      other.truncated == truncated &&
      sameValues(other.nodes, nodes) &&
      sameValues(other.issues, issues);

  @override
  int get hashCode => Object.hash(
        kind,
        version,
        truncated,
        valuesHash(nodes),
        valuesHash(issues),
      );

  @override
  String toString() =>
      'PreviewSyntaxTree(${kind.wireName}, $count 个节点'
      '${truncated ? "，已截断" : ""})';
}

/// 解析过程中的计数器：节点总数、「有没有触到闸门」、以及顺手攒下的问题。
class _Budget {
  /// 解析侧最多攒这么多条问题。一个被改坏的载荷（五万个未知类型节点）不该
  /// 让调用方的面板滚三屏 —— 这类补充信息宁少不多。
  static const int maxIssues = 50;

  int total = 0;
  bool truncated = false;

  /// 要不要检查节点类型（只有 Markdown 有白名单；HTML 的 type 就是标签名）。
  bool checkTypes = false;

  final List<PreviewSyntaxIssue> issues = <PreviewSyntaxIssue>[];

  /// 已经报过的未知类型：同一个 `type` 只报一次。按节点各报一条的话，五万个
  /// 节点会生成五万条一模一样的问题，读者一条也读不进去。
  final Set<String> _reportedTypes = <String>{};

  void noteUnknownType(String type, int? line) {
    if (issues.length >= maxIssues || !_reportedTypes.add(type)) {
      return;
    }
    issues.add(PreviewSyntaxIssue(
      kind: PreviewSyntaxIssueKind.unknownNodeType,
      detail: type,
      line: line,
    ));
  }
}
