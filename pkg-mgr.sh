#!/bin/bash
set -e

echo "📦 Adding package manager & project commands"

# Create commands directory
mkdir -p src/commands

# ── init command ──
cat > src/commands/init.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';

export function initProject() {
  const cwd = process.cwd();
  const exitapkgPath = path.join(cwd, 'exitapkg.json');
  if (fs.existsSync(exitapkgPath)) {
    console.error('exitapkg.json already exists.');
    return;
  }

  const exitapkg = {
    name: path.basename(cwd),
    version: '0.1.0',
    description: '',
    main: 'src/app.exj',
    scripts: {
      build: 'exita build',
      run: 'exita run',
    },
    dependencies: {},
    devDependencies: {},
  };

  fs.writeFileSync(exitapkgPath, JSON.stringify(exitapkg, null, 2));

  // Create src/app.exj
  const srcDir = path.join(cwd, 'src');
  if (!fs.existsSync(srcDir)) fs.mkdirSync(srcDir);
  fs.writeFileSync(
    path.join(srcDir, 'app.exj'),
    `Add.Module [App.hxj]

function App() {
  let message = "Hello Exita!"
  return <h1>{message}</h1>
}

export default App
`
  );

  // Create lock file
  fs.writeFileSync(
    path.join(cwd, 'exitapkg.json.lock'),
    JSON.stringify({ lockfileVersion: 1, packages: {} }, null, 2)
  );

  console.log('✅ Exita project initialized!');
  console.log('   Run: exita run');
}
EOF

# ── add command ──
cat > src/commands/add.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

export function addPackage(packageName: string) {
  const cwd = process.cwd();
  const exitapkgPath = path.join(cwd, 'exitapkg.json');
  if (!fs.existsSync(exitapkgPath)) {
    console.error('No exitapkg.json found. Run `exita init` first.');
    return;
  }

  const exitapkg = JSON.parse(fs.readFileSync(exitapkgPath, 'utf-8'));
  exitapkg.dependencies = exitapkg.dependencies || {};
  exitapkg.dependencies[packageName] = '*';
  fs.writeFileSync(exitapkgPath, JSON.stringify(exitapkg, null, 2));

  // Create a temporary package.json for npm compatibility
  const pkgJson = {
    name: exitapkg.name,
    version: exitapkg.version,
    dependencies: exitapkg.dependencies,
    devDependencies: exitapkg.devDependencies,
  };
  fs.writeFileSync(path.join(cwd, 'package.json'), JSON.stringify(pkgJson, null, 2));

  try {
    console.log(`Installing ${packageName}...`);
    execSync(`npm install --save ${packageName}`, { stdio: 'inherit', cwd });

    // Rename lock file to exitapkg.json.lock
    if (fs.existsSync(path.join(cwd, 'package-lock.json'))) {
      fs.copyFileSync(
        path.join(cwd, 'package-lock.json'),
        path.join(cwd, 'exitapkg.json.lock')
      );
      fs.unlinkSync(path.join(cwd, 'package-lock.json'));
    }
    console.log(`✅ Added ${packageName}`);
  } finally {
    // Clean up the temporary package.json
    if (fs.existsSync(path.join(cwd, 'package.json'))) {
      fs.unlinkSync(path.join(cwd, 'package.json'));
    }
  }
}
EOF

# ── update command ──
cat > src/commands/update.ts << 'EOF'
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export function updateExita() {
  const repoUrl = 'https://github.com/xkitzok/exita.js';
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'exita-update-'));

  try {
    console.log('⬇️  Cloning latest Exita...');
    execSync(`git clone --depth 1 ${repoUrl} ${tempDir}`, { stdio: 'inherit' });
    execSync('npm install', { cwd: tempDir, stdio: 'inherit' });
    execSync('npm run build', { cwd: tempDir, stdio: 'inherit' });

    // Find current Exita package root (above dist/commands)
    const packageRoot = path.resolve(__dirname, '../..');

    console.log(`Updating Exita in ${packageRoot}...`);
    // Copy the new dist and node_modules
    execSync(`cp -r ${path.join(tempDir, 'dist')} ${packageRoot}`);
    execSync(`cp -r ${path.join(tempDir, 'node_modules')} ${packageRoot}`);
    console.log('✅ Exita updated to the latest version!');
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}
EOF

# ── clean command ──
cat > src/commands/clean.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';

export function cleanProject() {
  const distPath = path.join(process.cwd(), 'dist');
  const lockPath = path.join(process.cwd(), 'exitapkg.json.lock');

  if (fs.existsSync(distPath)) {
    fs.rmSync(distPath, { recursive: true, force: true });
    console.log('🧹 Removed dist/');
  }

  if (fs.existsSync(lockPath)) {
    fs.unlinkSync(lockPath);
    console.log('🧹 Removed exitapkg.json.lock');
  }

  console.log('✅ Cleaned.');
}
EOF

# ── Updated CLI with all commands ──
cat > src/cli.ts << 'EOF'
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
EOF

# ── Update package.json to have a proper bin ──
if [ -f package.json ]; then
  node -e "
    const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
    pkg.bin = { exita: './dist/cli.js' };
    require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2));
  "
fi

# Rebuild
npm run build

echo ""
echo "🎉 Package manager ready!"
echo ""
echo "Try these commands:"
echo "  node dist/cli.js init            # Create a new project"
echo "  node dist/cli.js add react       # Add a dependency"
echo "  node dist/cli.js run             # Dev server"
echo "  node dist/cli.js update          # Self-update"
echo "  node dist/cli.js clean           # Clean"
echo "  node dist/cli.js help            # Show help"
echo ""
echo "To use the 'exita' command globally:  npm link"
