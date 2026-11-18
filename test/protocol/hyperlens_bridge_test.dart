import 'dart:io';

import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/protocol/hyperlens_bridge.dart';

import 'package:flutter_test/flutter_test.dart';

/// 通道名与回执前缀是 **Dart ↔ 模板** 的契约：模板是资源文件，编译期看不见，
/// 只能靠这条测试把两边钉在一起。漏改的表现是「回执永远不来 → 看门狗超时 →
/// 提示退出重进」，日志里看不出是拼错了。
///
/// 通道名**不写死**在模板里：模板用的是占位符，实际名字由渲染入口
/// （`HyperlensPage` → `buildMarkdownHtml`）替换进去 —— 使用方可以改成自己的名字。
void main() {
  // 包里只有 Markdown 渲染页；diff 那套模板不在本包（不参与 Markdown 渲染）。
  const String template = 'assets/web/markdown_view.html';

  test('模板的通道名走占位符，不写死具体名字', () {
    final String html = File(template).readAsStringSync();
    expect(
      html,
      contains('window.__HYPERLENS_CHANNEL__'),
      reason: '模板里的通道名必须是占位符，写死会让使用方改不动',
    );
    expect(
      html,
      isNot(contains('window.${HyperlensBridge.channelName}')),
      reason: '模板里不该出现默认名：它只能由渲染时注入',
    );
  });

  test('模板的回执前缀与会话侧一致', () {
    final String html = File(template).readAsStringSync();
    expect(
      html,
      contains("post('${HyperlensBridge.receiptPrefix}'"),
      reason: '模板里的回执前缀与 HyperlensBridge.receiptPrefix'
          '（${HyperlensBridge.receiptPrefix}）不一致',
    );
  });

  test('协议常量不带多余空白（前缀自带一个空格，解析靠它切凭据）', () {
    expect(HyperlensBridge.channelName.trim(), HyperlensBridge.channelName);
    expect(HyperlensBridge.receiptPrefix, endsWith(' '));
    expect(HyperlensBridge.receiptPrefix.trim(), isNotEmpty);
  });

  // 前缀现在集中在 HyperlensBridge 一处：模板与注入脚本里只能有字面量（资源文件
  // import 不了 Dart），所以靠这条测试把「两边各一份」钉住 —— 改了常量不改这里就红。
  test('每条前缀在模板里都有对应字面量', () {
    final String html = File(template).readAsStringSync();
    final Map<String, String> prefixes = <String, String>{
      'render': HyperlensBridge.receiptPrefix,
      'link': HyperlensBridge.linkPrefix,
      'top': HyperlensBridge.positionPrefix,
      'outline': HyperlensBridge.outlinePrefix,
      'ast': HyperlensBridge.astPrefix,
      'focus': HyperlensBridge.focusPrefix,
      'anchor': HyperlensBridge.anchorPrefix,
    };
    prefixes.forEach((String name, String prefix) {
      expect(
        html,
        contains("'$prefix'"),
        reason: '模板里没有 \'$prefix\'：改常量时漏了 $name 那条回执',
      );
    });
  });

  test('HTML 注入脚本里的前缀也逐字一致（且凭据位写 noToken）', () {
    final String js = htmlAnchorScript(null, channelName: 'HyperLens');
    for (final String prefix in <String>[
      HyperlensBridge.positionPrefix,
      HyperlensBridge.outlinePrefix,
      HyperlensBridge.astPrefix,
    ]) {
      expect(
        js,
        contains("'$prefix${HyperlensBridge.noToken} '"),
        reason: 'HTML 的 $prefix 回执没带「无凭据」占位：'
            '解析侧会把它当成有凭据，载荷被切掉一截',
      );
    }
  });

  test('默认通道名是合法 JS 标识符（要拼进 window.<name>）', () {
    expect(
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(HyperlensBridge.channelName),
      isTrue,
      reason: '非法标识符会让页面直接抛语法错误，表现为整页空白',
    );
  });
}
