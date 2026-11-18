/// 源镜（hyperlens）：Markdown 与 HTML 的**源码关联预览**。
///
/// 本包是**逻辑包**：渲染载荷怎么拼、回执怎么解、大纲与语法树的坐标怎么算、
/// 资产在包里的路径是什么。它不带 widget、不碰 WebView，`lib/` 内不 import
/// flutter —— pubspec 声明 `sdk: flutter` 只为 `flutter: assets:` 那一段。
///
/// 三处边界（都不在本包里，由宿主实现）：
/// - 读资产：`lib/root_bundle.dart`（唯一 import flutter/services 的文件）或
///   调用方自己的实现；
/// - 起页面：宿主自己的 WebView；
/// - 画界面：宿主自己的抽屉、工具栏、主题。
library;

export 'src/asset/asset_loader.dart';
export 'src/asset/hyperlens_assets.dart';
export 'src/host/logger.dart';
export 'src/html/html_anchor.dart';
export 'src/html/html_document_style.dart';
export 'src/markdown/bridge.dart';
export 'src/markdown/escape.dart';
export 'src/markdown/extras.dart';
export 'src/markdown/links.dart';
// payload.dart 是渲染入口的内部实现（`MarkdownPage` 用），不在 barrel 里导出。
export 'src/markdown/markdown_page.dart';
export 'src/model/anchor_handoff.dart';
export 'src/model/code_anchor.dart';
export 'src/model/document_outline.dart';
export 'src/model/html_outline.dart';
export 'src/model/hyperlens_theme.dart';
export 'src/model/markdown_outline.dart';
export 'src/model/preview_anchor.dart';
export 'src/model/preview_focus.dart';
export 'src/protocol/hyperlens_bridge.dart';
