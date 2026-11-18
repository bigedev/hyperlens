/// 源镜（hyperlens）：Markdown 与 HTML 的**源码关联预览**。
///
/// 一套概念，两种文档：地址（源码行 / DOM 路径）、视口、命中、大纲、语法树、
/// 主题、回执。用法只有一个入口 ——
///
/// ```dart
/// final html = await HyperlensPage.fromText(
///   source: text,
///   path: entry.path,          // .md / .markdown / .html / .htm
///   theme: theme,
/// ).render(assets: const HyperlensRootBundleAssetLoader());
///
/// final PreviewEvent event = PreviewEvent.parse(message);
/// ```
///
/// 本包是**逻辑包**：渲染载荷怎么拼、回执怎么解、坐标怎么算、资产路径是什么。
/// 它不带 widget、不碰 WebView，`lib/` 内不 import flutter —— pubspec 声明
/// `sdk: flutter` 只为 `flutter: assets:` 那一段。
///
/// 三处边界（都不在本包里，由调用方实现）：
/// - 读资产：`lib/root_bundle.dart`（唯一 import flutter/services 的文件）或
///   调用方自己的实现；
/// - 起页面：调用方自己的 WebView；
/// - 画界面：调用方自己的目录、工具栏、主题。
///
/// 自己拼页面或做诊断时才需要的底层工具在 `package:hyperlens/advanced.dart`：
/// 主入口只保留「用这个包」需要的符号，少一个选择就少一次犹豫。
library;

export 'src/asset/asset_loader.dart';
export 'src/asset/hyperlens_assets.dart';
export 'src/host/logger.dart';
export 'src/protocol/events.dart';
// payload.dart 是渲染入口的内部实现（`HyperlensPage` 用），不在 barrel 里导出。
export 'src/hyperlens_page.dart';
export 'src/model/anchor_handoff.dart';
export 'src/model/code_anchor.dart';
export 'src/model/document_outline.dart';
export 'src/model/html_outline.dart';
export 'src/model/hyperlens_theme.dart';
export 'src/model/markdown_outline.dart';
export 'src/model/preview_position.dart';
export 'src/model/preview_syntax.dart';
export 'src/model/preview_focus.dart';
export 'src/protocol/commands.dart';
export 'src/protocol/hyperlens_bridge.dart';
