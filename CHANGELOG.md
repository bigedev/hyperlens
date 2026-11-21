## 0.2.2

Receipts now have a single entry point, so a host no longer decides whether a given receipt is
worth moving off the main isolate — and HTML can re-send its syntax tree on demand.

- New `PreviewReceiptDispatcher`: hand every channel message to `dispatch()` and the package
  takes it from there. Small receipts are parsed inline, big ones (the syntax tree can reach
  2MB) are decoded in a background isolate, and the threshold stays internal — callers no
  longer carry a "how long counts as big" constant. The same document posts twice (the
  skeleton at render time, the full tree when the syntax panel asks), so a late skeleton is
  dropped as stale when another tree has already landed or a newer request returned first.
  The panel never falls back from the full tree to the skeleton. Platforms without isolates
  degrade to inline parsing.
- The constructor takes an optional `onLog`: one line for the off-thread duration of a big
  receipt, one for each dropped stale receipt. Silent by default.
- The injected HTML script now exposes `window.hyperlensSyntaxAst()` (the same name Markdown
  uses). HTML still sends its whole tree at once, but that first receipt can be lost (page
  reload, blank-page retry) — a caller opening the syntax panel can ask with
  `HyperlensCommands.requestSyntaxAst()` for another one.
- The library docs, the example and both READMEs now use this entry point; the example's
  syntax sheet shows Markdown (skeleton → full tree) and HTML (re-send) taking the same
  command.

## 0.2.1

No change to the library itself — this release makes the artifact's third-party notices match
what is actually inside it.

- `assets/web/mermaid.min.js` is rebuilt. Besides mermaid and KaTeX it carries 53 further
  dependencies (the d3 family, the cytoscape family, dagre-d3-es, dompurify, marked,
  lodash-es, …), distributed under MIT / ISC / BSD-3-Clause / (MPL-2.0 OR Apache-2.0). The
  complete list — every package with its copyright line, plus the verbatim text of all four
  licenses — is inlined as a comment at the end of the artifact, so the notices travel with
  every copy of the file.
- New `assets/licenses/mermaid-bundle.txt`: the same list as plain text, for a host's license
  page to read directly. `mermaid.txt` only ever held the two MIT texts of the primary works
  (mermaid, KaTeX) — it could not tell a reader that the file also contains 53 other packages.
- `THIRD_PARTY_NOTICES.md` / `.cn.md`: the claim that there is no fourth-party code inside the
  artifact is gone. The two texts are now explained as a pair, and one note flags the second
  dompurify (3.4.18, brought along by mermaid) that rides inside the file alongside the
  separately shipped `purify.min.js` (3.2.6) — same license, different code.

## 0.2.0

Link clicks now have one protocol, owned by the package: the criteria for when a click
is intercepted, the receipt envelope, and the list of schemes that count as "leave the
document". A caller injects and receives — it no longer copies either table.

- New `PreviewLinkSpace` (`repo` / `book`) plus `linkReceipt()` / `parseLinkReceipt()` /
  `isExternalPreviewLink()` / `kPreviewExternalSchemes` in
  `lib/src/protocol/link_intent.dart`. The private scheme list in `links.dart` is gone;
  both sides now read the exported one.
- The link receipt carries the address space: `link <space> <context> <encoded href>`
  (e.g. `link repo docs%2Fchap2.html chap2.html%23sec2`). `context` is what lets a caller
  drop a late receipt from the page it has just left — the old envelope left that to
  `href` alone, and a late tap could be applied to the new page. The plain
  `link <encoded href>` form is still understood, so existing templates keep working.
- `PreviewLinkTapped` gains `space` and `context`. `HtmlPreviewView`-style callers can
  compare them with the page they configured and ignore everything else.
- `HyperlensPage.fromText` / `htmlAnchorScript` accept `linkSpace` / `linkContext`: the
  injected HTML script posts the enriched envelope itself, so a page no longer needs a
  second, hand-written click script (two scripts meant two receipts for one click, and
  the second was only caught by a "same place" guard downstream).
