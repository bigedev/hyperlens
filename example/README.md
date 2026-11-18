# hyperlens example

One screen, one file (`lib/main.dart`), the whole path a host has to walk: **render →
route receipts → jump from the outline → remember the reading position.**

English | [简体中文](https://github.com/bigedev/hyperlens/blob/main/example/README.cn.md)

## Run

```sh
cd example
flutter pub get
flutter run          # android / ios / macos
```

The package itself has no platform code — what you see here is the *host* half: a
`WebViewWidget`, a JavaScript channel and a couple of buttons.

## What to look at

| Step | In `lib/main.dart` |
| --- | --- |
| Render | `HyperlensPage.fromText(...).render(assets: ...)` — Markdown needs assets, HTML does not |
| Receipts | `HyperlensBridge.channelName` + `PreviewEvent.parse` (one parser for both document kinds) |
| Outline | `PreviewOutlineReported` → the drawer; a tap runs `HyperlensCommands.forPosition` |
| Position | two separate values: *live* (`PreviewPositionReported`, every scroll) and *last read* — frozen only when the reader leaves (back to top / outline jump / switching document) — and the frozen one is what goes back in as `restore:` |
| Stale receipts | every commit gets a `token:`; receipts carrying another one are dropped, so a slow page cannot write into the next one |
| Syntax tree | skeleton from `PreviewSyntaxReported` first; the toolbar button requests the full tree with `HyperlensCommands.requestSyntaxAst()` |
| Theme | `HyperlensTheme.light / dark / ink` — colours and font size come from the caller |

The bottom bar shows two lines — the latest receipt and the frozen *last position* — so every
step is visible without a debugger. The theme switch repaints the **document** only; the app
chrome stays Material on purpose, because the host owns it.

Both sample documents are written in two parts — English first, Chinese second. The
Markdown one also carries **math** (`$…$`, `$$…$$` → KaTeX) and a **diagram**
(a `mermaid` fence). Both are gated by the package on content: no math, no diagram, no
inlined bundle. Expect a multi-MB payload when a document does use them — that is
Mermaid, not the library being wasteful.

The HTML sample shows the other side of that coin: an HTML page gets **no** injected
KaTeX/Mermaid (author page stays the author's), so its chart is inline SVG and its
formula is MathML.

## Platforms

`webview_flutter` officially implements **android / ios / macos**. On **windows / linux**
this example still builds and runs: it shows the payload that `render()` produced instead
of displaying it. Swap in your own WebView there and the rest of the code is unchanged.
