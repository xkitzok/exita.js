#!/bin/bash
set -e

echo "🚀 Exita Phase 3 – Production Features"

# ───────── 1. Install new dependencies ─────────
npm install --save-dev chokidar @types/chokidar esbuild semver @types/semver

# ───────── 2. Enhanced Runtime with async components ─────────
cat > src/runtime/exita-runtime.ts << 'EOF'
// ── Signals ──
let currentEffect: (() => void) | null = null;

export function signal<T>(initialValue: T) {
  let value = initialValue;
  const subscribers = new Set<() => void>();
  return new Proxy({} as { value: T }, {
    get(_, prop) {
      if (prop === 'value') {
        if (currentEffect) subscribers.add(currentEffect);
        return value;
      }
    },
    set(_, prop, newVal) {
      if (prop === 'value') {
        if (value !== newVal) {
          value = newVal;
          subscribers.forEach(fn => fn());
        }
        return true;
      }
      return false;
    }
  });
}

export function effect(fn: () => void) {
  const run = () => { currentEffect = run; fn(); currentEffect = null; };
  run();
}

export function computed<T>(fn: () => T) {
  const s = signal<T>(undefined as any);
  effect(() => { (s as any).value = fn(); });
  return s;
}

// ── Async component support ──
type VNode = any; // simplified
const pending = new WeakSet<Promise<any>>();

export function createElement(
  type: string | Function,
  props: Record<string, any> | null,
  ...children: any[]
): any {
  if (typeof type === 'function') {
    const result = type({ ...props, children });
    // If the component returns a Promise (async), handle it
    if (result instanceof Promise) {
      return handleAsyncComponent(result, type.name || 'Anonymous');
    }
    return result;
  }

  const el = document.createElement(type);
  if (props) {
    for (const [key, val] of Object.entries(props)) {
      if (key.startsWith('on')) {
        const event = key.slice(2).toLowerCase();
        el.addEventListener(event, val);
      } else if (key === 'class' || key === 'className') {
        el.className = val;
      } else if (key === 'style' && typeof val === 'object') {
        Object.assign(el.style, val);
      } else {
        el.setAttribute(key, String(val));
      }
    }
  }

  children.flat().forEach(child => {
    if (child == null || child === false) return;
    if (typeof child === 'string' || typeof child === 'number') {
      el.appendChild(document.createTextNode(String(child)));
    } else if (child instanceof Node) {
      el.appendChild(child);
    } else if (typeof child === 'function') {
      const placeholder = document.createTextNode('');
      el.appendChild(placeholder);
      effect(() => {
        const result = child();
        if (result instanceof Node) placeholder.replaceWith(result);
        else placeholder.textContent = String(result);
      });
    }
  });
  return el;
}

function handleAsyncComponent(promise: Promise<any>, name: string) {
  // Return a placeholder that resolves later
  const placeholder = document.createElement('div');
  placeholder.setAttribute('data-async', name);
  placeholder.textContent = `Loading ${name}...`;
  promise.then(resolved => {
    const parent = placeholder.parentNode;
    if (parent) {
      parent.replaceChild(resolved, placeholder);
    }
  });
  return placeholder;
}

export function Fragment({ children }: { children?: any[] }) {
  const frag = document.createDocumentFragment();
  (children || []).flat().forEach(child => {
    if (child instanceof Node) frag.appendChild(child);
    else if (typeof child === 'string') frag.appendChild(document.createTextNode(child));
  });
  return frag;
}

export function render(component: () => any, container: HTMLElement) {
  container.innerHTML = '';
  const vnode = component();
  if (vnode instanceof Node) {
    container.appendChild(vnode);
  }
}
EOF

