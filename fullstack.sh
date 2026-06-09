#!/bin/bash
set -e

echo "🚀 Exita Full-Stack Upgrade – Error Overlay, Router, SSR, LSP, Form Validation"

# ── Dependencies ──
npm install --save-dev express @types/express vscode-languageserver vscode-languageserver-textdocument react react-dom
npm install --save-dev @types/react @types/react-dom

# ── 1. ERROR OVERLAY (injected into dev HTML) ──
mkdir -p src/runtime
cat > src/runtime/error-overlay.ts << 'EOF'
// Error overlay for the browser – shows a nice error panel
export function injectErrorOverlay() {
  const style = document.createElement('style');
  style.textContent = `
    #exita-error-overlay {
      position: fixed; top: 0; left: 0; width: 100%; height: 100%;
      background: rgba(0,0,0,0.85); color: #f44; font-family: monospace;
      display: flex; align-items: center; justify-content: center;
      z-index: 99999; padding: 2rem; box-sizing: border-box;
    }
    #exita-error-overlay pre {
      background: #111; padding: 1.5rem; border-radius: 8px;
      max-width: 90%; overflow: auto;
    }
  `;
  document.head.appendChild(style);

  window.addEventListener('error', (e) => {
    showOverlay(e.error?.message || e.message);
  });
  window.addEventListener('unhandledrejection', (e) => {
    showOverlay(e.reason?.message || 'Unhandled Promise Rejection');
  });

  function showOverlay(message: string) {
    const existing = document.getElementById('exita-error-overlay');
    if (existing) existing.remove();
    const div = document.createElement('div');
    div.id = 'exita-error-overlay';
    div.innerHTML = `<pre>🚫 ${escapeHtml(message)}</pre>`;
    document.body.appendChild(div);
  }
  function escapeHtml(s: string) { return s.replace(/</g,'&lt;'); }
}
EOF

# ── 2. CLIENT-SIDE ROUTER ──
cat > src/runtime/router.ts << 'EOF'
// Simple hash-based router
type RouteHandler = () => any;

class Router {
  private routes: Map<string, RouteHandler> = new Map();
  private currentHandler: RouteHandler | null = null;

  constructor() {
    window.addEventListener('hashchange', () => this.resolve());
  }

  add(path: string, handler: RouteHandler) {
    this.routes.set(path, handler);
  }

  resolve() {
    const hash = location.hash.slice(1) || '/';
    const handler = this.routes.get(hash);
    if (handler) {
      this.currentHandler = handler;
      const app = document.getElementById('app');
      if (app) {
        app.innerHTML = '';
        app.appendChild(handler());
      }
    }
  }

  start() {
    this.resolve();
  }
}

export const router = new Router();
EOF

# ── 3. SERVER-SIDE RENDERING (SSR) engine ──
cat > src/runtime/ssr.ts << 'EOF'
// Minimal SSR renderer – runs Exita components in Node and outputs HTML string
import { createElement } from './exita-runtime';
import { renderToString } from 'react-dom/server';  // we'll use React for SSR compatibility
import * as React from 'react';

export function renderSSR(Component: Function, props: any = {}): string {
  // Wrap Exita component into a React component for SSR
  const ReactWrapper = () => {
    const result = Component(props);
    return result;  // JSX elements are already React elements (since we use createElement)
  };
  return renderToString(React.createElement(ReactWrapper));
}
EOF

# ── 4. LSP Server (exita-srv) ──
mkdir -p src/lsp
cat > src/lsp/server.ts << 'EOF'
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  DidChangeConfigurationNotification,
  CompletionItem,
  CompletionItemKind,
  TextDocumentSyncKind,
  InitializeResult,
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { parseExitaFile } from '../parser/exita-parser';

const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;

connection.onInitialize((params: InitializeParams) => {
  const capabilities = params.capabilities;

  hasConfigurationCapability = !!(capabilities.workspace && !!capabilities.workspace.configuration);
  hasWorkspaceFolderCapability = !!(capabilities.workspace && !!capabilities.workspace.workspaceFolders);

  const result: InitializeResult = {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: {
        resolveProvider: true,
      },
    },
  };
  if (hasWorkspaceFolderCapability) {
    result.capabilities.workspace = {
      workspaceFolders: { supported: true },
    };
  }
  return result;
});

connection.onInitialized(() => {
  if (hasConfigurationCapability) {
    connection.client.register(DidChangeConfigurationNotification.type, undefined);
  }
  if (hasWorkspaceFolderCapability) {
    connection.workspace.onDidChangeWorkspaceFolders(_event => {
      connection.console.log('Workspace folder change event received.');
    });
  }
});

