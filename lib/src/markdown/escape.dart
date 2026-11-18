/// 转义美元符（`\$`）的保护。
///
/// 为什么需要这一层：作者写 `\$x\$` 的意图是「原样显示 $x$」（与 GitHub 一致），
/// 但 marked 在解析阶段就把 `\$` 还原成 `$`，等模板里那段「清洗后的文本节点扫描」
/// 拿到内容时，转义信息已经没了 —— 结果被当成公式渲染（2026-11-17 真机走查发现）。
///
/// 做法：载荷组装时把**正文里**的 `\$` 换成一个私用区字符（[kEscapedDollarSentinel]），
/// 页面渲染完公式后再统一换回 `$`。私用区字符对 marked / DOMPurify 都是普通文本，
/// 不会被当成定界符；代码块与行内代码里**保持原样**（那里 `\$` 本来就该原样显示）。
///
/// 行数必须保持不变：模板按 `token.raw` 的行跨度给「块 ↔ 源码行」建表，多一行少一行
/// 都会让章节跳转 / 命中定位落错块。这里只做同字符数级替换（`\$` 两个字符 → 一个
/// 字符），不增删换行。
library;

/// 转义美元符的占位字符（Unicode 私用区，正常文档里不会出现）。
const String kEscapedDollarSentinel = '\uE000';

/// 围栏代码块的开标记：``` / ~~~，可带缩进与引用前缀。
///
/// 与 `markdown_extras.dart` 里那条必须保持一致 —— 那边用它决定「要不要加载资产」，
/// 这边用它决定「哪里不做转义保护」，两条判据一旦分叉，就会出现「门控说没有公式、
/// 渲染时却把某段代码当公式」这种难查的错位。
final RegExp _fenceOpen = RegExp(r'^[ \t>]*(`{3,}|~{3,})');

/// 把正文里的 `\$` 换成 [kEscapedDollarSentinel]（代码块与行内代码不动）。
String protectEscapedDollars(String markdown) {
  if (!markdown.contains(r'\$')) {
    return markdown;
  }
  final List<String> lines = markdown.split('\n');
  final List<String> out = <String>[];
  String? fenceChar;
  int fenceLen = 0;
  for (final String line in lines) {
    if (fenceChar != null) {
      // 围栏内：原样保留（包括 `\$`）
      if (_isFenceClose(line, fenceChar, fenceLen)) {
        fenceChar = null;
        fenceLen = 0;
      }
      out.add(line);
      continue;
    }
    final RegExpMatch? open = _fenceOpen.firstMatch(line);
    if (open != null) {
      final String marker = open.group(1)!;
      fenceChar = marker[0];
      fenceLen = marker.length;
      out.add(line);
      continue;
    }
    out.add(_protectInLine(line));
  }
  return out.join('\n');
}

bool _isFenceClose(String line, String fenceChar, int fenceLen) {
  final String trimmed = line.trimLeft();
  int run = 0;
  while (run < trimmed.length && trimmed[run] == fenceChar) {
    run++;
  }
  return run >= fenceLen;
}

/// 单行内替换：跳过行内代码（成对的反引号串），并保留 `\\` 这种「反斜杠的转义」。
///
/// `\\$`（两个反斜杠 + 美元）按 CommonMark 语义是「一个反斜杠 + 字面 $」——
/// 那种情况下的 `$` 不是定界符，原样留着，不换成占位字符。
String _protectInLine(String line) {
  final StringBuffer buffer = StringBuffer();
  int i = 0;
  while (i < line.length) {
    final String ch = line[i];
    if (ch == '`') {
      int run = 0;
      while (i + run < line.length && line[i + run] == '`') {
        run++;
      }
      final String fence = '`' * run;
      final int close = line.indexOf(fence, i + run);
      if (close < 0) {
        // 没配对的单个反引号：当普通字符，剩下的原样带走
        buffer.write(line.substring(i));
        break;
      }
      buffer.write(line.substring(i, close + run));
      i = close + run;
      continue;
    }
    if (ch == '\\' && i + 1 < line.length) {
      final String next = line[i + 1];
      if (next == '\$') {
        buffer.write(kEscapedDollarSentinel);
        i += 2;
        continue;
      }
      if (next == '\\') {
        // `\\` 是一个转义对：原样写回，跳过后面的 `$` 不再被当作被转义
        buffer.write('\\\\');
        i += 2;
        continue;
      }
    }
    buffer.write(ch);
    i++;
  }
  return buffer.toString();
}
