## 0.1.0

Unreleased. First extraction from the preview implementation of an editor app.

- Markdown rendering payload with line/block markers, safe HTML (DOMPurify), and
  KaTeX / mhchem math.
- HTML rendering payload with a DOM-path address for restoring the reading position.
- The HTML outline also picks up ARIA headings (`role="heading"` with `aria-level`,
  defaulting to 2 and capped at 6) next to `<h1>~<h6>`; one entry per heading, so a
  heading nested inside another keeps only the outer one.
- The HTML outline watches the document height (`ResizeObserver`) and re-scans after a
  disclosure panel opens or closes, or an image grows — no page reload needed.
- New syntax-tree skeleton receipt (`ast`): Markdown reuses the same lexer as the render
  pass, HTML walks the browser's own `document`; the payload is clipped by node count,
  depth and byte gates. Dart side exposes `PreviewSyntaxTree` / `PreviewSyntaxNode`
  (the full tree and host-side panels are still to come).
- Receipt protocol: render ready, link tapped, position reported, outline reported,
  focus applied, anchor scrolled, unknown message.
- Source-linked outline and syntax tree built from the same parse.
- Web assets (marked, DOMPurify, KaTeX, mhchem, highlight.js, Mermaid) declared by
  the package; the host stops declaring them.
- Public surface: `MarkdownPage` is the single render entry; `HyperlensAssets`,
  `HyperlensBridge`, `HyperlensTheme`, `HyperlensLogger` and `HyperlensAssetLoader`
  (`RootBundleAssetLoader` for Flutter) are the rest of it.
- The WebView channel name is injected instead of being hard-coded: the Markdown
  template takes it through a placeholder, `htmlAnchorScript(channelName:)` for the
  HTML side, so a host can register its own name. Either has to match
  `addJavaScriptChannel`, and a name that is not a valid identifier is rejected while
  the script is assembled.
- Missing enhanced assets (KaTeX, mhchem, Mermaid) degrade to plain text and report
  through `HyperlensLogger` instead of failing the whole page.
- `HyperlensTheme` treats dark and ink as independent axes: ink is a monochrome
  overlay shipped in both polarities (`*-ink.css` for the default light e-ink look,
  `*-ink-dark.css` for its inverse).
- Mermaid stays fully visible on dark backdrops: Sankey link bands were lost because
  Mermaid hard-codes `mix-blend-mode: multiply` on them, which only works over a light
  page; the blend mode is now set back to `normal` for the dark themes only, so the
  light and light-ink looks are unchanged.
- Reading positions are one address type (breaking): `SourceAddress` for a Markdown source
  line, `DomAddress` for an HTML DOM path such as `body>div#main>p:nth(3)`, plus
  `PreviewViewport` carrying the per-frame viewport lines that drive outline highlighting.
  `PreviewAnchor` (`block` / `offset` / `scrollY`) is gone, pages are only told to scroll
  through `HyperlensCommands` (`mdScrollToLine` / `hyperLensScrollToPath`), and a position
  that cannot be resolved puts the reader back at the top instead of guessing. Saved
  positions still parse: a stored `line` is reused, a pixel-only record falls back to top.