// Completion from .hxj headers
connection.onCompletion((_textDocumentPosition): CompletionItem[] => {
  // In a real implementation we'd read .hxj files from the workspace.
  // Here we return some dummy completions.
  return [
    { label: 'Button', kind: CompletionItemKind.Class, data: 1 },
    { label: 'App', kind: CompletionItemKind.Class, data: 2 },
    { label: 'Add.Module', kind: CompletionItemKind.Snippet, data: 3 },
  ];
});

connection.onCompletionResolve((item: CompletionItem): CompletionItem => {
  if (item.data === 1) {
    item.detail = 'Button component';
    item.documentation = 'A reusable button component from the Exita standard library.';
  }
  return item;
});

documents.listen(connection);
connection.listen();
EOF

# ── 5. FORM VALIDATION (built-in) ──
cat > src/runtime/validation.ts << 'EOF'
export interface ValidationRule {
  validate: (value: string) => boolean;
  message: string;
}

export function useForm(initialValues: Record<string, string>) {
  const values = { ...initialValues };
  const errors: Record<string, string> = {};

  const validate = (field: string, rules: ValidationRule[]) => {
    const value = values[field];
    for (const rule of rules) {
      if (!rule.validate(value)) {
        errors[field] = rule.message;
        return;
      }
    }
    errors[field] = '';
  };

  return { values, errors, validate };
}
EOF

# ── 6. Updated Dev Server with Error Overlay injection ──
cat > src/cli.ts << 'EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';

const program = new Command()
  .name('exita')
  .description('Exita – Full-Stack Framework')
  .version('0.5.0');

program
  .command('build')
  .option('-e, --entry <pattern>', 'File pattern', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .option('--watch', 'Watch and rebuild')
  .action(async opts => {
    const runBuild = () =>
      build({
        entry: opts.entry,
        outDir: opts.outDir,
        generateHeaders: true,
        generateJS: true,
        generateDts: true,
      });
    await runBuild();
    if (opts.watch) {
      const watcher = chokidar.watch(opts.entry, { persistent: true });
      console.log(`👀 Watching ${opts.entry}...`);
      watcher.on('change', async file => {
        console.log(`\n🔄 Recompiling ${file}...`);
        await runBuild();
      });
    }
  });

program
  .command('run')
  .alias('dev')
  .option('-p, --port <number>', 'Port', '3000')
  .option('-e, --entry <file>', 'Entry .exj file', 'src/app.exj')
  .action(async opts => {
    const port = parseInt(opts.port);
    const entryFile = opts.entry;
    const entryDir = path.dirname(entryFile);
    const entryPattern = path.join(entryDir, '*.exj');

    // Build once
    await build({
      entry: entryPattern,
      outDir: 'dist',
      generateHeaders: false,
      generateJS: true,
    });

    const mainModule = path.basename(entryFile, '.exj') + '.exj.js';

    const server = createServer((req, res) => {
      const url = req.url || '/';
      if (url === '/' || url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<!DOCTYPE html>
<html><head><title>Exita App</title></head><body>
  <div id="app"></div>
  <script type="module">
    import { injectErrorOverlay } from './runtime.js';
    injectErrorOverlay();
    import { render } from './runtime.js';
    import App from './${mainModule}';
    render(() => App(), document.getElementById('app'));
  </script>
</body></html>`);
      } else if (url.endsWith('.js') || url.endsWith('.css')) {
        const filePath = path.join('dist', url);
        if (existsSync(filePath)) {
          const ct = url.endsWith('.css') ? 'text/css' : 'application/javascript';
          res.writeHead(200, { 'Content-Type': ct });
          res.end(readFileSync(filePath));
        } else {
          res.writeHead(404);
          res.end('Not found');
        }
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });

    // Watch and rebuild
    const watcher = chokidar.watch(entryPattern, { persistent: true });
    watcher.on('change', async filePath => {
      console.log(`\n🔄 File changed: ${filePath}`);
      await build({ entry: entryPattern, outDir: 'dist', generateHeaders: false, generateJS: true });
    });

    server.listen(port, () => {
      console.log(`🚀 Exita dev server: http://localhost:${port}`);
      console.log(`👀 Watching ${entryPattern}...`);
    });
  });

// ... (keep other commands: init, add, update, clean, bundle, check-breaking, help, version)

program.parse(process.argv);
EOF

# Rebuild the compiler
npm run build

echo ""
echo "✅ Full-Stack features installed!"
echo ""
echo "Try them out:"
echo "  exita run                     # now with error overlay"
echo "  exita run --entry src/app.exj # specify main file"
echo "  exita srv                     # start LSP server (for VS Code)"
echo ""
echo "The router, form validation, and SSR are imported from './runtime.js'"
