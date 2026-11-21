import 'dart:async';

import 'events.dart';
import 'receipt_parse_sync.dart'
    if (dart.library.io) 'receipt_parse_isolate.dart' as backing;

/// 一条回执长到多少字符就值得挪到后台解析。
///
/// 语法树是协议里唯一能长到 2MB 的回执（页面侧的 `kSyntaxMaxBytes`），
/// 一次解码几百毫秒 —— 压在主 isolate 上就是「点开语法页，界面停一拍」。
/// 其余回执只有几十到几千字节，同步解析更快，也不必打乱顺序。
///
/// 阈值不对外：同步还是后台由 [PreviewReceiptDispatcher] 自己判，宿主不必知道。
const int _offThreadChars = 128 * 1024;

/// 这条回执值不值得挪到后台解析。
bool _needsOffThreadParse(String raw) => raw.length >= _offThreadChars;

/// 把一条回执挪到后台解析（没有 isolate 的平台退化为同步）。
Future<PreviewEvent> _parseOffThread(String raw) =>
    backing.parseReceiptOffThread(raw);

/// 回执入口：宿主把通道消息原样交进来，剩下的（同步/后台、先后）由这里管。
///
/// 用法（宿主只需这一处）：
///
/// ```dart
/// final dispatcher = PreviewReceiptDispatcher(apply: _onEvent, onLog: logI);
/// void _onMessage(String raw) => dispatcher.dispatch(raw);
/// ```
///
/// 小回执同步解析，大回执走后台 isolate，且**先后不说谎**。
///
/// 顺序守卫只针对语法树 —— 它是唯一会「同一份文档连发两回」的回执
/// （渲染时发骨架，切到语法页时再拉完整树）。后台解析慢，若骨架后到就会把
/// 完整树盖回骨架：面板只剩几行，读者会以为解析失败。两条判据任一成立就丢掉
/// 这份过时的：
/// - 解析期间已有别的语法树落地（[_appliedSyntax] 变了）；
/// - 后发起的那次已经先返回（[_seq] 变了）。
///
/// HTML 侧一次带全、通常没有骨架/完整树两回，走同一个入口也不会被误丢
/// （只有真的并发发出两份语法树时才会触发守卫，那时丢旧的那份正是对的）。
final class PreviewReceiptDispatcher {
  PreviewReceiptDispatcher({required this.apply, this.onLog});

  /// 落地一条回执。大回执回来时页面可能已经关了 —— 这里再判一次生命周期是调用方
  /// 的责任（`apply` 里判 `mounted`）。
  final void Function(PreviewEvent event) apply;

  /// 诊断用：大回执的后台解析耗时、被丢弃的过时回执。不接就静默。
  final void Function(String message)? onLog;

  /// 发起过的后台解析次数。
  int _seq = 0;

  /// 已落地的语法树份数。
  int _appliedSyntax = 0;

  void dispatch(String raw) {
    if (!_needsOffThreadParse(raw)) {
      final PreviewEvent event = PreviewEvent.parse(raw);
      if (event is PreviewSyntaxReported) {
        _appliedSyntax++;
      }
      apply(event);
      return;
    }
    unawaited(_dispatchOffThread(raw));
  }

  Future<void> _dispatchOffThread(String raw) async {
    final int seq = ++_seq;
    final int syntaxAtStart = _appliedSyntax;
    final Stopwatch watch = Stopwatch()..start();
    final PreviewEvent event = await _parseOffThread(raw);
    if (event is PreviewSyntaxReported) {
      if (seq != _seq || syntaxAtStart != _appliedSyntax) {
        onLog?.call('大回执 ${raw.length}B 解析完已过时，丢弃');
        return;
      }
      _appliedSyntax++;
    }
    onLog?.call('大回执 ${raw.length}B 后台解析 ${watch.elapsedMilliseconds}ms');
    apply(event);
  }
}
