#!/bin/bash
set -e

echo "🔥 Exita Phase 2.5 – hot reload, styles, runtime polish, VS Code"

# ───────── 1. Install new dependencies ─────────
npm install --save-dev chokidar ws
npm install --save-dev @types/ws

# ───────── 2. Enhanced Runtime with computed & effect ─────────
cat > src/runtime/exita-runtime.ts << 'EOF'
// ── Signals ──
let currentEffect: (() => void) | null = null

export function signal<T>(initialValue: T) {
  let value = initialValue
  const subscribers = new Set<() => void>()
  return new Proxy({} as { value: T }, {
    get(_, prop) {
      if (prop === 'value') {
        if (currentEffect) subscribers.add(currentEffect)
        return value
      }
    },
    set(_, prop, newVal) {
      if (prop === 'value') {
        if (value !== newVal) {
          value = newVal
          subscribers.forEach(fn => fn())
        }
        return true
      }
      return false
    }
  })
}

export function effect(fn: () => void) {
  const run = () => {
    currentEffect = run
    fn()
    currentEffect = null
  }
  run()
}

export function computed<T>(fn: () => T) {
  const s = signal<T>(undefined as any)
  effect(() => { (s as any).value = fn() })
  return s
}

// ── JSX Factory ──
export function createElement(
  type: string | Function,
  props: Record<string, any> | null,
  ...children: any[]
): any {
  if (typeof type === 'function') return type({ ...props, children })

  const el = document.createElement(type)
  if (props) {
    for (const [key, val] of Object.entries(props)) {
      if (key.startsWith('on')) {
        const event = key.slice(2).toLowerCase()
        el.addEventListener(event, val)
      } else if (key === 'class' || key === 'className') {
        el.className = val
      } else if (key === 'style' && typeof val === 'object') {
        Object.assign(el.style, val)
      } else if (key === 'ref') {
        if (typeof val === 'function') val(el)
      } else {
        el.setAttribute(key, String(val))
      }
    }
  }

  children.flat().forEach(child => {
    if (child == null || child === false) return
    if (typeof child === 'string' || typeof child === 'number') {
      el.appendChild(document.createTextNode(String(child)))
    } else if (child instanceof Node) {
      el.appendChild(child)
    } else if (typeof child === 'function') {
      const placeholder = document.createTextNode('')
      el.appendChild(placeholder)
      effect(() => {
        const result = child()
        if (result instanceof Node) placeholder.replaceWith(result)
        else placeholder.textContent = String(result)
      })
    }
  })
  return el
}

export function Fragment({ children }: { children?: any[] }) {
  const frag = document.createDocumentFragment()
  (children || []).flat().forEach(child => {
    if (child instanceof Node) frag.appendChild(child)
    else if (typeof child === 'string') frag.appendChild(document.createTextNode(child))
  })
  return frag
}

export function render(component: () => any, container: HTMLElement) {
  container.innerHTML = ''
  container.appendChild(component())
}
EOF

# Regenerate the browser bundle runtime.js in dist/
mkdir -p dist
cat > dist/runtime.js << 'EOF'
// Exita Runtime (auto-generated)
let currentEffect = null
function signal(initialValue) {
  let value = initialValue
  const subscribers = new Set()
  return new Proxy({}, {
    get(_, prop) {
      if (prop === 'value') {
        if (currentEffect) subscribers.add(currentEffect)
        return value
      }
    },
    set(_, prop, newVal) {
      if (prop === 'value') {
        if (value !== newVal) {
          value = newVal
          subscribers.forEach(fn => fn())
        }
        return true
      }
      return false
    }
  })
}
function effect(fn) {
  const run = () => { currentEffect = run; fn(); currentEffect = null }
  run()
}
function computed(fn) {
  const s = signal(undefined)
  effect(() => { s.value = fn() })
  return s
}
function createElement(type, props, ...children) {
  if (typeof type === 'function') return type({ ...props, children })
  const el = document.createElement(type)
  if (props) {
    for (const [key, val] of Object.entries(props)) {
      if (key.startsWith('on')) {
        const event = key.slice(2).toLowerCase()
        el.addEventListener(event, val)
      } else if (key === 'class' || key === 'className') {
        el.className = val
      } else if (key === 'style' && typeof val === 'object') {
        Object.assign(el.style, val)
      } else {
        el.setAttribute(key, String(val))
      }
    }
  }
  children.flat().forEach(child => {
    if (child == null || child === false) return
    if (typeof child === 'string' || typeof child === 'number') {
      el.appendChild(document.createTextNode(String(child)))
    } else if (child instanceof Node) {
      el.appendChild(child)
    } else if (typeof child === 'function') {
      const placeholder = document.createTextNode('')
      el.appendChild(placeholder)
      effect(() => {
        const result = child()
        if (result instanceof Node) placeholder.replaceWith(result)
        else placeholder.textContent = String(result)
      })
    }
  })
  return el
}
function Fragment({ children }) {
  const frag = document.createDocumentFragment()
  (children || []).flat().forEach(child => {
    if (child instanceof Node) frag.appendChild(child)
    else frag.appendChild(document.createTextNode(String(child)))
  })
  return frag
}
function render(component, container) {
  container.innerHTML = ''
  container.appendChild(component())
}
export { signal, effect, computed, createElement, Fragment, render }
EOF

