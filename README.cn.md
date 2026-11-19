# hyperlens

源镜（hyperlens）：Markdown 与 HTML 的**源码关联预览**。

渲染出来的页面、大纲与语法树共用**同一套坐标** —— Markdown 用源码行、HTML 用
DOM 路径 —— 编辑器因此能在正文与预览之间来回移动时不必猜。

[English](README.md) | 简体中文

> **状态：0.1.0 开发中，尚未发布。**

## 它做什么

- **渲染**：把 Markdown / HTML 文档变成调用方自己 WebView 里显示的那份载荷 ——
  不带自己的 widget，也不对调用方的版式发表意见。
- **双向映射**：报告读者滚到了哪一行（HTML 侧是哪个 DOM 路径），下次打开再把
  预览送回原处。
- **大纲与语法树**：与预览同一次解析得出，任何目录视图都与正文一致。
- **命中定位**：搜索结果滚进视野并保持高亮，回执会说明锚点有没有找到。

## 它不做什么

- 不带页面 widget、路由与主题系统 —— 外壳归调用方。
- 不做编码检测：字节怎么解是调用方的事。
- 不联网：资产随包发布。

## 安装

```yaml
dependencies:
  hyperlens: ^0.1.0
```

调用方的 WebView 需要能通过 `packages/hyperlens/...` 加载包内资产；路径以常量形式
公开，调用方里不硬编码。

WebView 侧 `addJavaScriptChannel` 用的名字必须与渲染入口一致：Markdown 传
`HyperlensPage.fromText(channelName:)`，默认是
`HyperlensBridge.channelName`。**两边对不上时页面不报错**——脚本里那句守卫只是
什么都不发，表现是阅读位置与目录静默不更新，日志里也没有线索。

## 最短用法

```dart
import 'package:hyperlens/hyperlens.dart';

// ① 一份文档 → 一份载荷。类型按后缀判定（.md / .markdown / .html / .htm），
//    HTML 页不需要 assets。
final HyperlensPage page = HyperlensPage.fromText(
  source: text,
  path: entry.path,
  theme: theme,
);
final String html = await page.render(assets: const HyperlensRootBundleAssetLoader());

// ② 交给自己的 WebView。通道名两边必须一致，否则位置与目录静默不更新。
await controller.loadHtmlString(html);
controller.addJavaScriptChannel(
  HyperlensBridge.channelName,
  onMessageReceived: (message) {
    switch (PreviewEvent.parse(message.message)) {
      case PreviewRenderReady(:final result):
        onReady(result);          // ok（…）/ empty / 异常: …
      case PreviewPositionReported(:final position):
        remember(position);       // 下次打开送回这里
      case PreviewOutlineReported(:final outline):
        renderOutline(outline);   // 目录（Markdown / HTML 通用成员）
      default:
        break;                    // 语法树、命中、链接按需处理
    }
  },
);

// ③ 目录点击：拿命令去跑（Markdown 带行号，HTML 带 DOM 路径）
await controller.runJavaScript(
  HyperlensCommands.forPosition(entry.address, kind: page.kind),
);
```

自己拼页面或做诊断时才需要 `package:hyperlens/advanced.dart`（HTML 注入顺序、
标签扫描、Markdown 链接解析等）。主入口只保留「用这个包」需要的符号。

## 示例

[`example/`](example/) 是可运行的演示：`lib/main.dart` 走渲染流水线（渲染 → 回执 →
目录跳转 → 位置还原），外壳在 `lib/src/`。在 android / ios / macos 上 `flutter run`
直接看。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
