import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/asset/hyperlens_assets.dart';

/// `assets/web/` 的路径只允许写在 [HyperlensAssets] 里，而且必须真的存在。
///
/// 这两件事**都不会编译失败**：写错路径是运行时 `Asset not found`（那一侧渲染白屏），
/// 而改资源文件名后忘了同步调用方，同样只在真机上才看见。前者靠「文件存在」断言，
/// 后者靠「lib 里不许再有裸路径」断言。
void main() {
  const List<String> paths = <String>[
    HyperlensAssets.markdownViewHtml,
    HyperlensAssets.mdLightCss,
    HyperlensAssets.mdDarkCss,
    HyperlensAssets.mdInkCss,
    HyperlensAssets.mdInkDarkCss,
    HyperlensAssets.hljsLightCss,
    HyperlensAssets.hljsDarkCss,
    HyperlensAssets.hljsInkCss,
    HyperlensAssets.hljsInkDarkCss,
    HyperlensAssets.markedJs,
    HyperlensAssets.purifyJs,
    HyperlensAssets.highlightJs,
    HyperlensAssets.highlightDartJs,
    HyperlensAssets.katexJs,
    HyperlensAssets.mhchemJs,
    HyperlensAssets.katexCss,
    HyperlensAssets.mermaidJs,
  ];

  test('清单与常量表同步（新增资源时把上面这份列全）', () {
    expect(paths.length, 17, reason: '常量表增减了就要同步这里，否则下面两条是残的');
  });

  test('表里的资源都真的存在', () {
    // 常量是**资产键**（`packages/hyperlens/assets/web/…`），磁盘上则相对包根：
    // 断言前先摘掉 `packages/hyperlens/` 这一段。
    final List<String> missing = <String>[
      for (final String path in paths)
        if (!File(path.replaceFirst('packages/hyperlens/', '')).existsSync()) path,
    ];
    expect(missing, isEmpty, reason: '缺文件：\n${missing.join('\n')}');
  });

  test('lib 里不再有裸的 assets/web/ 路径', () {
    // 只认「整条字面量就是一个路径」：`'assets/web/xxx'`。
    // 所以 licenses_data 里「内置 assets/web/highlight.min.js，sha256 …」这类说明文本
    // 不会被算进来；注释同理。
    // 常量表所在文件本身就是唯一允许出现路径的地方，跳过它。
    final RegExp literal = RegExp(r"'assets/web/[A-Za-z0-9_.-]+'");
    final List<String> hits = <String>[];

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path.endsWith('asset/hyperlens_assets.dart')) {
        continue;
      }
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) {
          hits.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(hits, isEmpty, reason: '改用 HyperlensAssets.*：\n${hits.join('\n')}');
  });
}
