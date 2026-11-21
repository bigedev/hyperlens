import 'dart:isolate';

import 'events.dart';

/// 有 isolate 的平台（VM / 移动端）：把一条回执挪到后台解析。
///
/// `Isolate.run` 用 `Isolate.exit` 把结果**零拷贝**交回来，所以
/// [PreviewEvent] 这类纯数据对象可以直接跨隔离区（闭包、原生句柄不行）。
Future<PreviewEvent> parseReceiptOffThread(String raw) =>
    Isolate.run(() => PreviewEvent.parse(raw));
