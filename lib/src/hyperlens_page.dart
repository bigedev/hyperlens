import 'package:meta/meta.dart';

import 'asset/asset_loader.dart';
import 'host/logger.dart';
import 'html/html_anchor.dart';
import 'html/html_document_style.dart';
import 'markdown/payload.dart';
import 'model/hyperlens_theme.dart';
import 'model/preview_focus.dart';
import 'model/preview_position.dart';
import 'model/preview_syntax.dart';
import 'protocol/focus_script.dart';
import 'protocol/hyperlens_bridge.dart';

/// 渲染一页预览：**包对外的唯一渲染入口**，Markdown 与 HTML 同一个形状。
///
/// 对使用方来说，hyperlens 是「一份文档 → 一份可以直接交给 `loadHtmlString` 的
/// 载荷」。文档只有两种载体，而**概念是同一套**：地址、视口、大纲、语法树、主题、
/// 回执。分成两个入口之后，这些概念会在调用点被拆成两套参数、两套顺序，而其中
/// 「先摘作者脚本还是先判可见内容」「命中与还原谁优先」这类顺序，错了都不报错 ——
/// 只表现为白屏、跳回旧位置、目录空着。
///
/// ```dart
/// final html = await HyperlensPage.fromText(
///   source: text,
///   path: 'docs/a.md',
///   theme: theme,
/// ).render(assets: const HyperlensRootBundleAssetLoader());
/// ```
///
/// 一次 [render] 就是一次完整的「模板 / 样式 / 脚本 / 载荷」拼装；WebView 生命周期、
/// 看门狗、回执路由都在使用方（包不碰 UI）。
@immutable
final class HyperlensPage {
  /// 从一段文本建一页。
  ///
  /// 文档类型按 [kind] → [path] 后缀（`.md` / `.markdown` / `.html` / `.htm`）
  /// 的顺序判定，判不出就抛 [ArgumentError] —— **不看内容猜**：Markdown 里内联 HTML
  /// 是常态，嗅探会把 `.md` 当成 HTML 页，正文里的 `#` / `|` 全变成字面量。
  factory HyperlensPage.fromText({
    required String source,
    String? path,
    PreviewSourceKind? kind,
    String token = '',
    HyperlensTheme theme = HyperlensTheme.light,
    PreviewPosition? restore,
    PreviewFocus? focus,
    String channelName = HyperlensBridge.channelName,
    bool ownPage = false,
    bool scripts = true,
  }) {
    final PreviewSourceKind resolved = _resolveKind(path: path, kind: kind);
    final PreviewPosition position = restore ??
        (resolved == PreviewSourceKind.markdown
            ? PreviewPosition.top
            : PreviewDomAddress.body);
    final _Document document = resolved == PreviewSourceKind.markdown
        ? _MarkdownDocument(source, token)
        : _HtmlDocument(source, ownPage: ownPage, scripts: scripts);
    return HyperlensPage._(
      document: document,
      kind: resolved,
      theme: theme,
      restore: position,
      focus: focus,
      channelName: channelName,
    );
  }

  const HyperlensPage._({
    required _Document document,
    required this.kind,
    required this.theme,
    required this.restore,
    required this.focus,
    required this.channelName,
  }) : _document = document;

  /// 这份文档是哪一类（由 [path] / `kind` 判定，见 `fromText`）。
  final PreviewSourceKind kind;

  /// 主题（底色 / 正文色 / 描边色 / 字号 / 深色与墨水屏档）。两种文档共用。
  final HyperlensTheme theme;

  /// 阅读位置还原目标：Markdown 用行号（[PreviewSourceAddress]），HTML 用路径（[PreviewDomAddress]）。
  ///
  /// 不传时按类型补：Markdown 从头（[PreviewPosition.top]），HTML 回到 `body`。
  /// 显式给仍然有意义 —— 不传就等于「新文档从头」，不会继承上一篇的滚动位置。
  final PreviewPosition restore;

  /// 搜索命中定位：非空时滚到那一段并高亮（**优先于** [restore]）。
  final PreviewFocus? focus;

  /// 注入页面的 JS 通道名（默认 [HyperlensBridge.channelName]）。
  ///
  /// 使用方要改的话，WebView 侧 `addJavaScriptChannel` 必须用同一个名字。
  final String channelName;

  final _Document _document;

  /// 脚本不执行时这页还剩不剩内容（HTML 用得到；Markdown 恒 false）。
  ///
  /// 判的是**作者的原文**：先摘掉作者脚本再看，因为「内容全在脚本里」正是要提示的
  /// 那种页面 —— 读者看到的是一片白，而文件其实有内容。
  bool get blankWithoutScripts => switch (_document) {
        _MarkdownDocument() => false,
        _HtmlDocument(:final String source) =>
          !htmlHasVisibleContent(stripAuthorScripts(source)),
      };

