import '../asset/asset_loader.dart';
import '../host/logger.dart';
import '../model/hyperlens_theme.dart';
import '../model/preview_position.dart';
import '../model/preview_focus.dart';
import '../protocol/hyperlens_bridge.dart';
import 'payload.dart';

/// 渲染一页 Markdown 预览：**包对外的唯一渲染入口**。
///
/// 为什么是一个对象而不是两个自由函数：载荷（`buildMarkdownPayload`）与整页 HTML
/// （`buildMarkdownHtml`）是同一件事的两半，调用方必须先拼载荷再拼页面，顺序错了
/// 不报错、只表现为「页面能开但没内容」。合成一个对象后，顺序与参数对应关系由包
/// 自己保证，新增一个渲染参数也不用改使用方的调用点。
///
/// 一次 [render] 就是一次完整的「模板 + 资源 + 载荷」拼装，产物直接交给
/// `loadHtmlString`；WebView 生命周期、看门狗、回执路由都在使用方（包不碰 UI）。
///
/// ```dart
/// final page = MarkdownPage(
///   markdown: source,
///   token: 'doc-42:v1',
///   theme: HyperlensTheme.light,
///   restore: PreviewPosition.top,
/// );
/// final html = await page.render(assets: const RootBundleAssetLoader());
/// ```
final class MarkdownPage {
  const MarkdownPage({
    required this.markdown,
    required this.token,
    required this.theme,
    required this.restore,
    this.focus,
    this.channelName = HyperlensBridge.channelName,
  });

  /// 正文（Markdown 原文）。
  final String markdown;

  /// 回执凭据：页面每条带凭据的回执都会回传它。
  ///
  /// 由调用方自定（常见做法是「文档标识 + 版本」）。作用是丢弃换文档后旧页面的
  /// 收尾回执 —— 否则上一篇的位置与章节清单会盖到新文档上。
  final String token;

  /// 主题（底色 / 正文色 / 描边色 / 字号 / 深色与墨水屏档）。
  final HyperlensTheme theme;

  /// 阅读位置还原目标。
  ///
  /// **不能省**：不显式给一个位置，ArkWeb 会把上一篇的滚动位置留给下一篇
  /// （真机实测停在中腰），读者一进来就找不到开头。新文档传 `PreviewPosition.top`。
  ///
  /// Markdown 页只认 [SourceAddress]；传 [DomAddress] 时按「回顶部」处理（页面
  /// 没有 DOM 路径可言，日志里会说明）。
  final PreviewPosition restore;

  /// 搜索命中定位：非空时渲染完滚到那一段并高亮。
  ///
  /// 与 [restore] 同时给出时以命中为准（页面里 `payload.restore && !payload.focus`），
  /// 因为读者要的是命中，不是上次读到哪。
  final PreviewFocus? focus;

  /// 注入页面的 JS 通道名（默认 [HyperlensBridge.channelName]）。
  ///
  /// 使用方要改的话，WebView 侧 `addJavaScriptChannel` 必须用同一个名字。
  final String channelName;

  /// 拼出可直接提交给 WebView 的整页 HTML。
  ///
  /// [assets] 负责读随包资产（`HyperlensAssets` 里的常量作 path）。
  /// [logger] 可选：只在增强资产缺失这类降级路径上说话。
  Future<String> render({
    required HyperlensAssetLoader assets,
    HyperlensLogger? logger,
  }) async {
    HyperlensBridge.checkChannelName(channelName);
    final String payload = buildMarkdownPayload(
      markdown: markdown,
      dark: theme.isDark,
      fontSize: theme.fontSize,
      token: token,
      restore: restore,
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

}
