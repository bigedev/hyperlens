/// Markdown 内链的解析：把文档里的 `href` 变成「要做什么」。
///
/// 背景（真机）：预览页由 `loadHtmlString` 加载（**没有 base url**），
/// 模板里也没有拦链接 ⇒ 点一个相对链接就是让 WebView 去导航到一个解析不出来的
/// 地址，表现是「整页变空白」（CPF-Flutter 的文档索引 README 就是这样）。
/// 所以链接点击必须在 WebView 内拦下、回传 Dart，再由这里判定去向。
///
/// 纯函数、无 IO：便于单测，也让 WebView 侧只管「把 href 交出来」。
library;

import 'package:path/path.dart' as p;

import '../protocol/link_intent.dart';

/// 一次链接点击的去向。
sealed class MarkdownLinkAction {
  const MarkdownLinkAction();
}

/// 仓库内的文件/目录（[relPath] 相对仓库根，已归一化）。
///
/// **不带尾斜杠**：由上层再确认目标是文件还是目录。
///
/// [fragment] 是 `a.html#sec2` 里那一段（已解码，不含 `#`）：上层打开目标时把它
/// 交给预览的落位（DOM 路径 `#id`），「第 5 章第 2 节」才落得到节。null = 链接
/// 没带片段。
class OpenRepoFile extends MarkdownLinkAction {
  const OpenRepoFile(this.relPath, {this.fragment});

  final String relPath;
  final String? fragment;
}

/// 交给系统浏览器 / 外部应用的地址。
class OpenExternal extends MarkdownLinkAction {
  const OpenExternal(this.url);

  final String url;
}

/// 不处理：页内锚点、空链接、越出仓库根、不支持的协议。
class IgnoreLink extends MarkdownLinkAction {
  const IgnoreLink();
}

// 外链表只有一份：`protocol/link_intent.dart` 的 `kPreviewExternalSchemes`。
// 这里原本是私有副本，与注入脚本旁边那张表「必须同步」只能靠注释约束 ——
// 漏一个 `tel:`，表现只是「点电话号码没反应」。

/// 把 [href] 按「它写在 [fromRelPath] 这个文件里」来解析。
///
/// 支持：`./a/b.md`、`../c.md`、`/d.md`（相对仓库根）、带 `#锚点`/`?query`、
/// `%20` 转义、`<url>` 包裹、协议相对 `//host/path`、以及 http/https/mailto/tel。
///
/// 跨文件的 `#片段` 不再丢弃：它随 [OpenRepoFile.fragment] 交给上层落位
/// （纯锚点 `#x` 仍归 [IgnoreLink] —— 那是同一份文档内部的滚动，页面自己会做）。
MarkdownLinkAction resolveMarkdownLink({
  required String fromRelPath,
  required String href,
}) {
  String link = href.trim();
  if (link.isEmpty) {
    return const IgnoreLink();
  }
  // 页内锚点：WebView 自己就能滚，不必绕一圈 Dart
  if (link.startsWith('#')) {
    return const IgnoreLink();
  }
  // Markdown 允许把地址写成 <url>
  if (link.length > 2 && link.startsWith('<') && link.endsWith('>')) {
    link = link.substring(1, link.length - 1).trim();
  }
  // 协议相对：//example.com/a → https://example.com/a
  if (link.startsWith('//')) {
    link = 'https:$link';
  }

  final Uri? uri = Uri.tryParse(link);
  if (uri != null && uri.scheme.isNotEmpty) {
    if (kPreviewExternalSchemes.contains(uri.scheme.toLowerCase())) {
      return OpenExternal(link);
    }
    return const IgnoreLink(); // file: / ohos: / javascript: 之类一律不跳
  }

  // 仓库内路径：先切下锚点（片段留着交给落位），再切掉查询串
  String path = link;
  String? fragment;
  final int hash = path.indexOf('#');
  if (hash >= 0) {
    final String raw = path.substring(hash + 1);
    path = path.substring(0, hash);
    if (raw.isNotEmpty) {
      // 作者可能写 `#%E4%B8%AD`：解码一次，落到页面里按 id 找才对得上
      try {
        fragment = Uri.decodeComponent(raw);
      } on ArgumentError {
        fragment = raw;
      }
    }
  }
  final int query = path.indexOf('?');
  if (query >= 0) {
    path = path.substring(0, query);
  }
  if (path.isEmpty) {
    return const IgnoreLink();
  }

  // 反斜杠按分隔符处理；`%20` 这类转义还原（Markdown 里的空格常被编码）
  path = path.replaceAll(r'\', '/');
  // 尾斜杠是「这是目录」的信号，normalize 之后要还回去
  final bool isDir = path.endsWith('/');
  try {
    path = Uri.decodeComponent(path);
  } on ArgumentError {
    // 转义有问题时按原样使用，别把整次点击丢掉
  }

  // 以 `/` 开头 = 相对仓库根；否则相对**当前文件所在目录**
  final String base = path.startsWith('/') ? '' : p.posix.dirname(fromRelPath);
  final String joined = p.posix.normalize(
    p.posix.join(base, path.replaceFirst(RegExp(r'^/+'), '')),
  );
  if (joined.isEmpty ||
      joined == '.' ||
      joined == '..' ||
      joined.startsWith('../')) {
    return const IgnoreLink(); // 越出仓库根（或指向根本身）
  }
  // normalize 是否保留尾斜杠随实现而变，这里统一成「不带尾斜杠」再加
  final String clean =
      joined.endsWith('/') ? joined.substring(0, joined.length - 1) : joined;
  return OpenRepoFile(isDir ? '$clean/' : clean, fragment: fragment);
}
