# hyperlens 示例

一屏、一个文件（`lib/main.dart`），把宿主侧要走的路整条走一遍：**渲染 → 分发回执 →
从目录跳转 → 记住并还原阅读位置**。

[English](https://github.com/bigedev/hyperlens/blob/main/example/README.md) | 简体中文

## 运行

```sh
cd example
flutter pub get
flutter run          # android / ios / macos
```

包本身没有平台代码 —— 这里看到的是**宿主那一半**：一个 `WebViewWidget`、一个
JavaScript 通道，加几个按钮。

## 值得看的地方

| 步骤 | 在 `lib/main.dart` 里的位置 |
| --- | --- |
| 渲染 | `HyperlensPage.fromText(...).render(assets: ...)` —— Markdown 要资产，HTML 不要 |
| 回执 | `HyperlensBridge.channelName` + `PreviewEvent.parse`（两种文档同一个解析器） |
| 目录 | `PreviewOutlineReported` → 抽屉；点击执行 `HyperlensCommands.forPosition` |
| 位置 | 两个值分开：「此刻在哪」（`PreviewPositionReported`，每滚一次就更新）与「上次读到哪」—— 后者只在读者**离开**时定格（回顶部 / 目录跳转 / 切文档），定格的那个才作为 `restore:` 传回去 |
| 陈旧回执 | 每次提交带一个新 `token:`，对不上的回执丢掉：慢一拍的页面写不进下一份的账 |
| 语法树 | 先收 `PreviewSyntaxReported` 的骨架；工具栏按钮用 `HyperlensCommands.requestSyntaxAst()` 拉完整树 |
| 主题 | `HyperlensTheme.light / dark / ink` —— 配色与字号都由调用方给 |

底部两行，一行是最新回执、一行是定格下来的「上次位置」，不必开调试器就能看到每一步。
主题开关只重画**文档**：App 外壳保持 Material，因为外壳归宿主。

两份示例文档都写成**两段**：先英文、后中文。Markdown 那份还带**公式**（`$…$`、
`$$…$$` → KaTeX）与**图表**（`mermaid` 围栏）。这两样由包按内容自动门控：文档里没有
就不内联。真用上时载荷会到几 MB —— 那是 Mermaid 的体积，不是包在浪费。

HTML 那份演示另一面：HTML 页**不会**被注入 KaTeX / Mermaid（作者的页面归作者），
所以它的图表用内联 SVG、公式用 MathML。

## 平台

`webview_flutter` 官方实现覆盖 **android / ios / macos**。在 **windows / linux** 上本示例
照常编译运行，只是把 `render()` 产出的载荷以源码形式展示（不渲染）。那两平台接自己的
WebView 即可，其余代码不用改。
