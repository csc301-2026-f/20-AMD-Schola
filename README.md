# Schola for Godot: project site

The project site for CSC301 Team 20's Godot port of AMD Schola. It's plain HTML and CSS with no
build step, no JavaScript and no framework, published by GitHub Pages straight from this
`gh-pages` branch.

This branch is an orphan: it shares no history with `main`, so nothing here affects the plugin,
its CI, or the course deliverables.

## Pages

| File | What it covers |
| --- | --- |
| `index.html` | What we're building, the grid-world task, current status and a timeline |
| `demos.html` | The D1, D2 and D3 demos, what was a stand-in at each stage, and newer examples |
| `stories.html` | How we planned the user stories, where each one stands, and what AMD changed |
| `how-it-works.html` | Architecture, training and inference paths, testing, CI, dependencies, releases |
| `team.html` | Who did what, our AMD partner, how we worked, and partner meeting outcomes |
| `404.html` | Shown by GitHub Pages for unknown URLs |

## Styles

Every page links one stylesheet, `assets/css/site.css`, which imports the modules in order:

| File | Holds |
| --- | --- |
| `tokens.css` | Colours, type and sizes. Change the look here first. |
| `base.css` | Reset and plain element styles (no classes) |
| `layout.css` | Header, page frame, reading column, footer |
| `components.css` | Home intro, AMD partner credit, screenshots, timeline, code and diagrams |
| `gridworld.css` | The animated grid world on the home page |

The look follows AMD's palette of black, white and AMD red (`#ED1C24`). Red is used for link
underlines, the current page in the navigation, and the agent in the grid world. Text is set in
Barlow, with JetBrains Mono for code.

## AMD logo

`assets/img/amd-schola-lockup.png` is AMD's Schola lockup from `Docs/Sphinx/_static` on `main`,
and `assets/img/amd-logo.png` is the AMD wordmark cropped from it. Both files are black; on black
backgrounds the CSS flips them to white (`.on-black .partner img`). The logo appears as a partner
credit in the home page intro and every footer, and as the lockup on the team page. It's AMD's
trademark, so check with our AMD contact before publishing.

## Editing

The header and footer are repeated in each page, since there's no build step to share them.
When you change one, change it in every `.html` file. Each copy is marked with a
`Shared header` or `Shared footer` comment.

To preview the site the way Pages serves it:

```sh
python -m http.server 8000
```

## Publishing

Commit on `gh-pages` and push. GitHub Pages serves the branch root, and the `.nojekyll` file
tells it to serve the files as they are.