- The injected HTML script reports the reading position before the link, in the same JS
  turn (one capture-phase listener registered earlier than the link one), so a back
  stack gets the position the reader left from rather than the last settled one.
- A receipt the package cannot make sense of — wrong segment count, unknown address
  space, broken escaping — is reported as unknown instead of being handed to the caller
  as a link (`%FF`-style escapes used to throw out of the parser).
- `OpenRepoFile` keeps the `#fragment` of a cross-file link (`fragment`, decoded):
  `README.md#getting-started` no longer loses the section. A bare `#anchor` inside one
  document is still left to the page's own scrolling.
- The example now shows the link path end to end: the HTML document gets
  `linkSpace` / `linkContext`, the status bar prints the address space that came back, and
  a `demo.html#receipts` link lands through `PreviewDomAddress('#receipts')` (the
  Markdown document keeps posting the plain envelope, so both forms are on screen).

## 0.1.1

No change to the library itself — this release only tidies what the package ships with.

- The example is split by responsibility: `lib/main.dart` keeps the render pipeline
  (commit, receipt routing, reading-position semantics), while the sample documents,
  toolbar, outline drawer, status bar, syntax sheet and platform fallback moved to
  `lib/src/`.
- The `description` in `pubspec.yaml` was tightened to the length the pub specification
  asks for.

## 0.1.0

First extraction from the preview implementation of an editor app.

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
  depth and byte gates. Dart side exposes `PreviewSyntaxTree` / `PreviewSyntaxNode`.
- The full tree (nested blocks plus inline tokens) is fetched on demand through
  `HyperlensCommands.requestSyntaxAst()`, sharing the same tokens and line numbers as the
  skeleton.
- Syntax issue list (`issues` in the `ast` receipt): the page reports unclosed code
  fences, table rows whose cell count differs from the header, and reference-style links
  with no definition; the Dart side adds `scanHtmlTagIssues()`, a tag-stack scan over the
  source text that finds unclosed and stray end tags the browser's fixed-up `document`
  no longer shows. When both sources are merged the page's entries come first, and a
  duplicate (same kind, same place) is dropped.
- Receipt protocol: render ready, link tapped, position reported, outline reported,
  focus applied, anchor scrolled, unknown message.
- Source-linked outline and syntax tree built from the same parse.
- Web assets (marked, DOMPurify, KaTeX, mhchem, highlight.js, Mermaid) declared by
  the package; the caller stops declaring them.
- Public surface: `HyperlensPage.fromText` is the single render entry (Markdown and
  HTML alike); `HyperlensAssets`,
  `HyperlensBridge`, `HyperlensTheme`, `HyperlensLogger` and `HyperlensAssetLoader`
  (`HyperlensRootBundleAssetLoader` for Flutter) are the rest of it.
- The WebView channel name is injected instead of being hard-coded: the Markdown
  template takes it through a placeholder, `htmlAnchorScript(channelName:)` for the
  HTML side, so the caller can register its own name. Either has to match
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
- Reading positions are one address type (breaking): `PreviewSourceAddress` for a Markdown source
  line, `PreviewDomAddress` for an HTML DOM path such as `body>div#main>p:nth(3)`, plus
  `PreviewViewport` carrying the per-frame viewport lines that drive outline highlighting.
  `PreviewAnchor` (`block` / `offset` / `scrollY`) is gone, pages are only told to scroll
  through `HyperlensCommands` (`mdScrollToLine` / `hyperLensScrollToPath`), and a position
  that cannot be resolved puts the reader back at the top instead of guessing. Saved
  positions still parse: a stored `line` is reused, a pixel-only record falls back to top.
- Documented that `HyperlensTheme` is the sole definition of "how this page looks" for a
  host that has to decide whether to reload: the rendered page is a snapshot (background,
  text colour and overlay layers are baked into the HTML at load time), so a new knob has
  to be added together with `==` / `hashCode`. The case that bit us: ink and light share
  the same `#ffffff` background, so a host comparing only the background skipped the
  reload on "ink → light" and kept the ink monochrome overlay — coloured headings turned
  black (see the `HyperlensTheme` class docs).
