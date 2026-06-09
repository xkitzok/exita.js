#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';
import { bundleApp } from './bundler';
import { checkBreaking } from './utils/breaking-changes';
import { initProject } from './commands/init';
import { addPackage } from './commands/add';
import { updateExita } from './commands/update';
import { cleanProject } from './commands/clean';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';

const program = new Command()
  .name('exita')
  .description('Exita – TypeScript rebuilt for joy')
  .version('0.5.0');

// ------------ BUILD ------------
program
  .command('build')
  .description('Compile .exj files')
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

// ------------ RUN (dev server) ------------
program
  .command('run')
  .alias('dev')
  .description('Start dev server with auto-rebuild')
  .option('-p, --port <number>', 'Port', '3000')
  .action(async opts => {
    const port = parseInt(opts.port);
    const entryPattern = 'src/**/*.exj';   // project source (or examples for demo)

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
    import App from './app.exj.js';
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
      console.log(`\n🔄 File changed: ${filePath}`);
      await build({
        entry: entryPattern,
        outDir: 'dist',
        generateHeaders: false,
        generateJS: true,
      });
    });

    server.listen(port, () => {
      console.log(`🚀 Exita dev server: http://localhost:${port}`);
      console.log(`👀 Watching ${entryPattern}...`);
    });
  });

// ------------ INIT ------------
program
  .command('init')
  .description('Initialize a new Exita project')
  .action(() => initProject());

// ------------ ADD ------------
program
  .command('add <package>')
  .description('Add a dependency to exitapkg.json')
  .action(pkg => addPackage(pkg));

// ------------ UPDATE ------------
program
  .command('update')
  .description('Update Exita to the latest version from GitHub')
  .action(() => updateExita());

// ------------ CLEAN ------------
program
  .command('clean')
  .description('Remove build artifacts')
  .action(() => cleanProject());

// ------------ BUNDLE ------------
program
  .command('bundle <entry>')
  .description('Bundle for production')
  .option('-o, --outFile <file>', 'Output', 'dist/bundle.js')
  .action(async (entry, opts) => bundleApp(entry, opts.outFile));

// ------------ CHECK-BREAKING ------------
program
  .command('check-breaking <header> <version>')
  .description('Check for breaking changes')
  .action((header, version) => checkBreaking(header, version));

// ------------ HELP & VERSION ------------
program
  .command('help')
  .description('Show help')
  .action(() => program.help());

program
  .command('version')
  .description('Show version')
  .action(() => console.log(program.version()));

program.parse(process.argv);
