import 'events.dart';

/// 没有 isolate 的平台（web）：退回同步解析。
///
/// 语义与 isolate 版一致 —— 调用方只管 `await`，不必知道底下有没有真线程。
/// 主入口 `lib/` 不 import flutter，web 端也能只靠协议驱动自己的预览，
/// 所以这里不能直接 `import 'dart:isolate'`（web 上编不过）。
Future<PreviewEvent> parseReceiptOffThread(String raw) async =>
    PreviewEvent.parse(raw);
