## Exita

Exita.js is a programming language forked off TypeScript to provide a better developer experience. Exita.js was bulit with AI assistance for coding although i did the architecture. You can contribute.

## Why Exita

Exita.js is unique for having no configuration files, hook imports/exports, signals by default, async, bulit-in everything, and boilerplate that distracts from working. It also infers types from your code too!

## Installation

Exita requires Node.js 18 or later and Python 3.

```
git clone https://github.com/xkitzok/exita.js
cd exita.js
python x.py build --entry 'src/**/*.exj' --outDir dist
```

After bootstrapping, the `exita` command becomes available globally:

```
exita help
```

## Quick Start

Create a new project:

```
exita init
```

This creates `exitapkg.json`, `src/app.exj`, and a lock file. To run it:

```
exita run
```

## Commands

| Command | Description |
|---|---|
| `exita init` | Create a new Exita project |
| `exita run` | Start dev server with auto-rebuild |
| `exita build` | Compile `.exj` files |
| `exita add <pkg>` | Add a dependency inside exitapkg.json |
| `exita update` | Update Exita to the latest version |
| `exita clean` | Remove build artifacts |
| `exita bundle` | Bundle for production |
| `exita check-breaking` | Check for breaking API changes |

## File Extensions

| Extension | Purpose |
|---|---|
| `.exj` | Exita source file (components, logic) |
| `.hxj` | Exita header file (auto-generated contract) |
| `.exj.css` | Scoped styles (auto-extracted) |