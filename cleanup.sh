#!/bin/bash
set -e

echo "🧹 Cleaning & Optimizing Exita Project"

# ── 1. Remove unused dependencies ──
# (We only keep what's actually imported)
npm uninstall \
  @babel/plugin-transform-react-jsx \
  @babel/plugin-transform-typescript \
  @types/babel__generator \
  @types/babel__traverse \
  @types/ws \
  ws \
  2>/dev/null || true

# chokidar, esbuild, semver are used → keep
# @babel/parser, traverse, generator, types → used in parser → keep

# ── 2. Delete unused source files ──
rm -f src/utils/ast-helpers.ts          # unused
rm -f src/transforms/signal-transform.ts   # old Babel version, we use signal-transformer.ts now

# ── 3. Optimize runtime generation (use esbuild to bundle + minify) ──
# Update the build process to always produce a production-ready runtime.js
cat > src/runtime/build-runtime.ts << 'EOF'
import * as esbuild from 'esbuild';
import * as path from 'path';
import * as fs from 'fs';

export async function buildRuntime(outDir: string) {
  const src = path.join(__dirname, 'exita-runtime.ts');
  const out = path.join(outDir, 'runtime.js');

  // Write temporary entry that just re-exports everything
  const tmpEntry = path.join(outDir, '_runtime_entry.ts');
  fs.writeFileSync(tmpEntry, `
    export { signal as __exita_signal, createElement as __exita_createElement, Fragment, render, effect, computed } from './exita-runtime';
  `);

  await esbuild.build({
    entryPoints: [path.join(__dirname, 'exita-runtime.ts')],
    bundle: true,
    minify: true,
    format: 'esm',
    outfile: out,
    platform: 'browser',
    target: 'es2020',
    globalName: 'Exita',
    plugins: [],
  });

  // Also create a non-minified dev version for debugging
  await esbuild.build({
    entryPoints: [path.join(__dirname, 'exita-runtime.ts')],
    bundle: true,
    minify: false,
    format: 'esm',
    outfile: path.join(outDir, 'runtime.dev.js'),
    platform: 'browser',
    target: 'es2020',
  });

  // Clean up temp file
  try { fs.unlinkSync(tmpEntry); } catch {}
  console.log('⚡ Optimized runtime built:', out);
}
EOF

# ── 4. Update main build to include runtime generation ──
cat > src/index.ts << 'EOF'
import { parseExitaFile } from './parser/exita-parser';
import { generateHeader } from './generator/hxj-generator';
import { generateDts as emitDts } from './generator/dts-generator';
import { compileToJS } from './generator/js-generator';
import { buildRuntime } from './runtime/build-runtime';
import { globSync } from 'glob';

export interface BuildOptions {
  entry: string;
  outDir: string;
  generateHeaders?: boolean;
  generateJS?: boolean;
  generateDts?: boolean;
  generateRuntime?: boolean;
}

export async function build(options: BuildOptions) {
  const {
    entry, outDir,
    generateHeaders = true,
    generateJS = true,
    generateDts = false,
    generateRuntime = true,
  } = options;

  const files = globSync(entry);

  files.forEach(file => {
    console.log(`Compiling ${file}...`);
    const moduleInfo = parseExitaFile(file);

    if (generateHeaders) generateHeader(moduleInfo, outDir);
    if (generateJS) compileToJS(file, outDir);
    if (generateDts) emitDts(file, outDir);

    console.log(`  -> ${moduleInfo.exports.length} exports`);
  });

  if (generateRuntime) {
    await buildRuntime(outDir);
  }

  console.log('Build completed.');
}
EOF

# ── 5. Update CLI to handle async build calls ──
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
  .description('Exita compiler – Optimized')
  .version('0.4.0');

// Build command (with watch, async)
program
  .command('build')
  .option('-e, --entry <pattern>', 'File pattern', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .option('--watch', 'Watch and rebuild')
  .action(async opts => {
    const runBuild = () => build({
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
      watcher.on('change', async (file) => {
        console.log(`\n🔄 Recompiling ${file}...`);
        await runBuild();
      });
    }
  });

// Dev server – watches & recompiles automatically
program
  .command('dev')
  .option('-p, --port <number>', 'Port', '3000')
  .action(async opts => {
    const port = parseInt(opts.port);
    const entryPattern = 'examples/**/*.exj';

    // Initial build (async)
    await build({
      entry: entryPattern,
      outDir: 'dist',
      generateHeaders: false,
      generateJS: true,
    });

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
        } else {
          res.writeHead(404);
          res.end('Not found');
        }
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });

    // Watch .exj files and rebuild
    const watcher = chokidar.watch(entryPattern, { persistent: true });
    watcher.on('change', async (filePath) => {
      console.log(`\n🔄 File changed: ${filePath}`);
      await build({ entry: entryPattern, outDir: 'dist', generateHeaders: false, generateJS: true });
    });

    server.listen(port, () => {
      console.log(`🚀 Exita dev server: http://localhost:${port}`);
      console.log(`👀 Watching for changes in ${entryPattern}...`);
    });
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
  .action(async (entry, opts) => {
    await bundleApp(entry, opts.outFile);
  });

program.parse(process.argv);
EOF

# ── 6. Ensure necessary dependencies are installed ──
npm install

# ── 7. Add .gitignore if missing ──
if [ ! -f .gitignore ]; then
  cat > .gitignore << 'IGNORE'
node_modules/
dist/
*.js
!examples/*.exj
!README.md
!LICENSE
IGNORE
fi

echo ""
echo "✅ Cleanup complete! Optimizations:"
echo "  • Removed unused dependencies (Babel JSX/TS plugins, ws, etc.)"
echo "  • Removed dead files (ast-helpers.ts, old signal-transform.ts)"
echo "  • Runtime now generated & minified automatically via esbuild"
echo "  • Dev server & watch mode are now async (faster)"
echo "  • Runtime also available as runtime.dev.js for debugging"
echo ""
echo "Rebuild compiler:  npm run build"
echo "Start dev server:  node dist/cli.js dev"
