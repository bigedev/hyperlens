# hyperlens 示例

一屏，宿主侧要走的路整条都在 `lib/main.dart` 里：**渲染 → 分发回执 → 从目录跳转 →
记住并还原阅读位置**。其余都是外壳 —— 演示文档、工具栏、抽屉、页脚、语法树弹层
放在 `lib/src/`，入口文件才读得下去。

[English](https://github.com/bigedev/hyperlens/blob/main/example/README.md) | 简体中文

## 运行

```sh
cd example
flutter pub get
flutter run          # android / ios / macos
```

包本身没有平台代码 —— 这里看到的是**宿主那一半**：一个 `WebViewWidget`、一个
JavaScript 通道，加几个按钮。

## 文件

| 文件 | 干什么 |
| --- | --- |
| `lib/main.dart` | 入口 + 渲染流水线：提交、回执分发、位置语义 |
| `lib/src/demo_documents.dart` | 两份演示文档（Markdown / HTML） |
| `lib/src/preview_toolbar.dart` | 文档档位、主题档位 |
| `lib/src/outline_drawer.dart` | 目录抽屉 |
| `lib/src/status_bar.dart` | 页脚两行 —— 「此刻在哪」与「上次读到哪」 |
| `lib/src/syntax_sheet.dart` | 语法树弹层 |
| `lib/src/platform_fallback.dart` | 哪些平台有 WebView，其余平台的载荷视图 |

## 值得看的地方

| 步骤 | 在哪 |
| --- | --- |
| 渲染 | `main.dart` → `_render()`：`HyperlensPage.fromText(...).render(assets: ...)` —— Markdown 要资产，HTML 不要 |
| 回执 | `main.dart` → `_onMessage()`：`HyperlensBridge.channelName` → `PreviewReceiptDispatcher.dispatch`（两种文档同一个入口；小回执同步、大回执后台解析、过时的骨架会被丢掉） |
| 目录 | 清单在 `src/outline_drawer.dart`；点击回到 `main.dart` → `_jumpTo()`，执行 `HyperlensCommands.forPosition` |
| 位置 | `main.dart` 里两个字段：「此刻在哪」`_live`（`PreviewPositionReported`，每滚一次就更新）与「上次读到哪」`_bookmark` —— 后者只在读者**离开**时定格（回顶部 / 目录跳转 / 切文档），定格的那个才作为 `restore:` 传回去 |
| 陈旧回执 | `main.dart` → `_fromLivePage()`：每次提交带一个新 `token:`，对不上的回执丢掉：慢一拍的页面写不进下一份的账 |
| 语法树 | 先收 `PreviewSyntaxReported` 的骨架；`main.dart` → `_showSyntax()` 用 `HyperlensCommands.requestSyntaxAst()` 拉完整树，弹层在 `src/syntax_sheet.dart`。HTML 走同一条命令 —— 它一次带全，这条命令是**重发**（首屏那条可能丢） |
| 主题 | `src/preview_toolbar.dart` → `demoThemes`：`HyperlensTheme.light / dark / ink` —— 配色与字号都由调用方给 |

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
