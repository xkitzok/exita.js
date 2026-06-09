#!/bin/bash
set -e

echo "📦 Adding Phase 2 runtime & transforms..."

# ──────────────── 1. Runtime Library ────────────────
mkdir -p src/runtime
cat > src/runtime/exita-runtime.ts << 'EOF'
/**
 * Exita Runtime – fine-grained reactivity & JSX
 */

// ── Signal Implementation ──
export function signal<T>(initialValue: T) {
  let value = initialValue;
  const subscribers = new Set<() => void>();

  const proxy = new Proxy({} as { value: T }, {
    get(_, prop) {
      if (prop === 'value') {
        if (currentEffect) {
          subscribers.add(currentEffect);
        }
        return value;
      }
      return undefined;
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

  return proxy;
}

let currentEffect: (() => void) | null = null;

export function effect(fn: () => void) {
  const run = () => {
    currentEffect = run;
    fn();
    currentEffect = null;
  };
  run();
}

// ── JSX Factory ──
export function createElement(
  type: string | Function,
  props: Record<string, any> | null,
  ...children: (Node | string | (() => Node))[]
): Node {
  if (typeof type === 'function') {
    // Component
    return type({ ...props, children });
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
        el.setAttribute(key, val);
      }
    }
  }

  children.flat().forEach(child => {
    if (typeof child === 'string' || typeof child === 'number') {
      el.appendChild(document.createTextNode(String(child)));
    } else if (child instanceof Node) {
      el.appendChild(child);
    } else if (typeof child === 'function') {
      // Reactive binding: child is a function that returns a Node
      const placeholder = document.createTextNode('');
      el.appendChild(placeholder);
      effect(() => {
        const node = child();
        placeholder.replaceWith(node);
      });
    }
  });

  return el;
}

// JSX Fragment
export function Fragment({ children }: { children?: any[] }) {
  const frag = document.createDocumentFragment();
  (children || []).flat().forEach(child => {
    if (child instanceof Node) frag.appendChild(child);
    else if (typeof child === 'string') frag.appendChild(document.createTextNode(child));
  });
  return frag;
}

// Mount function
export function render(component: () => Node, container: HTMLElement) {
  container.innerHTML = '';
  container.appendChild(component());
}
EOF

echo "✅ exita-runtime.ts created"

# ──────────────── 2. Signal Transform (real implementation) ────────────────
cat > src/transforms/signal-transform.ts << 'EOF'
import * as t from '@babel/types';
import generate from '@babel/generator';
import traverse from '@babel/traverse';

/**
 * Converts `let x = initial` inside component functions into
 * `const x = __exita_signal(initial)`, and replaces all references
 * to `x` with `x.value` throughout the function scope.
 */
export function transformSignals(ast: t.File, componentNames: Set<string>) {
  traverse(ast, {
    // Find component functions (named exports or auto-detected)
    FunctionDeclaration(path) {
      if (path.node.id && componentNames.has(path.node.id.name)) {
        transformFunctionBody(path.get('body'), path.scope);
      }
    },
    VariableDeclarator(path) {
      if (
        t.isIdentifier(path.node.id) &&
        componentNames.has(path.node.id.name) &&
        path.node.init &&
        (t.isArrowFunctionExpression(path.node.init) || t.isFunctionExpression(path.node.init))
      ) {
        const fnPath = path.get('init');
        if (fnPath.isArrowFunctionExpression() || fnPath.isFunctionExpression()) {
          transformFunctionBody(fnPath.get('body'), fnPath.scope);
        }
      }
    },
  });
}

function transformFunctionBody(bodyPath: any, scope: any) {
  // Collect all `let` declarations with initializers
  const signalVars = new Map<string, t.Expression>();

  bodyPath.traverse({
    VariableDeclaration(innerPath: any) {
      const node: t.VariableDeclaration = innerPath.node;
      if (node.kind === 'let') {
        node.declarations.forEach((decl: t.VariableDeclarator) => {
          if (t.isIdentifier(decl.id) && decl.init) {
            const varName = decl.id.name;
            // Save initializer expression
            signalVars.set(varName, decl.init);
            // Replace `let x = val` with `const x = __exita_signal(val)`
            decl.init = t.callExpression(t.identifier('__exita_signal'), [decl.init]);
          }
        });
        // Change kind to 'const'
        node.kind = 'const';
      }
    },
  });

  // Replace all references to these variables with `.value` access
  bodyPath.traverse({
    Identifier(innerPath: any) {
      if (signalVars.has(innerPath.node.name)) {
        // Skip if it's the declaration itself (already transformed)
        if (
          innerPath.parentPath.isVariableDeclarator() &&
          innerPath.parentPath.node.id === innerPath.node
        ) {
          return;
        }
        // Replace `x` with `x.value`
        innerPath.replaceWith(
          t.memberExpression(
            t.identifier(innerPath.node.name),
            t.identifier('value')
          )
        );
      }
    },
  });
}
EOF

echo "✅ signal-transform.ts updated"

# ──────────────── 3. Style Extractor ────────────────
cat > src/transforms/style-extractor.ts << 'EOF'
import * as t from '@babel/types';
import generate from '@babel/generator';
import traverse from '@babel/traverse';
import * as path from 'path';
import * as fs from 'fs';

/**
 * Finds all <style> JSX elements in the component tree, extracts their CSS text,
 * replaces them with a scoped class attribute, and writes the CSS to a file.
 */
export function extractStyles(ast: t.File, componentName: string, outDir: string): string {
  let cssContent = '';
  let className = `exita-${componentName.toLowerCase()}-${Math.random().toString(36).substr(2, 5)}`;

  traverse(ast, {
    JSXElement(jsxPath) {
      const node = jsxPath.node;
      if (
        t.isJSXIdentifier(node.openingElement.name, { name: 'style' })
      ) {
        // Extract CSS text from the only child (a JSXExpressionContainer with template literal)
        const child = node.children[0];
        if (child && t.isJSXExpressionContainer(child) && t.isTemplateLiteral(child.expression)) {
          cssContent += child.expression.quasis.map(q => q.value.cooked).join('');
        }
        // Replace <style>...</style> with nothing (or an empty expression)
        jsxPath.remove();
      }
    },
  });

  if (cssContent) {
    // Prepend scoped class selector to each rule
    cssContent = `.${className} { ${cssContent} }`;
    const cssDir = path.join(outDir, 'styles');
    fs.mkdirSync(cssDir, { recursive: true });
    fs.writeFileSync(path.join(cssDir, `${componentName}.exj.css`), cssContent);
    console.log(`  Styles extracted: ${componentName}.exj.css`);
  }

  return className;
}
EOF

echo "✅ style-extractor.ts created"

# ──────────────── 4. JS Generator (orchestrates transforms) ────────────────
cat > src/generator/js-generator.ts << 'EOF'
import { parse } from '@babel/parser';
import generate from '@babel/generator';
import * as fs from 'fs';
import * as path from 'path';
import { parseExitaFile } from '../parser/exita-parser';
import { transformSignals } from '../transforms/signal-transform';
import { extractStyles } from '../transforms/style-extractor';
import * as t from '@babel/types';

export function compileToJS(filePath: string, outDir: string): string {
  const rawCode = fs.readFileSync(filePath, 'utf-8');
  const moduleInfo = parseExitaFile(filePath);

  // Clean Add.Module lines
  const cleanCode = rawCode.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');

  const ast = parse(cleanCode, {
    sourceType: 'module',
    plugins: ['jsx', 'typescript'],
  });

  const componentNames = new Set(moduleInfo.exports
    .filter(e => e.kind === 'function')
    .map(e => e.name)
  );

  // 1. Signal transform
  transformSignals(ast, componentNames);

  // 2. Style extraction (per component? We'll extract from the whole file)
  let scopedClass = '';
  if (componentNames.size > 0) {
    const compName = [...componentNames][0]; // simplest: first component
    scopedClass = extractStyles(ast, compName, outDir);
  }

  // 3. Add import for runtime at the top
  const runtimeImport = t.importDeclaration(
    [t.importSpecifier(t.identifier('__exita_signal'), t.identifier('signal'))],
    t.stringLiteral('exita-runtime')
  );
  ast.program.body.unshift(runtimeImport);

  // 4. Generate code
  const { code } = generate(ast, {
    retainLines: true,
    compact: false,
  });

  // 5. Write output .js file
  const outFile = path.join(outDir, path.basename(filePath, '.exj') + '.exj.js');
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, code, 'utf-8');
  console.log(`Generated JS: ${outFile}`);

  return outFile;
}
EOF

