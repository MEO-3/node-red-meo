# Editor UI Customization Guide (node-red-meo fork)

This document explains how the Node-RED **editor UI** is structured and how to modify,
restyle, and extend it in this fork. It is written for the MEO 3 project, where we
maintain a fork (`MEO-3/node-red-meo`) instead of vendoring stock Node-RED.

> The editor UI lives entirely in the `@node-red/editor-client` package:
> `packages/node_modules/@node-red/editor-client/`. Everything below is relative to
> the repository root unless stated otherwise.

---

## 1. The big picture: source → build → served

The files you **edit** are not the files that get **served**. There are three stages:

```
  src/ (+ templates/)        scripts/build           public/            editor-api
  ───────────────────   ──▶  ───────────────  ──▶   ──────────  ──serves──▶  browser
  what you edit              npm run build           generated
```

| Stage      | Where                                                                                 | Notes                                                              |
| ---------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| **Source** | `editor-client/src/{js,sass,images,vendor}` and `editor-client/templates/index.mst`   | The only files you should hand-edit.                              |
| **Build**  | `npm run build` at the repo root (runs `scripts/build/`)                              | Concatenates + compiles + copies into `public/`.                 |
| **Served** | `editor-client/public/`                                                                | **Generated. Git-ignored. Never edit by hand — it is overwritten.** |

The build pipeline (`scripts/build/index.js`) runs, in order:
`clean → jsonlint → concat → copy → sass → (minify, unless --dev)`.

Output destinations (from `scripts/build/config.js`):

- JS bundle  → `editor-client/public/red/red.js`
- CSS bundle → `editor-client/public/red/style.min.css`
- templates, images, vendor libs → copied under `editor-client/public/`

The editor is served by `@node-red/editor-api`
(`packages/node_modules/@node-red/editor-api/lib/editor/ui.js`):

- It renders `editor-client/templates/index.mst` with **Mustache**
  (`editorTemplatePath = .../templates/index.mst`, hardcoded — see §6).
- It serves `editor-client/public/` as static assets.

**The editor is a single-page app.** `index.mst` is essentially
`<div id="red-ui-editor"></div>` plus `red.js` + `main.js`. There is **no page router** —
what feel like "pages" are tabs, panels, and trays rendered inside that one app.

---

## 2. Build & run commands

Run these from the **repository root** (`node-red-meo/`):

```bash
npm install            # once, installs build + runtime deps
npm run build          # full production build (minified) -> public/
npm run build-dev      # faster build, no minification (use while developing)
npm run dev            # watch mode: rebuilds public/ on save (chokidar)
npm run lint           # eslint over editor-client/src/js
npm start              # run Node-RED (node packages/node_modules/node-red/red.js)
```

Typical inner loop:

1. `npm run dev` in one terminal (keeps `public/` in sync as you edit `src/`).
2. Edit files under `editor-client/src/`.
3. Reload the browser (the server serves the freshly rebuilt `public/`).

`public/` is git-ignored, so a fresh clone has **no** built UI until you run a build.

---

## 3. Modifying existing UI behavior (JavaScript)

The editor client code is plain, jQuery-based JavaScript under `editor-client/src/js/`:

- `src/js/red.js`, `src/js/main.js` — bootstrap and top-level wiring.
- `src/js/ui/*.js` — the UI modules: `view.js` (flow canvas), `palette.js`,
  `sidebar.js`, `editor.js`, `tray.js`, `tab-info.js`, `deploy.js`, `keyboard.js`, etc.
- `src/js/ui/common/*.js` — reusable widgets (`editableList`, `typedInput`, `menu`,
  `popover`, `tabs`, `panels`, …).

These are exposed on the global `RED` object (e.g. `RED.view`, `RED.sidebar`,
`RED.notify`, `RED.actions`).

### Adding a NEW JavaScript file

The bundle is an **explicit, ordered list** — not a glob of the whole folder. If you add
a new file under `src/js/`, you must register it in
`scripts/build/config.js` → `concatEditor.src`, in the right position. A new file that is
not listed there is silently left out of `red.js`.

```js
// scripts/build/config.js  (excerpt of concatEditor.src)
"ui/editor.js",
"ui/meo/myFeature.js",   // <-- add your new file here
```

Then `npm run build-dev`.

---

## 4. Restyling (SCSS / CSS)

Styles live in `editor-client/src/sass/`. The entry point compiled by the build is
`src/sass/style.scss`, which `@import`s the rest (`base.scss`, `colors.scss`,
`header.scss`, `palette.scss`, `sidebar.scss`, …). Output is
`public/red/style.min.css`.

- Change look-and-feel by editing the relevant `*.scss` partial.
- Shared variables/spacing live in `variables.scss` and `colors.scss`
  (`dark-colors.scss` / `dark-theme.scss` for the dark theme).