# Regenerate browser runtime
cat > dist/runtime.js << 'EOF'
// Exita Runtime (Phase 3)
let currentEffect = null;
function signal(initialValue) {
  let value = initialValue;
  const subscribers = new Set();
  return new Proxy({}, {
    get(_, prop) {
      if (prop === 'value') {
        if (currentEffect) subscribers.add(currentEffect);
        return value;
      }
    },
    set(_, prop, newVal) {
      if (prop === 'value') {
        if (value !== newVal) {
          value = newVal;
          subscribers.forEach(fn => fn());
        }
        return true;
      }
      return false;
    }
  });
}
function effect(fn) {
  const run = () => { currentEffect = run; fn(); currentEffect = null; };
  run();
}
function computed(fn) {
  const s = signal(undefined);
  effect(() => { s.value = fn(); });
  return s;
}
function createElement(type, props, ...children) {
  if (typeof type === 'function') {
    const result = type({ ...props, children });
    if (result instanceof Promise) {
      const placeholder = document.createElement('div');
      placeholder.textContent = 'Loading...';
      result.then(res => {
        const parent = placeholder.parentNode;
        if (parent) parent.replaceChild(res, placeholder);
      });
      return placeholder;
    }
    return result;
  }
  const el = document.createElement(type);
  if (props) {
    for (const [key, val] of Object.entries(props)) {
      if (key.startsWith('on')) {
        el.addEventListener(key.slice(2).toLowerCase(), val);
      } else if (key === 'class' || key === 'className') {
        el.className = val;
      } else if (key === 'style' && typeof val === 'object') {
        Object.assign(el.style, val);
      } else {
        el.setAttribute(key, String(val));
      }
    }
  }
  children.flat().forEach(child => {
    if (child == null || child === false) return;
    if (typeof child === 'string' || typeof child === 'number') {
      el.appendChild(document.createTextNode(String(child)));
    } else if (child instanceof Node) {
      el.appendChild(child);
    }
  });
  return el;
}
function Fragment({ children }) {
  const frag = document.createDocumentFragment();
  (children || []).flat().forEach(child => {
    if (child instanceof Node) frag.appendChild(child);
    else frag.appendChild(document.createTextNode(String(child)));
  });
  return frag;
}
function render(component, container) {
  container.innerHTML = '';
  container.appendChild(component());
}
export { signal, effect, computed, createElement, Fragment, render };
EOF

# ───────── 3. .d.ts Generator ─────────
cat > src/generator/dts-generator.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { parseExitaFile } from '../parser/exita-parser';

export function generateDts(filePath: string, outDir: string): string {
  const moduleInfo = parseExitaFile(filePath);
  const dtsPath = path.join(outDir, path.basename(filePath, '.exj') + '.d.ts');
  
  let content = `// Auto-generated type definitions for Exita module: ${moduleInfo.name}\n\n`;
  
  moduleInfo.exports.forEach(exp => {
    if (exp.kind === 'function') {
      content += `export declare function ${exp.name}(`;
      if (exp.params && exp.params.length > 0) {
        content += exp.params.map(p => `${p.name}${p.typeAnnotation ? ': ' + p.typeAnnotation : ''}`).join(', ');
      }
      content += `): ${exp.returnType || 'any'};\n\n`;
    } else if (exp.kind === 'variable') {
      content += `export declare const ${exp.name}: ${exp.typeAnnotation || 'any'};\n\n`;
    }
  });
  
  fs.mkdirSync(path.dirname(dtsPath), { recursive: true });
  fs.writeFileSync(dtsPath, content, 'utf-8');
  console.log(`Generated .d.ts: ${dtsPath}`);
  return dtsPath;
}
EOF

# ───────── 4. Breaking Change Detector ─────────
cat > src/utils/breaking-changes.ts << 'EOF'
import * as fs from 'fs';
import * as semver from 'semver';

export function checkBreaking(headerFile: string, oldVersion: string) {
  if (!fs.existsSync(headerFile)) {
    console.error(`Header file ${headerFile} not found.`);
    return;
  }
  
  // Simulate: read current header and compare with a git tag or a stored snapshot.
  // For simplicity, we'll assume a .hxj.bak file exists for the old version.
  const oldHeader = headerFile + '.bak';
  if (!fs.existsSync(oldHeader)) {
    console.error(`No backup found for version ${oldVersion}. Create ${oldHeader} first.`);
    return;
  }
  
  const current = fs.readFileSync(headerFile, 'utf-8');
  const old = fs.readFileSync(oldHeader, 'utf-8');
  
  // Extract export names
  const extractExports = (content: string) => {
    const re = /export\s+(?:declare\s+)?(function|const|interface)\s+(\w+)/g;
    const names: string[] = [];
    let m;
    while ((m = re.exec(content))) names.push(m[2]);
    return names;
  };
  
  const currentExports = extractExports(current);
  const oldExports = extractExports(old);
  
  const removed = oldExports.filter(e => !currentExports.includes(e));
  const added = currentExports.filter(e => !oldExports.includes(e));
  
  console.log(`\n🔍 Breaking change check: ${headerFile} vs ${oldVersion}`);
  if (removed.length) {
    console.log(`❌ Removed exports: ${removed.join(', ')}`);
  }
  if (added.length) {
    console.log(`✅ Added exports: ${added.join(', ')}`);
  }
  if (!removed.length && !added.length) {
    console.log('✔ No breaking changes detected.');
  }
}
EOF

# ───────── 5. Production Bundler (esbuild) ─────────
cat > src/bundler.ts << 'EOF'
import * as esbuild from 'esbuild';
import * as fs from 'fs';
import * as path from 'path';
import { globSync } from 'glob';

