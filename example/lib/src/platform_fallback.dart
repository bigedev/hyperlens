/// 平台差异只在这一处：官方 `webview_flutter` 覆盖哪些平台，其余平台怎么降级。
///
/// 库本身与平台无关 —— windows / linux 上本示例照常编译运行，只是把 `render()`
/// 产出的载荷以源码形式摆出来。那两平台接自己的 WebView 即可，其余代码不用改。
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// 官方 `webview_flutter` 覆盖的平台；其余平台降级成展示载荷。
///
/// 必须按平台判空：官方包在 windows / linux 上**构造** `WebViewController()`
/// 就会抛错（平台实现没注册），而不是等到用的时候。
bool get hasWebViewPlatform =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };

/// 没有 WebView 的平台：只把「拿到的载荷」摆出来，接口形状与前三个平台一样。
///
/// 只摆开头：文档里有公式或 mermaid 时载荷是 4 MB 上下（Mermaid 一家就 3.5 MB），
/// 整份塞进一个 Text 要一次布局几百万字符 —— 那两平台上会直接卡死。
class PayloadFallbackView extends StatelessWidget {
  const PayloadFallbackView({super.key, required this.payload});

  final String payload;

  static const int _maxPreviewChars = 20000;

  @override
  Widget build(BuildContext context) {
    final String shown = payload.length <= _maxPreviewChars
        ? payload
        : '${payload.substring(0, _maxPreviewChars)}\n'
            '… (${payload.length} chars total)';
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Text(
            'No official WebView implementation on this platform — below is what\n'
            'HyperlensPage.render() produced. Wire your own WebView for the same\n'
            'result as on android / ios / macos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            shown,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
