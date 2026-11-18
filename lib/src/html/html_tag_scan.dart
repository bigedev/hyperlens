/// 扫一遍 HTML **源码文本**的标签栈，找出「一定是写错」的地方。
///
/// 为什么不用页面的 `document`：浏览器会把所有错误悄悄修好（自动补 `</p>`、纠正
/// 错位嵌套），修完的树里没有任何「作者写错了」的痕迹。要判定就得看原文。
///
/// **只报硬错**，两种：
/// 1. 结束标签没有对应的开始标签（`</div>` 多出来）；
/// 2. 非空元素没闭合，且它不属于「允许省略结束标签」的那批（HTML 规范允许 `<li>`、
///    `<tr>`、`<td>`、`<p>` 等省略结尾 —— 那些不报，否则每份正常 HTML 都会满屏红）。
///
/// 行号是源码行（1 起），与阅读位置同一套坐标；点问题能落到那一行。
library;

import '../model/preview_syntax.dart';

/// 扫出标签问题（最多 [maxIssues] 条，按源码顺序）。
///
/// 启发式，不是完整解析器：`<template>`、CDATA、SVG 命名空间里的少数写法可能被
/// 误判，所以每条都只说「哪个标签在哪一行」，不猜作者的意图。
List<PreviewSyntaxIssue> scanHtmlTagIssues(
  String html, {
  int maxIssues = 20,
}) {
  if (html.isEmpty) {
    return const <PreviewSyntaxIssue>[];
  }
  final List<PreviewSyntaxIssue> issues = <PreviewSyntaxIssue>[];
  final List<_OpenTag> stack = <_OpenTag>[];
  // 属性值里可能有 `>`（`title="a > b"`），所以属性段要吞掉成对的引号
  final RegExp tagPattern = RegExp(
    '<!--[\\s\\S]*?-->|<!\\[CDATA\\[[\\s\\S]*?\\]\\]>'
    '|<(/?)([a-zA-Z][\\w:.-]*)((?:[^>"\']|"[^"]*"|\'[^\']*\')*)>',
  );
  int line = 1;
  int consumed = 0;
  // 找结束标签要不带大小写地搜，但整篇 toLowerCase 只在真遇到原始文本标签时
  // 做一次 —— 别给每篇文档都白拷一份。
  String? lowerHtml;

  bool full() => issues.length >= maxIssues;

  String lowerSource() => lowerHtml ??= html.toLowerCase();

  void report(PreviewSyntaxIssueKind kind, String detail, int atLine) {
    if (full()) {
      return;
    }
    issues.add(PreviewSyntaxIssue(kind: kind, detail: detail, line: atLine));
  }

  /// 从 [from] 到 [to] 之间的换行数，用于把下标换算成源码行。
  void advanceTo(int to) {
    for (int i = consumed; i < to && i < html.length; i++) {
      if (html.codeUnitAt(i) == 0x0A) {
        line += 1;
      }
    }
    consumed = to;
  }

  for (final RegExpMatch match in tagPattern.allMatches(html)) {
    if (full()) {
      break;
    }
    // 跳过的区间（原始文本内容）里也可能有像标签的东西：正则照样会给出它们，
    // 但那里已经是脚本的正文，不参与结构。
    if (match.start < consumed) {
      continue;
    }
    advanceTo(match.start);
    final String raw = match.group(0)!;
    if (raw.startsWith('<!--') || raw.startsWith('<![CDATA[')) {
      continue; // 注释 / CDATA 里的标签不算结构
    }
    final bool closing = match.group(1) == '/';
    final String name = match.group(2)!.toLowerCase();
    final bool selfClosing = raw.trimRight().endsWith('/>');
    final int tagLine = line;

    if (!closing) {
      if (_kRawText.contains(name)) {
        // script / style / textarea / title 的内容里可以出现 `<`，跳到它真正的结束标签
        final int closeAt = lowerSource().indexOf('</$name', match.end);
        if (closeAt < 0) {
          report(
            PreviewSyntaxIssueKind.unclosedTag,
            '<$name> 没有闭合',
            tagLine,
          );
          break;
        }
        // 连同结束标签一起跳过：它本来就是配对的，再让正则看一眼只会误报
        // 「</script> 没有对应的开始标签」。
        final int gtAt = html.indexOf('>', closeAt);
        advanceTo(gtAt < 0 ? html.length : gtAt + 1);
        continue;
      }
      if (selfClosing || _kVoid.contains(name)) {
        continue;
      }
      stack.add(_OpenTag(name, tagLine));
      continue;
    }

    // 结束标签：从栈顶往下找同名
    int index = -1;
    for (int i = stack.length - 1; i >= 0; i--) {
      if (stack[i].name == name) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      report(
        PreviewSyntaxIssueKind.unclosedTag,
        '</$name> 没有对应的开始标签',
        tagLine,
      );
      continue;
    }
    // 同名之上还有没关的标签：那是嵌套写错（或者上面那些本来就该省略结尾）
    for (int i = stack.length - 1; i > index; i--) {
      final _OpenTag open = stack[i];
      if (_kOptionalClose.contains(open.name)) {
        continue;
      }
      report(
        PreviewSyntaxIssueKind.unclosedTag,
        '<${open.name}> 没有闭合（第 ${open.line} 行开始，直到第 $tagLine 行遇到 </$name>）',
        open.line,
      );
    }
    stack.removeRange(index, stack.length);
  }

  for (final _OpenTag open in stack) {
    if (full()) {
      break;
    }
    if (_kOptionalClose.contains(open.name)) {
      continue;
    }
    report(
      PreviewSyntaxIssueKind.unclosedTag,
      '<${open.name}> 没有闭合（第 ${open.line} 行开始，到文件结尾都没关）',
      open.line,
    );
  }

  return issues;
}

class _OpenTag {
  const _OpenTag(this.name, this.line);

  final String name;
  final int line;
}

/// 自闭合元素：不压栈。
const Set<String> _kVoid = <String>{
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'param', 'source', 'track', 'wbr',
};

/// 规范允许省略结束标签的元素：它们的「未闭合」不算错，报出来全是噪音。
const Set<String> _kOptionalClose = <String>{
  'p', 'li', 'dt', 'dd', 'tr', 'td', 'th', 'thead', 'tbody', 'tfoot',
  'option', 'optgroup', 'rt', 'rp', 'colgroup', 'caption',
};

/// 内容里可能出现 `<` 的元素：必须按「原始文本」跳到真正的结束标签。
const Set<String> _kRawText = <String>{'script', 'style', 'textarea', 'title'};
