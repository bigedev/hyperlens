import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/hyperlens.dart';

/// 与包内的分界一致：到这个长度才值得挪到后台（宿主看不到这个数，这里只是造数据）。
const int _offThreadChars = 128 * 1024;

/// 造一条 `ast` 回执：`nodes` 个节点、每段文字 400 字，撑过阈值。
String _astReceipt({required int nodes, String token = 'page-1'}) {
  final String filler = 'x' * 400;
  final List<Map<String, Object?>> list = <Map<String, Object?>>[
    for (int i = 0; i < nodes; i++)
      <String, Object?>{
        'type': 'paragraph',
        'line': i + 1,
        'text': filler,
      },
  ];
  final String json = jsonEncode(<String, Object?>{
    'kind': 'markdown',
    'version': 1,
    'nodeCount': nodes,
    'truncated': false,
    'nodes': list,
  });
  return '${HyperlensBridge.astPrefix}$token $json';
}

void main() {
  test('超过阈值的语法树回执在后台解析，类型照旧', () async {
    final String message = _astReceipt(nodes: 400);
    expect(
      message.length,
      greaterThan(_offThreadChars),
      reason: '这条用例本身要够大，否则走的是同步路径',
    );

    final Completer<PreviewEvent> applied = Completer<PreviewEvent>();
    final PreviewReceiptDispatcher dispatcher = PreviewReceiptDispatcher(
      apply: applied.complete,
    );
    dispatcher.dispatch(message);

    expect(applied.isCompleted, isFalse, reason: '大回执不该在 dispatch 里同步做完');

    final PreviewEvent event = await applied.future.timeout(
      const Duration(seconds: 10),
    );
    expect(event, isA<PreviewSyntaxReported>());
    expect((event as PreviewSyntaxReported).tree.count, 400);
    expect(event.tree.kind, PreviewSourceKind.markdown);
  });

  test('骨架后到不会盖掉完整树（顺序守卫）', () async {
    // 骨架：节点少但每条都撑得很大 → 走后台；完整树：节点小而多 → 同步先落地。
    // 后台那份回来时已经过时，必须丢掉，否则面板会从「完整树」退回「骨架」。
    final String skeleton = _astReceipt(nodes: 400, token: 'page-1');
    final String full = _astReceipt(nodes: 3, token: 'page-1');

    final List<PreviewEvent> applied = <PreviewEvent>[];
    final List<String> logs = <String>[];
    final Completer<void> done = Completer<void>();
    final PreviewReceiptDispatcher dispatcher = PreviewReceiptDispatcher(
      apply: (PreviewEvent event) {
        applied.add(event);
        if (event is PreviewSyntaxReported &&
            event.tree.count == 3 &&
            !done.isCompleted) {
          // 同步那份已经落地；再等后台那份跑完
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (!done.isCompleted) {
              done.complete();
            }
          });
        }
      },
      onLog: logs.add,
    );

    dispatcher.dispatch(skeleton);
    dispatcher.dispatch(full);
    await done.future;

    expect(applied.length, 1, reason: '过时的骨架不该落地');
    expect((applied.single as PreviewSyntaxReported).tree.count, 3);
    expect(
      logs.any((String line) => line.contains('已过时')),
      isTrue,
      reason: '丢弃要走诊断日志，不能一声不响',
    );
  });

  test('小回执仍同步落地（不因后台解析而变成异步）', () {
    final List<PreviewEvent> applied = <PreviewEvent>[];
    final PreviewReceiptDispatcher dispatcher = PreviewReceiptDispatcher(
      apply: applied.add,
    );
    const String position = '${HyperlensBridge.positionPrefix}page-1 {"line":12}';
    expect(
      position.length,
      lessThan(_offThreadChars),
      reason: '位置回执只有几十字节',
    );
    dispatcher.dispatch(position);
    expect(applied, hasLength(1));
    expect(applied.single, isA<PreviewPositionReported>());
  });
}