echo "✅ js-generator.ts created"

# ──────────────── 5. Update index.ts to include JS generation ────────────────
cat > src/index.ts << 'EOF'
import { parseExitaFile } from './parser/exita-parser';
import { generateHeader } from './generator/hxj-generator';
import { compileToJS } from './generator/js-generator';
import * as fs from 'fs';
import * as path from 'path';
import { globSync } from 'glob';

export interface BuildOptions {
  entry: string;
  outDir: string;
  generateHeaders?: boolean;
  generateJS?: boolean;
}

export function build(options: BuildOptions) {
  const { entry, outDir, generateHeaders = true, generateJS = true } = options;
  const files = globSync(entry);
  
  if (files.length === 0) {
    console.error(`No .exj files found matching pattern: ${entry}`);
    return;
  }

  files.forEach(file => {
    console.log(`Compiling ${file}...`);
    const moduleInfo = parseExitaFile(file);
    
    if (generateHeaders) {
      generateHeader(moduleInfo, outDir);
    }
    if (generateJS) {
      compileToJS(file, outDir);
    }
    console.log(`  -> ${moduleInfo.exports.length} exports found`);
  });

  console.log('Build completed.');
}
EOF

echo "✅ index.ts updated"

# ──────────────── 6. Update CLI to add dev command ────────────────
cat > src/cli.ts << 'EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { createServer } from 'http';
import * as fs from 'fs';
import * as path from 'path';