export async function bundleApp(entry: string, outFile: string) {
  // We need to compile all .exj to .js first
  const { build } = require('./index');
  build({ entry: 'examples/**/*.exj', outDir: 'dist', generateHeaders: false, generateJS: true });
  
  // Then bundle the main entry JS file
  const result = await esbuild.build({
    entryPoints: [path.join('dist', path.basename(entry, '.exj') + '.exj.js')],
    bundle: true,
    minify: true,
    outfile: outFile,
    format: 'esm',
    external: ['./runtime.js'],
    plugins: [],
  });
  console.log(`📦 Bundled to: ${outFile}`);
}
EOF

# ───────── 6. Updated CLI with all new commands ─────────
cat > src/cli.ts << 'EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { bundleApp } from './bundler';
import { checkBreaking } from './utils/breaking-changes';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';

const program = new Command()
  .name('exita')
  .description('Exita compiler – Phase 3')
  .version('0.3.0');

// Build command with watch mode
program
  .command('build')
  .option('-e, --entry <pattern>', 'File pattern', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .option('--watch', 'Watch and rebuild incrementally')
  .action(opts => {
    const runBuild = () => build({ entry: opts.entry, outDir: opts.outDir, generateHeaders: true, generateJS: true, generateDts: true });
    runBuild();
    if (opts.watch) {
      const watcher = chokidar.watch(opts.entry, { persistent: true });
      console.log(`👀 Watching ${opts.entry}...`);
      watcher.on('change', (file) => {
        console.log(`\n🔄 Recompiling ${file}...`);
        build({ entry: opts.entry, outDir: opts.outDir, generateHeaders: true, generateJS: true, generateDts: true });
      });
    }
  });

// Dev server
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
    server.listen(port, () => console.log(`🚀 Exita dev server: http://localhost:${port}`));
  });

// Breaking change detector
program
  .command('check-breaking <header> <version>')
  .description('Check for breaking changes against an old version')
  .action((header, version) => checkBreaking(header, version));

// Production bundle
program
  .command('bundle <entry>')
  .option('-o, --outFile <file>', 'Output bundle file', 'dist/bundle.js')
  .description('Bundle app for production')
  .action((entry, opts) => bundleApp(entry, opts.outFile));

program.parse(process.argv);
EOF

# ───────── 7. Update compiler index to support .d.ts generation ─────────
cat > src/index.ts << 'EOF'
import { parseExitaFile } from './parser/exita-parser';
import { generateHeader } from './generator/hxj-generator';
import { generateDts } from './generator/dts-generator';
import { compileToJS } from './generator/js-generator';
import { globSync } from 'glob';

export interface BuildOptions {
  entry: string;
  outDir: string;
  generateHeaders?: boolean;
  generateJS?: boolean;
  generateDts?: boolean;
}

export function build(options: BuildOptions) {
  const { entry, outDir, generateHeaders = true, generateJS = true, generateDts = false } = options;
  const files = globSync(entry);
  
  files.forEach(file => {
    console.log(`Compiling ${file}...`);
    const moduleInfo = parseExitaFile(file);
    
    if (generateHeaders) generateHeader(moduleInfo, outDir);
    if (generateJS) compileToJS(file, outDir);
    if (generateDts) generateDts(file, outDir);
    
    console.log(`  -> ${moduleInfo.exports.length} exports`);
  });
  console.log('Build completed.');
}
EOF

# ───────── 8. Update type definition ─────────
cat > src/types.ts << 'EOF'
export interface ExitaModule {
  name: string;
  headerPath: string;
  sourcePath: string;
  exports: ExitaExport[];
}

export interface ExitaExport {
  kind: 'function' | 'variable' | 'interface';
  name: string;
  typeAnnotation?: string;
  params?: ExitaParam[];
  returnType?: string;
  isSignal?: boolean;
  defaultValues?: Record<string, string>;
}

export interface ExitaParam {
  name: string;
  typeAnnotation?: string;
  defaultValue?: string;
}

export interface CompilerOptions {
  entry: string;
  outDir: string;
  generateHeaders: boolean;
  generateJS: boolean;
  generateDts: boolean;
  watch: boolean;
}
EOF

echo ""
echo "✅ Phase 3 installed! New features:"
echo "  • Watch mode:        node dist/cli.js build --watch"
echo "  • .d.ts generation:  node dist/cli.js build --entry ... (auto generated alongside .hxj)"
echo "  • Bundling:          node dist/cli.js bundle examples/App.exj -o dist/bundle.js"
echo "  • Breaking changes:  node dist/cli.js check-breaking headers/Button.hxj v1.0.0 (needs .bak file)"
echo "  • Async components:  Now work automatically (show loading placeholder)"
echo ""
echo "Rebuild compiler:      npm run build"
echo "Test with:             node dist/cli.js dev"
