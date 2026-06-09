#!/bin/bash
set -e

echo " Professional Exita – finalised CLI, no emojis"

# ── 1. Professional diagnostics (ANSI only) ──
cat > src/utils/diagnostics.ts << 'DIAG_EOF'
const red    = (t: string) => `\x1b[31m${t}\x1b[0m`;
const yellow = (t: string) => `\x1b[33m${t}\x1b[0m`;
const green  = (t: string) => `\x1b[32m${t}\x1b[0m`;
const cyan   = (t: string) => `\x1b[36m${t}\x1b[0m`;

export function error(message: string): void {
  console.error(`${red('error')}: ${message}`);
  process.exit(1);
}

export function warn(message: string): void {
  console.warn(`${yellow('warning')}: ${message}`);
}

export function info(message: string): void {
  console.log(`${cyan('info')}: ${message}`);
}

export function success(message: string): void {
  console.log(`${green('success')}: ${message}`);
}

export function progressBar(current: number, total: number, label: string = 'Installing') {
  const pct = Math.round((current / total) * 100);
  const filled = Math.round(pct / 5);          // 20‑char bar
  const bar = '#'.repeat(filled) + '-'.repeat(20 - filled);
  process.stdout.write(`\r${label}... [${bar}] ${pct}%`);
  if (current >= total) process.stdout.write('\n');
}
DIAG_EOF

# ── 2. Professional CLI (no emojis anywhere) ──
cat > src/cli.ts << 'CLI_EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';
import { error, warn, success, info, progressBar } from './utils/diagnostics';

const program = new Command()
  .name('exita')
  .description('Exita -- Full-Stack Framework')
  .version('0.5.0');

process.on('uncaughtException', (err) => error(err.message));
process.on('unhandledRejection', (reason) => error(reason instanceof Error ? reason.message : String(reason)));

// ── Build ──
program
  .command('build')
  .description('Compile .exj files')
  .option('-e, --entry <pattern>', 'File pattern', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory', 'dist')
  .option('--watch', 'Watch and rebuild')
  .action(async opts => {
    try {
      const runBuild = async () => {
        await build({
          entry: opts.entry,
          outDir: opts.outDir,
          generateHeaders: true,
          generateJS: true,
          generateDts: true,
        });
      };
      await runBuild();
      if (opts.watch) {
        const watcher = chokidar.watch(opts.entry, { persistent: true });
        info(`Watching ${opts.entry}...`);
        watcher.on('change', async file => {
          console.log(`\nRecompiling ${file}...`);
          await runBuild();
        });
      }
      success('Build completed');
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Run / Dev ──
program
  .command('run')
  .alias('dev')
  .description('Start dev server with auto-rebuild')
  .option('-p, --port <number>', 'Port', '3000')
  .option('-e, --entry <file>', 'Entry .exj file', 'src/app.exj')
  .action(async opts => {
    try {
      const port = parseInt(opts.port);
      const entryFile = opts.entry;
      const entryDir = path.dirname(entryFile);
      const entryPattern = path.join(entryDir, '*.exj');
      const mainModule = path.basename(entryFile, '.exj') + '.exj.js';

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
    import { injectErrorOverlay, render } from './runtime.js';
    injectErrorOverlay();
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

      const watcher = chokidar.watch(entryPattern, { persistent: true });
      watcher.on('change', async filePath => {
        console.log(`\nRecompiling ${filePath}...`);
        await build({ entry: entryPattern, outDir: 'dist', generateHeaders: false, generateJS: true });
      });

      server.listen(port, () => {
        success(`Dev server running at http://localhost:${port}`);
        info(`Watching ${entryPattern}...`);
      });
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Init ──
program
  .command('init')
  .description('Initialize a new Exita project')
  .action(() => {
    try {
      const { initProject } = require('./commands/init');
      initProject();
      success('Project initialized');
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Add ──
program
  .command('add <package>')
  .description('Add a dependency')
  .action(async pkg => {
    try {
      const { addPackage } = require('./commands/add');
      info(`Downloading ${pkg}...`);
      for (let i = 0; i <= 100; i += 10) {
        progressBar(i, 100, 'Installing');
        await new Promise(r => setTimeout(r, 100));
      }
      addPackage(pkg);
      success(`Added ${pkg}`);
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Update ──
program
  .command('update')
  .description('Update Exita to the latest version')
  .action(async () => {
    try {
      info('Updating Exita.js...');
      const { updateExita } = require('./commands/update');
      updateExita();
      success('Update completed');
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Clean ──
program
  .command('clean')
  .description('Remove build artifacts')
  .action(() => {
    try {
      const { cleanProject } = require('./commands/clean');
      cleanProject();
      success('Cleaned');
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Bundle ──
program
  .command('bundle <entry>')
  .description('Bundle for production')
  .option('-o, --outFile <file>', 'Output', 'dist/bundle.js')
  .action(async (entry, opts) => {
    try {
      const { bundleApp } = require('./bundler');
      await bundleApp(entry, opts.outFile);
      success(`Bundled to ${opts.outFile}`);
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Check-breaking ──
program
  .command('check-breaking <header> <version>')
  .description('Check for breaking changes')
  .action((header, version) => {
    try {
      const { checkBreaking } = require('./utils/breaking-changes');
      checkBreaking(header, version);
    } catch (e: any) {
      error(e.message);
    }
  });

// ── Help / Version ──
program.on('--help', () => {
  console.log('\nExamples:');
  console.log('  $ exita init');
  console.log('  $ exita run');
  console.log('  $ exita add lodash');
  console.log('  $ exita update');
});

program.parse(process.argv);
CLI_EOF

# ── 3. Rebuild runtime so injectErrorOverlay is exported ──
npm run build
node -e "
  const { buildRuntime } = require('./dist/runtime/build-runtime.js');
  buildRuntime('dist');
"

# ── 4. Build example app (so it exists immediately) ──
node dist/cli.js build --entry 'examples/*.exj' --outDir dist

echo ""
echo "Done. Start the server:"
echo "  exita run"
