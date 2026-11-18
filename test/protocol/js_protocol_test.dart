import 'dart:io';

import 'package:hyperlens/src/protocol/js_protocol.dart';

import 'package:flutter_test/flutter_test.dart';

/// 通道名与回执前缀是 **Dart ↔ 模板** 的契约：模板是资源文件，编译期看不见，
/// 只能靠这条测试把两边钉在一起。漏改的表现是「回执永远不来 → 看门狗超时 →
/// 提示退出重进」，日志里看不出是拼错了。
void main() {
  // 包里只有 Markdown 渲染页；diff 那套模板不在本包（不参与 Markdown 渲染）。
  const List<String> templates = <String>[
    'assets/web/markdown_view.html',
  ];

  for (final String path in templates) {
    test('$path 与会话侧使用同一套协议', () {
      final String html = File(path).readAsStringSync();
      expect(
        html,
        contains('window.${JsProtocol.channel}'),
        reason: '模板里的 JS 通道名与 JsProtocol.channel（${JsProtocol.channel}）不一致',
      );
      expect(
        html,
        contains("post('${JsProtocol.receiptPrefix}'"),
        reason:
            '模板里的回执前缀与 JsProtocol.receiptPrefix（${JsProtocol.receiptPrefix}）不一致',
      );
    });
  }

  test('协议常量不带多余空白（前缀自带一个空格，解析靠它切凭据）', () {
    expect(JsProtocol.channel.trim(), JsProtocol.channel);
    expect(JsProtocol.receiptPrefix, endsWith(' '));
    expect(JsProtocol.receiptPrefix.trim(), isNotEmpty);
  });
}