# ───────── 3. Style Extraction (real transformer) ─────────
cat > src/transforms/style-extractor.ts << 'EOF'
import * as t from '@babel/types';
import * as fs from 'fs';
import * as path from 'path';

export function extractStylesFromCode(code: string, componentName: string, outDir: string): string {
  // Simple regex-based extraction for now (we already have the transpiled code)
  // We'll scan the original source for <style>`...`</style>
  const styleRegex = /<style>\s*`([^`]*)`\s*<\/style>/g;
  let cssContent = '';
  let match;
  while ((match = styleRegex.exec(code)) !== null) {
    cssContent += match[1];
  }

  if (!cssContent) return '';

  // Scope with a unique class
  const scopedClass = `exita-${componentName.toLowerCase()}-${Math.random().toString(36).substr(2, 5)}`;
  const scopedCSS = `.${scopedClass} {\n${cssContent}\n}`;

  const cssDir = path.join(outDir, 'styles');
  fs.mkdirSync(cssDir, { recursive: true });
  fs.writeFileSync(path.join(cssDir, `${componentName}.exj.css`), scopedCSS);
  console.log(`  Styles extracted: ${componentName}.exj.css`);
  return scopedClass;
}
EOF

# ───────── 4. Update compiler to use style extraction and hot reload ─────────
cat > src/generator/js-generator.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import * as ts from 'typescript';
import { parseExitaFile } from '../parser/exita-parser';
import { signalTransformer } from '../transforms/signal-transformer';
import { extractStylesFromCode } from '../transforms/style-extractor';

export function compileToJS(filePath: string, outDir: string): string {
  const rawCode = fs.readFileSync(filePath, 'utf-8');
  const moduleInfo = parseExitaFile(filePath);

  // Style extraction from original source (before transformation)
  const componentName = moduleInfo.name;
  const scopedClass = extractStylesFromCode(rawCode, componentName, outDir);

  // Remove Add.Module lines
  let cleanCode = rawCode.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');

  // Insert the scoped class into the root element of the component if available (advanced)
  // For now, just let the user manually add class={scopedClass} later. We'll inject a prop.

  const source = cleanCode;

  const result = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2020,
      jsx: ts.JsxEmit.React,
      jsxFactory: '__exita_createElement',
      jsxFragmentFactory: 'Fragment',
      esModuleInterop: true,
      allowSyntheticDefaultImports: true,
      strict: false,
    },
    transformers: { before: [signalTransformer] }
  });

  let output = result.outputText;

  // Add runtime imports
  const needsSignal = output.includes('__exita_signal');
  const needsCreateElement = output.includes('__exita_createElement');
  const imports: string[] = [];
  if (needsSignal) imports.push('signal as __exita_signal');
  if (needsCreateElement) imports.push('createElement as __exita_createElement');
  if (output.includes('Fragment')) imports.push('Fragment');
  if (imports.length) {
    output = `import { ${imports.join(', ')} } from './runtime.js';\n${output}`;
  }

  output = output.replace(/^import\s+['"]\.\/runtime\.js['"];?\n/gm, '');

  const outFile = path.join(outDir, path.basename(filePath, '.exj') + '.exj.js');
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, output, 'utf-8');
  console.log(`Generated JS: ${outFile}`);
  return outFile;
}
EOF

# ───────── 5. Hot‑reloading dev server (websocket) ─────────
cat > src/cli.ts << 'EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';
import * as WebSocket from 'ws';

const program = new Command()
  .name('exita')
  .description('Exita compiler')
  .version('0.2.5');

program
  .command('build')
  .option('-e, --entry <pattern>', 'File pattern', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .action(opts => build({ entry: opts.entry, outDir: opts.outDir }));

program
  .command('dev')
  .option('-p, --port <number>', 'Port', '3000')
  .action(opts => {
    const port = parseInt(opts.port);
    build({ entry: 'examples/**/*.exj', outDir: 'dist', generateHeaders: false, generateJS: true });

    const server = createServer((req, res) => {
      const url = req.url || '/';
      if (url === '/' || url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<!DOCTYPE html>
<html><head><title>Exita App</title></head><body>
  <div id="app"></div>
  <script type="module">
    import { render } from './runtime.js';
    import App from './App.exj.js';
    render(() => App(), document.getElementById('app'));
    // Hot reload client
    const ws = new WebSocket('ws://localhost:${port}');
    ws.onmessage = (msg) => {
      if (msg.data === 'reload') location.reload();
    };
  </script>
</body></html>`);
      } else if (url.endsWith('.js') || url.endsWith('.css')) {
        const filePath = path.join('dist', url);
        if (existsSync(filePath)) {
          const ext = path.extname(url);
          res.writeHead(200, { 'Content-Type': ext === '.css' ? 'text/css' : 'application/javascript' });
          res.end(readFileSync(filePath));
        } else { res.writeHead(404); res.end('Not found'); }
      } else {
        res.writeHead(404); res.end('Not found');
      }
    });

    // WebSocket for livereload
    const wss = new WebSocket.Server({ server });
    const clients = new Set<WebSocket>();
    wss.on('connection', ws => {
      clients.add(ws);
      ws.on('close', () => clients.delete(ws));
    });
    function broadcast(msg: string) { clients.forEach(c => c.send(msg)); }

    // Watch files and rebuild
    const watcher = chokidar.watch('examples/**/*.exj', { persistent: true });
    watcher.on('change', (filePath) => {
      console.log(`\n🔄 File changed: ${filePath}`);
      build({ entry: 'examples/**/*.exj', outDir: 'dist', generateHeaders: false, generateJS: true });
      broadcast('reload');
    });

    server.listen(port, () => {
      console.log(`🚀 Exita dev server with hot reload: http://localhost:${port}`);
    });
  });

