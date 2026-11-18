/// 把 Dart 值变成**可以内联进 `<script>`** 的 JS 字面量。
///
/// 三处拼装（Markdown 载荷、focus 脚本、HTML 注入脚本）以前各写一遍「`<` →
/// `\u003c`」，每发现一个禁区就要补三处 —— 那些禁区又是「表现成点了没反应」的
/// 一类（整段脚本 `SyntaxError`，日志干净）。收敛成一个出口，补一次就全补上。
library;

import 'dart:convert';

/// `jsonEncode` 的结果 + 三个内联禁区。
///
/// - `<`：内联进 `<script>` 时可能被解析成标签，`</script>` 会当场截断整段脚本；
/// - U+2028 / U+2029：JSON 允许，**JS 字符串字面量不允许**（ES2019 之前被当成
///   换行符），老 WebView 上同样表现为整段脚本语法错。
///
/// `\n` / `\r` 由 `jsonEncode` 自己转义，这里不用管。
String jsJson(Object? value) => jsonEncode(value)
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029')
    .replaceAll('<', r'\u003c');

/// 单引号 JS 字符串字面量（命令参数用：`mdScrollToLine('…')`）。
///
/// 与 [jsJson] 同一批禁区，另外要转 `'` 与 `\`。`\n` / `\r` 必须显式转义：地址可能
/// 来自跨会话持久化（`PreviewDomAddress` 不限格式），一条换行就足以让整条命令报废。
String jsSingleQuoted(String value) => "'${value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029')
    .replaceAll('<', r'\u003c')}'";