  /// 拼出可直接提交给 WebView 的整页 HTML。
  ///
  /// [assets] 负责读随包资产（`HyperlensAssets` 里的常量作 path）；Markdown 必须有，
  /// HTML 不需要（那边不加载模板与 marked），传了也不用。
  /// [logger] 可选：只在增强资产缺失这类降级路径上说话。
  Future<String> render({
    HyperlensAssetLoader? assets,
    HyperlensLogger? logger,
  }) async {
    HyperlensBridge.checkChannelName(channelName);
    final _Document document = _document;
    if (document is _MarkdownDocument) {
      return _renderMarkdown(document.source, document.token, assets, logger);
    }
    final _HtmlDocument html = document as _HtmlDocument;
    return _renderHtml(
      html.source,
      ownPage: html.ownPage,
      scripts: html.scripts,
    );
  }

  Future<String> _renderMarkdown(
    String markdown,
    String token,
    HyperlensAssetLoader? assets,
    HyperlensLogger? logger,
  ) async {
    if (assets == null) {
      throw ArgumentError(
        'Markdown 预览需要 assets：页面模板、marked、highlight、KaTeX 都是随包资产。'
        'HTML 预览不需要（那边不加载模板）。',
      );
    }
    final String receipt = token.isEmpty ? HyperlensBridge.noToken : token;
    if (receipt != HyperlensBridge.noToken) {
      HyperlensBridge.checkToken(receipt);
    }
    final String payload = buildMarkdownPayload(
      markdown: markdown,
      dark: theme.isDark,
      fontSize: theme.fontSize,
      token: receipt,
      // Markdown 的页面只认行号；路径地址到这里按「从头」处理
      restore: restore is PreviewSourceAddress ? restore : PreviewPosition.top,
      focus: focus,
    );
    return buildMarkdownHtml(
      load: assets.loadString,
      dark: theme.isDark,
      background: theme.background,
      foreground: theme.foreground,
      border: theme.border,
      payload: payload,
      markdown: markdown,
      ink: theme.isInk,
      channelName: channelName,
      logger: logger,
    );
  }

  String _renderHtml(
    String html, {
    required bool ownPage,
    required bool scripts,
  }) {
    // 开脚本就要摘作者脚本（只为我们自己的脚本开口子）；自有页面不摘。
    final bool strip = scripts && stripsAuthorScripts(ownPage: ownPage, anchor: true);
    final String source = strip ? stripAuthorScripts(html) : html;
    if (!scripts) {
      return source;
    }
    // 先样式后脚本：样式不依赖 DOM 是否就绪，脚本要在解析完正文后跑才有东西可扫。
    final String styled = injectStyleIntoHtml(
      source,
      htmlPreviewCss(
        backgroundHex: theme.background,
        zoom: htmlPreviewZoom(theme.fontSize),
        dark: theme.isDark,
        ink: theme.isInk,
        // 深色档且作者没声明整页底色：底色是我们换上去的，UA 默认字色（黑字）
        // 会和它打架，必须接管；作者自己定了底色就让它保持原样。
        overrideTextColor:
            theme.isDark && !htmlDeclaresPageBackground(source),
        foregroundHex: theme.foreground,
      ),
    );
    final StringBuffer script = StringBuffer(
      // 有命中时不让还原脚本按住位置：否则它会把页面拽回旧位置，和命中抢滚动条
      htmlAnchorScript(
        restore,
        channelName: channelName,
        hold: focus == null,
      ),
    );
    if (focus != null) {
      // 命中脚本排在后面：先摆好页面，再滚动到命中处
      script.write('\n${previewFocusScript(focus!, channelName: channelName)}');
    }
    return injectScriptIntoHtml(styled, script.toString());
  }

  static PreviewSourceKind _resolveKind({
    required String? path,
    required PreviewSourceKind? kind,
  }) {
    if (kind != null) {
      return kind;
    }
    final String lower = (path ?? '').toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return PreviewSourceKind.markdown;
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return PreviewSourceKind.html;
    }
    throw ArgumentError(
      '判不出文档类型：给 path（.md / .markdown / .html / .htm）或显式 kind。'
      '不看内容猜 —— Markdown 里内联 HTML 是常态。',
    );
  }
}

/// 两种文档的差异收在这里：入口只有一个，参数各自完整。
@immutable
sealed class _Document {
  const _Document(this.source);

  final String source;
}

final class _MarkdownDocument extends _Document {
  const _MarkdownDocument(super.source, this.token);

  final String token;
}

final class _HtmlDocument extends _Document {
  const _HtmlDocument(super.source, {required this.ownPage, required this.scripts});

  /// 调用方自己生成的页面：不摘里面的脚本（那通常就是它自己的桥）。
  final bool ownPage;

  /// 是否注入我们的桥脚本（关掉就只有静态内容，位置 / 目录 / 语法树都不会来）。
  final bool scripts;
}