program.parse(process.argv);
EOF

# ───────── 6. VS Code Extension (minimal) ─────────
mkdir -p vscode-exita
cat > vscode-exita/package.json << 'EOF'
{
  "name": "exita-vscode",
  "displayName": "Exita",
  "version": "0.1.0",
  "engines": { "vscode": "^1.80.0" },
  "categories": ["Programming Languages"],
  "contributes": {
    "languages": [
      { "id": "exj", "extensions": [".exj"], "aliases": ["Exita Source"] },
      { "id": "hxj", "extensions": [".hxj"], "aliases": ["Exita Header"] }
    ],
    "grammars": [
      {
        "language": "exj",
        "scopeName": "source.exj",
        "path": "./syntaxes/exj.tmLanguage.json"
      },
      {
        "language": "hxj",
        "scopeName": "source.hxj",
        "path": "./syntaxes/hxj.tmLanguage.json"
      }
    ]
  }
}
EOF

mkdir -p vscode-exita/syntaxes
cat > vscode-exita/syntaxes/exj.tmLanguage.json << 'EOF'
{
  "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  "name": "Exita Source",
  "scopeName": "source.exj",
  "patterns": [
    { "include": "source.tsx" }
  ]
}
EOF

cat > vscode-exita/syntaxes/hxj.tmLanguage.json << 'EOF'
{
  "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  "name": "Exita Header",
  "scopeName": "source.hxj",
  "patterns": [
    { "include": "source.ts" }
  ]
}
EOF

echo ""
echo "✅ Phase 2.5 complete!"
echo ""
echo "What's new:"
echo "  1. Hot reload:      node dist/cli.js dev  (auto reloads on save)"
echo "  2. Style extraction: .css files in dist/styles/"
echo "  3. VS Code extension: copy vscode-exita folder to ~/.vscode/extensions/exita"
echo "  5. Runtime polish:   computed(), effect()"
echo ""
echo "To apply VS Code extension:"
echo "  cp -r vscode-exita ~/.vscode/extensions/exita"
echo "  (or on Windows: %USERPROFILE%\\.vscode\\extensions\\exita)"
