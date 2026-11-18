/// 预览 ↔ 源码切换时的坐标交接（用**源码行号**当公共坐标）。
///
/// **为什么需要**：两条通道本来各记各的：预览记源码行（[PreviewSourceAddress]），
/// 源码记像素偏移（[PreviewCodeAnchor]），互相听不懂 —— 于是读者在预览
/// 里读到某段、切到源码，落回的是「上次源码停的地方」，没读过就是顶部。
///
/// 交接写成一个纯换算、由调用方在切视图时调用：算出来的锚点照常走各自的上报通道
/// （预览的 `onAnchor` / 源码的 `onCodeAnchor`），于是切过去、返回、下次再进来，
/// 落在的还是这一段。
///
/// **两个方法都返回可空**：null 表示「这次别动」，宁可保持各自的老位置，也不要猜一个
/// 把它带偏。
library;

import 'package:path/path.dart' as p;

import 'code_anchor.dart';
import 'preview_position.dart';

/// 有 Markdown 渲染通道的扩展名。
///
/// 哪个后缀走哪条预览通道由调用方决定（HTML 那条记的是 DOM 路径），这里只用来回答
/// 「行号这个坐标这次认不认」：`.md` / `.markdown`。
const Set<String> _markdownExtensions = <String>{'.md', '.markdown'};

/// 源码 → 预览 / 预览 → 源码 的位置换算。
abstract final class PreviewAnchorHandoff {
  /// 源码停在第 [codeLine] 行时，切到预览该落哪。
  ///
  /// **只有 Markdown 预览认这个坐标**：HTML 预览的地址是 DOM 路径
  /// （见 `html_anchor.dart`），拿一行号去换会把读者扔回页首 —— 返回 null 别动它。
  ///
  /// [codeLine] < 1 表示源码那边还没报过行号（刚打开、标尺还没就绪）：不猜。
  static PreviewSourceAddress? toPreview({
    required String entryPath,
    required int codeLine,
  }) {
    if (!_isMarkdown(entryPath) || codeLine < 1) {
      return null;
    }
    // 只带行号：预览侧按行换算像素（见 `PreviewSourceAddress` 的说明）
    return PreviewSourceAddress(codeLine);
  }

  /// 预览停在第 [previewLine] 行时，切到源码该落哪。
  ///
  /// [previewLine] < 1 表示预览侧没算出来（文档比一屏还短、或页面结构陌生）：不猜。
  static PreviewCodeAnchor? toCode({required int previewLine}) {
    if (previewLine < 1) {
      return null;
    }
    // 只带行号：源码侧按行估偏移，再由顶对齐的闭环纠一次
    return PreviewCodeAnchor(line: previewLine, offset: 0, fontSize: 0);
  }

  static bool _isMarkdown(String path) =>
      _markdownExtensions.contains(p.extension(path).toLowerCase());
}
