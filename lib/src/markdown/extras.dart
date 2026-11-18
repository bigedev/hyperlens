/// Markdown 预览的**渲染增强**门控：这篇文档要不要额外背 KaTeX（0.66 MB）与
/// Mermaid（3.57 MB）的内联资产。
///
/// 为什么要有这一层：预览页是「模板 + 全部资产一次性拼成一个 HTML 再
/// `loadHtmlString`」的形态（见 `markdown_payload.dart`），内联体积直接等于每次
/// 渲染的拼装量与页面解析量。现在整包内联资产约 250 KB；无门控地塞进 4 MB，等于
/// 让每篇 README（含每次切字号、切主题）都付一遍。
///
/// 判据**只看源码文本**，宁可多判也不能漏判：漏判的表现是「公式 / 图表原样露出来」，
/// 读者会当成渲染坏了；多判只是多加载一份没被用到的脚本。
library;

/// 一篇文档需要的渲染增强。
class MarkdownExtras {
  const MarkdownExtras({required this.math, required this.mermaid});

  /// 需要 KaTeX（含 mhchem 化学式）。
  final bool math;

  /// 需要 Mermaid 图表。
  final bool mermaid;

  /// 一个都不需要 —— 模板里所有增强占位都按空串替换，行为与没有这些功能时逐字节一致。
  static const MarkdownExtras none =
      MarkdownExtras(math: false, mermaid: false);

  bool get any => math || mermaid;

  @override
  String toString() {
    if (!any) {
      return 'extras=none';
    }
    return 'extras=${<String>[
      if (math) 'math',
      if (mermaid) 'mermaid',
    ].join('+')}';
  }
}

/// 行内代码：`` `$x$` `` 不该把整篇判成有公式。
///
/// 只处理单层（`` ` ` `` 与 ``` `` ```）—— 多层反引号里写公式是极少数，
/// 真的漏判了也只是多加载一份资产。
final RegExp _inlineCode = RegExp(r'`+[^`]*`+');

/// 围栏代码块：``` / ~~~，可带缩进与引用前缀。
final RegExp _fenceOpen = RegExp(r'^[ \t>]*(`{3,}|~{3,})');

/// `mermaid` 围栏：```mermaid / ~~~mermaid。**必须在剥围栏之前判**（剥完就没了）。
final RegExp _mermaidFence = RegExp(
  r'^[ \t>]*(?:`{3,}|~{3,})[ \t]*mermaid\b',
  multiLine: true,
);

/// 块级公式的定界符：`$$`（成对与否都算，交给渲染器兜错）、`\[`、`\(`。
final RegExp _mathBlockDelim = RegExp(r'\$\$|\\\[|\\\(');

/// 行内公式 `$…$`：不跨行、内部非空、首尾不贴空白、`$` 不能被反斜杠转义、
/// 且不能是 `$$` 的一部分。
///
/// 两条容易漏的边界：
/// - 「首尾不贴空白」与模板里的渲染判据一致：中文里写「$5 到 $10」不该被当成公式，
///   而 `$a + b$` 这种中间有空格的正常写法仍然成立；
/// - 紧贴反引号的不算公式（`` `$x$` `` 是行内代码）：剥行内代码那一步按 `` `+ `` 配对，
///   遇到多层反引号会剩下碎块，所以判据本身再挡一道。
final RegExp _mathDollar =
    RegExp(r'(?<!\\)(?<!`)\$(?!\$)(?!`)(?!\s)[^\n$]*?(?<!\s)(?<!\\)\$(?!`)');

/// 判定这篇 Markdown 需要哪些渲染增强。
///
/// 「忽略代码里的命中」用两步做：先整块剥掉围栏代码，再剥掉行内代码。围栏内的
/// 内容不会被 token 化，剥掉只是为了避免「代码块里写着 `$x$`」把整篇判成有公式 ——
/// 那会让无公式的大文档也变慢。
MarkdownExtras detectMarkdownExtras(String markdown) {
  if (markdown.isEmpty) {
    return MarkdownExtras.none;
  }
  // mermaid 的围栏要在剥之前认，剥完只剩空行
  final bool mermaid = _mermaidFence.hasMatch(markdown);

  final String body = _stripInlineCode(_stripFencedCode(markdown));
  final bool math =
      _mathBlockDelim.hasMatch(body) || _mathDollar.hasMatch(body);

  if (!math && !mermaid) {
    return MarkdownExtras.none;
  }
  return MarkdownExtras(math: math, mermaid: mermaid);
}

/// 把围栏代码块整段换成空行（保留行数，便于将来需要行号时不出错）。
String _stripFencedCode(String src) {
  final List<String> lines = src.split('\n');
  final List<String> out = <String>[];
  String? fenceChar;
  int fenceLen = 0;
  for (final String line in lines) {
    final String trimmed = line.trimLeft();
    if (fenceChar == null) {
      final RegExpMatch? open = _fenceOpen.firstMatch(line);
      if (open != null) {
        final String marker = open.group(1)!;
        fenceChar = marker[0];
        fenceLen = marker.length;
        out.add('');
        continue;
      }
      out.add(line);
      continue;
    }
    // 收尾围栏：同一种字符、长度不小于开启那条
    final RegExp close = RegExp('^${RegExp.escape(fenceChar)}{$fenceLen,}');
    if (close.hasMatch(trimmed)) {
      fenceChar = null;
      fenceLen = 0;
    }
    out.add('');
  }
  return out.join('\n');
}

String _stripInlineCode(String src) => src.replaceAll(_inlineCode, '``');
