// 公开命名自检：`dart run tool/check_public_names.dart`
//
// 为什么需要：Dart 没有跨包符号冲突检测 —— 两个包导出同名类时，冲突在使用方的
// import 处才爆，而且只有用到的那个名字才报错。所以「少用裸名」是唯一防线，只能靠
// 这里守住：公开类型必须从前缀表里选，主入口不许导出底层工具目录。
//
// 失败时退出码非 0，可直接接进 CI。

import 'dart:io';

/// 公开类型允许的前缀。
const List<String> _allowedPrefixes = <String>[
  'Hyperlens', // 门面与服务：Page / Theme / Assets / Logger / Commands / Bridge
  'Preview', // 概念与事件：Position / Focus / Outline / Syntax / Event…
  'Markdown', // Markdown 专用工具：MarkdownExtras / MarkdownLinkAction
  'NoopHyperlens', // NoopHyperlensLogger
];

/// 例外：语义足够独特、加前缀反而更长。
const Set<String> _exceptions = <String>{
  'OpenRepoFile',
  'OpenExternal',
  'IgnoreLink',
};

/// 主入口（`lib/hyperlens.dart`）不许导出的目录：那里的符号属于
/// `package:hyperlens/advanced.dart`（自己拼页面 / 诊断才用）。
const List<String> _advancedOnlyPaths = <String>[
  "export 'src/html/",
  "export 'src/markdown/",
];

final RegExp _typeDecl = RegExp(
  r'^(?:abstract |sealed |final |base |interface )*'
  r'(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)',
  multiLine: true,
);

void main() {
  final List<String> problems = <String>[];

  final List<File> sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  for (final File file in sources) {
    final String text = file.readAsStringSync();
    for (final RegExpMatch match in _typeDecl.allMatches(text)) {
      final String name = match.group(1)!;
      if (name.startsWith('_') || _exceptions.contains(name)) {
        continue;
      }
      if (!_allowedPrefixes.any(name.startsWith)) {
        problems.add('${file.path}: 公开类型 `$name` 没有包前缀'
            '（允许：${_allowedPrefixes.join(' / ')}，或加到 _exceptions）');
      }
    }
  }

  final File mainEntry = File('lib/hyperlens.dart');
  final String mainText = mainEntry.readAsStringSync();
  for (final String path in _advancedOnlyPaths) {
    if (mainText.contains(path)) {
      problems.add('lib/hyperlens.dart: 主入口不应导出 `${path.substring(8)}…`'
          '（应放在 lib/advanced.dart）');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('公开命名自检通过（${sources.length} 个文件）。');
    return;
  }
  stderr.writeln('公开命名自检失败：');
  for (final String problem in problems) {
    stderr.writeln('  - $problem');
  }
  exitCode = 1;
}