const program = new Command();

program
  .name('exita')
  .description('Exita compiler CLI – Phase 2')
  .version('0.2.0');

program
  .command('build')
  .description('Compile .exj files and generate .hxj & .js')
  .option('-e, --entry <pattern>', 'File pattern for .exj files', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .action((options) => {
    build({
      entry: options.entry,
      outDir: options.outDir,
      generateHeaders: true,
      generateJS: true,
    });
  });

program
  .command('dev')
  .description('Start dev server with auto-compilation')
  .option('-p, --port <number>', 'Port', '3000')
  .action((options) => {
    const port = parseInt(options.port);
    const server = createServer((req, res) => {
      if (req.url === '/' || req.url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`
<!DOCTYPE html>
<html>
<head><title>Exita Dev</title></head>
<body>
  <div id="app"></div>
  <script type="module">
    import { render } from '/runtime.js';
    import App from '/App.exj.js';
    render(App, document.getElementById('app'));
  </script>
</body>
</html>`);
      } else if (req.url?.endsWith('.js')) {
        const filePath = path.join('dist', req.url);
        if (fs.existsSync(filePath)) {
          res.writeHead(200, { 'Content-Type': 'application/javascript' });
          res.end(fs.readFileSync(filePath));
        } else {
          res.writeHead(404);
          res.end('Not found');
        }
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });

    server.listen(port, () => {
      console.log(`🚀 Exita dev server running at http://localhost:${port}`);
      // Auto-build once
      build({
        entry: 'examples/**/*.exj',
        outDir: 'dist',
        generateHeaders: false,
        generateJS: true,
      });
    });
  });

program.parse(process.argv);
EOF

echo "✅ cli.ts updated"

# ──────────────── 7. Install dev server dependency (http already built-in) ────────────────
echo "Installing dependencies..."
npm install

echo ""
echo "🎉 Phase 2 setup complete!"
echo ""
echo "Next steps:"
echo "  1. Build: npm run build"
echo "  2. Compile: node dist/cli.js build --entry 'examples/*.exj' --outDir dist"
echo "  3. Run dev: node dist/cli.js dev"
