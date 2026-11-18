# hyperlens

Source-linked preview for Markdown and HTML.

The rendered page, the outline and the syntax tree share **one coordinate system** —
the source line for Markdown, the DOM path for HTML — so an editor can move between
source and preview without guessing.

English | [简体中文](README.cn.md)

> **Status: 0.1.0 in progress.** Nothing has been published yet.

## What it does

- **Render** a Markdown or HTML document into the payload a host shows in its own
  WebView — no widget of its own, no opinion about the host's layout.
- **Map both ways**: report the source line the reader has scrolled to, and scroll
  the preview back to a remembered line (or DOM path) after a restart.
- **Outline and syntax tree** derived from the same parse, so the drawer, the
  minimap and the preview cannot disagree.
- **Search hits** scroll into view and stay highlighted; the receipt says whether
  the anchor was found.

## What it does not do

- No page widgets, no routing, no theming system — the host keeps its own shell.
- No encoding detection: bytes are the caller's business.
- No network access: assets ship inside the package.

## Install

```yaml
dependencies:
  hyperlens: ^0.1.0
```

The host WebView must be able to load package assets through
`packages/hyperlens/...`; the asset paths are exposed as constants so nothing in the
host hard-codes them.

The name passed to `addJavaScriptChannel` must match what the render entry uses:
`MarkdownPage(channelName:)` for Markdown, `htmlAnchorScript(..., channelName:)` for
HTML, defaulting to `HyperlensBridge.channelName`. **A mismatch fails silently** — the
guard in the injected script simply posts nothing, so reading positions and the outline
stop updating with no error anywhere in the logs.

## License

MIT — see [LICENSE](LICENSE).