- Add a new partial by creating `src/sass/_yourpartial.scss` and `@import`ing it from
  `style.scss` (or another already-imported partial).

Rebuild with `npm run build-dev` (or let `npm run dev` watch).

---

## 5. The HTML shell (`index.mst`)

`editor-client/templates/index.mst` is the Mustache template for the page shell. It is
copied to `public/` and rendered per-request by `editor-api`. It pulls in
`red/style.min.css`, vendor libs, `red.js`, and `main.js`.

It also exposes theme-driven injection points that are filled from server settings
(see §7) — you usually do **not** need to edit `index.mst` directly:

```mustache
<title>{{ page.title }}</title>
<link rel="icon" href="{{{ page.favicon }}}">
{{#page.css}}    <link rel="stylesheet" href="{{.}}"> {{/page.css}}
{{#page.scripts}}<script src="{{.}}"></script>       {{/page.scripts}}
```

Edit `index.mst` only when you need to change the actual HTML skeleton. Prefer §7 for
CSS/JS injection and branding.

---

## 6. Creating a new "page" or panel

Because the editor is a single-page app, choose the lightest option that fits:

1. **New sidebar tab/panel — preferred.** Use `RED.sidebar.addTab({...})` to add a
   panel beside Info/Debug. This is the intended extension point and needs no core
   surgery. Ship it as an editor **plugin** or from a node's edit dialog.

2. **A separate standalone page.** Register a custom admin route from a plugin or node
   (`RED.httpAdmin.get('/meo-dashboard', ...)`) that serves your own HTML/app,
   independent of the editor SPA. Best choice for a dedicated, child-facing MEO screen.

3. **A new full view inside the SPA.** Deep work in `src/js/ui/view*.js`; high
   maintenance. Only do this if the feature must live on the flow canvas itself.

Note: `editor-api/lib/editor/ui.js` **hardcodes** `templates/index.mst` as the single
editor template (`editorTemplatePath`). Swapping in an alternative top-level template
(e.g. a `meo.mst`) means editing `ui.js` too — a deeper fork change. Prefer options 1–2.

---

## 7. Customization WITHOUT forking the editor (theme settings)

Even though we maintain a fork, prefer doing branding and light customization through
Node-RED's **theme settings** rather than editing `editor-client/src`. Node-RED's
`editor-api/lib/editor/theme.js` reads `settings.editorTheme` and feeds the
`index.mst` injection points, so you can supply custom CSS/JS, title, favicon, and
header image from configuration:

```js
// settings.js (MEO 3 service config: config/node-red/settings.js)
editorTheme: {
    page: {
        title: "MEO 3",
        favicon: "/absolute/path/to/favicon.ico",
        css: "/absolute/path/to/meo.css",     // injected via {{#page.css}}
        scripts: "/absolute/path/to/meo.js"   // injected via {{#page.scripts}}
    },
    header: { title: "MEO 3", image: "/absolute/path/to/logo.png" }
}
```

**Rule of thumb:** keep MEO branding and CSS/JS injection in `settings.js`, ship new
functionality as plugins / sidebar tabs, and reserve edits to `editor-client/src` for
things that are genuinely impossible through the theme/plugin API. This keeps merges
from upstream Node-RED manageable.

---

## 8. Releasing / packaging (important)

When this fork is packaged for a gateway:

- `public/` is **git-ignored and must be built before packaging** — a clean checkout
  has no built UI. Run `npm run build` (production) before producing a release.
- Building requires **dev dependencies** (`sass`, `fast-glob`, …). Gateways that only
  run `npm ci --omit=dev` will **not** be able to build the editor, so the built
  `public/` has to be produced on the build host and shipped with the package.

In short: **always `npm run build` after changing any `editor-client/src` file, and
before packaging a release.**

---

## Quick reference

| I want to…                       | Edit                                            | Then run            |
| -------------------------------- | ----------------------------------------------- | ------------------- |
| Change editor behavior           | `editor-client/src/js/ui/*.js`                  | `npm run build-dev` |
| Add a new JS file                | the file + `scripts/build/config.js` (`concatEditor`) | `npm run build-dev` |
| Restyle                          | `editor-client/src/sass/*.scss`                 | `npm run build-dev` |
| Change the HTML shell            | `editor-client/templates/index.mst`             | `npm run build-dev` |
| Add a panel                      | a plugin using `RED.sidebar.addTab(...)`        | `npm run build-dev` |
| Brand / inject CSS-JS (no fork)  | `settings.js` → `editorTheme`                   | restart Node-RED    |
| Iterate continuously             | —                                               | `npm run dev` (watch) |

**Golden rule:** never edit `editor-client/public/` — it is generated by the build and
overwritten every time.
