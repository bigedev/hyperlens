/// 链接点击的**协议本体**：清单一处 —— 判据（哪些链接不拦）、信封（回执长什么样）、
/// 外链表（哪些协议算「离开文档」）。
///
/// 为什么收进包里：这三样原本是「包内 Markdown 模板一份、调用方注入脚本一份」，
/// 改一处漏一处**不报错**，只表现为「某类链接点了没反应」；外链表漏一个 `tel:`，
/// 表现只是「点电话号码没反应」。现在页面脚本由 [htmlAnchorScript] 生成、回执由
/// [PreviewEvent.parse] 解析，调用方只剩两件事：注入、接事件。
///
/// 回执信封（与 `HyperlensBridge.linkPrefix` 对齐）：
///
/// ```text
/// link <space> <encodeURIComponent(context)> <encodeURIComponent(href)>
/// link <encodeURIComponent(href)>            // 旧式：页面不知道自己在哪个地址空间
/// ```
///
/// [context] 是「同一个 href 在哪个地址空间里成立」的补充：`repo` 是仓库相对路径，
/// `book` 是章号。**切文件 / 翻章之后上一页的迟到回执靠它丢弃** —— 没有它，连点时
/// 上一页的那一下会算到新页头上。
library;

import 'hyperlens_bridge.dart';

/// 这条链接是在哪个地址空间里被点的。
///
/// 名字带 `Preview` 前缀：使用方 import 之后自己也有 `LinkSpace` 这类枚举的代价，
/// 比多打几个字高得多（同 [HyperlensBridge] 的口径）。
enum PreviewLinkSpace {
  /// 仓库里的文件（Markdown 文档、仓内 `.html`）：`context` 是仓库相对路径。
  repo('repo'),

  /// 电子书的一章：`context` 是章号（`0` 起，与页面侧的章序一致）。
  book('book');

  const PreviewLinkSpace(this.wireName);

  /// 回执里的写法。
  final String wireName;

  /// 从回执还原；认不出来返回 null（当作旧式回执，而不是「没有链接」）。
  static PreviewLinkSpace? fromWire(String name) {
    for (final PreviewLinkSpace space in PreviewLinkSpace.values) {
      if (space.wireName == name) {
        return space;
      }
    }
    return null;
  }
}

/// 可以交给系统打开的协议。
///
/// 判据只看协议头，不看域名：`mailto:` / `tel:` 与 http(s) 同属「离开文档」。
/// **这是一张「少一个就静默失效」的表**：`tel:` 漏了，表现只是「点电话号码没反应」。
const Set<String> kPreviewExternalSchemes = <String>{
  'http',
  'https',
  'mailto',
  'tel',
};

/// 这条 href 该交给系统浏览器吗（[kPreviewExternalSchemes] 里的协议）。
bool isExternalPreviewLink(String href) {
  final String trimmed = href.trim();
  final int colon = trimmed.indexOf(':');
  if (colon <= 0) {
    return false;
  }
  return kPreviewExternalSchemes.contains(trimmed.substring(0, colon).toLowerCase());
}

/// 链接回执的前缀部分：`link ` 或 `link <space> <encoded context> `。
///
/// 页面脚本把它当字符串常量拼在编码后的 href 前面（见 [htmlAnchorScript]）；
/// Dart 侧拼整条回执用 [linkReceipt]。
String linkReceiptPrefix({
  PreviewLinkSpace? space,
  String? context,
}) {
  if (space == null) {
    return HyperlensBridge.linkPrefix;
  }
  final String ctx = Uri.encodeComponent(context ?? '');
  return '${HyperlensBridge.linkPrefix}${space.wireName} $ctx ';
}

/// 拼一条完整回执（`link <space> <ctx> <encoded href>`）。
///
/// 与页面里 `post(前缀 + encodeURIComponent(href))` 逐字等价 —— 单测拿它当基准。
String linkReceipt({
  required PreviewLinkSpace space,
  required String context,
  required String href,
}) {
  return '${linkReceiptPrefix(space: space, context: context)}'
      '${Uri.encodeComponent(href)}';
}

/// 解析 `link <载荷>` 里的载荷（不含前缀）。
///
/// 两种形态都认：
/// - `link repo my%2Fdoc.html a%2Fb.html%23sec2` → 带地址空间与上下文；
/// - `link a%2Fb.html`（旧式 / 页面不知道自己属于谁）→ `space` 与 `context` 为 null。
///
/// 认不出（空 href、段数不对、space 名不合法）返回 null —— 调用方归到
/// `PreviewUnknownMessage`，别把「认不出的消息」当成「点了空链接」。
({PreviewLinkSpace? space, String? context, String href})? parseLinkReceipt(
  String payload,
) {
  final List<String> parts = payload.split(' ');
  if (parts.length > 1) {
    // 编码后的 href 里没有空格（`Uri.encodeComponent` 把空格写成 %20），所以拆出
    // 两段以上就一定是带地址空间的信封：段数不对、或 space 认不出（页面与包不同步）
    // 都返回 null。**不能退回「整段当 href」** —— 那会把一句 `repo2 x%20y` 当成
    // 链接交出去，调用方拿着它去打开文件，报错离现场十万八千里。
    if (parts.length != 3) {
      return null;
    }
    final PreviewLinkSpace? space = PreviewLinkSpace.fromWire(parts[0]);
    if (space == null) {
      return null;
    }
    final String href = _decode(parts[2]);
    if (href.isEmpty) {
      return null;
    }
    return (space: space, context: _decode(parts[1]), href: href);
  }
  // 旧式：整段就是编码后的 href（只有一段）。
  final String href = _decode(payload);
  if (href.isEmpty) {
    return null;
  }
  return (space: null, context: null, href: href);
}

/// 转义异常时按原样返回：一次非法转义不该让整次点击消失。
///
/// 两种异常都要接：`%zz` / 结尾单个 `%` 抛 [ArgumentError]，而 `%FF`（合法转义、
/// 但解出来不是 UTF-8）抛 [FormatException]。漏掉后者会让**一条乱码回执直接抛到
/// 调用方的通道回调里**，整页的后续回执跟着停摆。
String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}
