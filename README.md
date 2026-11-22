# Schola for Godot: project site

The showcase site for CSC301 Team 20's Godot port of AMD Schola. It is plain HTML and CSS with no
build step, no JavaScript and no framework, published by GitHub Pages straight from this
`gh-pages` branch.

This branch is an orphan: it shares no history with `main`, so nothing here affects the plugin,
its CI, or the course deliverables.

## Pages

| File | What it covers |
| --- | --- |
| `index.html` | Overview: what Schola is, what we built, the journey at a glance |
| `demos.html` | Each deliverable's demo (D1, D2, D3) and what changed between them |
| `stories.html` | How we planned and tracked the user stories, and where each one stands |
| `architecture.html` | How the plugin is put together: modules, lifecycle, training and inference |
| `engineering.html` | Testing, CI, packaging, dependency pinning and how we review work |
| `team.html` | The team, our AMD partners, and how we worked together |
| `404.html` | Shown by GitHub Pages for unknown URLs |

## Styles

Every page links one stylesheet, `assets/css/site.css`, which imports the modules in order:

| File | Holds |
| --- | --- |
| `tokens.css` | Colours, type scale, spacing. Change the look here first. |
| `base.css` | Reset and plain element styles (no classes) |
| `layout.css` | Header, footer, section bands, grids |
| `components.css` | Reusable blocks: buttons, timeline, tables, diagrams, tags |
| `hero.css` | The animated grid-world on the home page |

Colours follow AMD's palette: black, white and AMD red (`#ED1C24`). Red text on white uses a
darker shade (`--red-ink`) so it stays readable.

## Editing

The header and footer are repeated in each page, since there is no build step to share them.
When you change one, change it in every `.html` file. Each copy is marked with
`<!-- Shared header -->` and `<!-- Shared footer -->`.

To preview, open `index.html` in a browser. To serve it the way Pages does:

```sh
python -m http.server 8000
```

## Publishing

Commit on `gh-pages` and push. GitHub Pages serves the branch root, and the `.nojekyll` file
tells it to serve the files as they are.
