/// 底层工具：**自己拼页面**或做**诊断**时才需要。
///
/// 日常用法只要 `package:hyperlens/hyperlens.dart`：
///
/// ```dart
/// final html = await HyperlensPage.fromText(source: text, path: p).render(
///   assets: const HyperlensRootBundleAssetLoader(),
/// );
/// final PreviewEvent event = PreviewEvent.parse(message);
/// ```
///
/// 这里的符号是那两条路**内部**用的零件：HTML 的注入顺序、脚本与样式的拼装、
/// 标签扫描、Markdown 链接解析与扩展块探测。单独放在第二个入口，是为了让
/// 「用这个包」和「借这个包自己搭」在 import 处就能分开 —— 主入口少一个选择，
/// 使用方就少一次「我是不是该手工拼」的犹豫。
///
/// 这里的函数**不承诺稳定**：它们的签名跟着内部实现走，替换实现时可能变。
library;

export 'src/html/html_anchor.dart';
export 'src/html/html_document_style.dart';
export 'src/html/html_tag_scan.dart';
export 'src/markdown/escape.dart';
export 'src/markdown/extras.dart';
export 'src/markdown/links.dart';
