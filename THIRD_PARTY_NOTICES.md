# Third-party notices

English | [简体中文](THIRD_PARTY_NOTICES.cn.md)

hyperlens bundles a small set of third-party browser-side resources in
[`assets/web/`](assets/web/). They are what the preview WebView actually executes: the
Markdown parser, the sanitizer, the diagram and math renderers, plus their stylesheets.
Their license texts are reproduced **verbatim** in [`assets/licenses/`](assets/licenses/),
one file per component; the table below is the index between "what ships in this package"
and "which text applies".

Version numbers are read from the shipped files themselves (a banner string or a
`version:"…"` field inside the bundle), not from a manifest — a minified asset carries no
package metadata.

| Component | Version | License | Shipped as | License text |
|---|---|---|---|---|
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.2.6 | Apache-2.0 (dual-licensed with MPL-2.0; this package relies on Apache-2.0) | `assets/web/purify.min.js` | [`assets/licenses/dompurify.txt`](assets/licenses/dompurify.txt) |
| [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) | — (upstream CSS carries no version) | MIT | `assets/web/md-light.css`, `md-dark.css`, `md-ink.css`, `md-ink-dark.css` | [`assets/licenses/github-markdown-css.txt`](assets/licenses/github-markdown-css.txt) |
| [highlight.js](https://github.com/highlightjs/highlight.js) | 11.9.0 | BSD-3-Clause | `assets/web/highlight.min.js`, `highlight-dart.min.js`, `hljs/*.min.js` (41 per-language grammars), `hljs-light.css`, `hljs-dark.css`, `hljs-ink.css`, `hljs-ink-dark.css` | [`assets/licenses/highlight.js.txt`](assets/licenses/highlight.js.txt) |
| [KaTeX](https://github.com/KaTeX/KaTeX) | 0.19.1 | MIT | `assets/web/katex.min.js`, `katex.min.css`, `mhchem.min.js` | [`assets/licenses/katex.txt`](assets/licenses/katex.txt) |
| [marked](https://github.com/markedjs/marked) | 14.1.3 | MIT | `assets/web/marked.min.js` | [`assets/licenses/marked.txt`](assets/licenses/marked.txt) |
| [Mermaid](https://github.com/mermaid-js/mermaid) | 11.17.2 | MIT (the artifact also carries 53 dependencies under MIT / ISC / BSD-3-Clause / MPL-2.0-or-Apache-2.0) | `assets/web/mermaid.min.js` | [`assets/licenses/mermaid.txt`](assets/licenses/mermaid.txt) (mermaid + KaTeX) · [`assets/licenses/mermaid-bundle.txt`](assets/licenses/mermaid-bundle.txt) (all 55 bundled packages) |

## Notes on how these map to the shipped files

- **`md-*.css` are modified copies of github-markdown-css.** Only color variables were
  changed, plus one structural edit: the `prefers-color-scheme` branch is removed so the
  light/dark skin is chosen by the host app instead of by the system. MIT allows this; the
  upstream copyright notice is retained in `assets/licenses/github-markdown-css.txt`. The
  `-ink*` skins are the same file with a monochrome palette.
- **`mhchem.min.js` is a contrib build shipped inside the KaTeX package** (same version,
  same MIT license, `\ce{}` / `\pu{}` support), so `assets/licenses/katex.txt` covers it
  rather than a separate notice.
- **`mermaid.min.js` is a self-built bundle** — mermaid + KaTeX + mhchem, *plus mermaid's own
  53 dependencies* (the 30-package d3 family, the cytoscape family, dagre-d3-es, dompurify,
  marked, lodash-es, …) — 55 packages in one IIFE. The two texts split the work:
  - `assets/licenses/mermaid.txt` carries the MIT text of the two **primary works** (mermaid and
    KaTeX, incl. contrib/mhchem);
  - `assets/licenses/mermaid-bundle.txt` carries the **complete list**: every bundled package
    with its copyright line, plus the verbatim text of all four licenses.
  The same list and texts are also inlined at the end of the artifact, so the notices travel
  with every copy of the file.
- **A second dompurify (3.4.18) rides inside the artifact** — that is the copy mermaid brings
  along. It is not the same code as the separately shipped `purify.min.js` (3.2.6); both are
  Apache-2.0 and share `assets/licenses/dompurify.txt`.
- **`assets/licenses/marked.txt` is upstream's LICENSE verbatim**, which is two texts: the
  MIT license for marked itself and the BSD-style notice for the Markdown syntax it derives
  from (John Gruber, 2004).
- **`assets/web/markdown_view.html` is first-party** — the page template this package
  generates and injects into. No third-party notice applies.

## Dart dependencies

Packages pulled from pub are **not** listed here, and their license files are not copied
into this directory. Flutter collects every dependency's `LICENSE` into `NOTICES` at build
time and registers it with `LicenseRegistry`, so a host app's own license page shows them
without hyperlens duplicating the text. This file only covers the non-Dart, non-registered
resources above.

## hyperlens itself

MIT — see [LICENSE](LICENSE).
