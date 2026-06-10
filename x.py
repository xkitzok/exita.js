#!/usr/bin/env python3
"""Exita bootstrapper – compiles the compiler and runs commands."""

import sys
import os
import subprocess
import shutil
import pathlib
import stat

ROOT = pathlib.Path(__file__).resolve().parent
DIST_CLI = ROOT / "dist" / "cli.js"
GLOBAL_LINK = "/usr/local/bin/exita"

BOOTSTRAP_JS = r"""
const fs = require('fs');
const path = require('path');
const ts = require('typescript');
const glob = require('glob');
const esbuild = require('esbuild');

const root = process.cwd();
const files = glob.sync('src/**/*.exj');

files.forEach(file => {
  const code = fs.readFileSync(file, 'utf8');
  const clean = code.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');
  const result = ts.transpileModule(clean, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
      allowSyntheticDefaultImports: true,
      strict: false
    }
  });
  const out = path.join('dist', path.relative('src', file).replace(/\.exj$/, '.js'));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, result.outputText);
});

const runtimeSrc = path.join(root, 'src', 'runtime', 'exita-runtime.exj');
if (fs.existsSync(runtimeSrc)) {
  esbuild.buildSync({
    entryPoints: [runtimeSrc],
    bundle: true,
    minify: true,
    format: 'esm',
    outfile: path.join('dist', 'runtime.js'),
    platform: 'browser',
    target: 'es2020',
    loader: { '.exj': 'ts' }
  });
}
console.log('Bootstrap complete');
"""

def find_node():
    """Return full path to Node.js, or None."""
    return shutil.which('node') or shutil.which('nodejs')

def ensure_deps():
    """Install npm dependencies if node_modules is missing."""
    if not (ROOT / 'node_modules').exists():
        print("Installing dependencies...")
        subprocess.run(['npm', 'install'], cwd=ROOT, check=True)

def bootstrap():
    """Compile all .exj sources if dist/cli.js does not exist."""
    if DIST_CLI.exists():
        return
    print("Bootstrapping Exita compiler...")
    node = find_node()
    if not node:
        sys.exit("Error: Node.js not found. Install Node.js 18+.")
    ensure_deps()
    bs_path = ROOT / '_bootstrap.js'
    bs_path.write_text(BOOTSTRAP_JS)
    try:
        subprocess.run([node, str(bs_path)], cwd=ROOT, check=True)
    except subprocess.CalledProcessError as e:
        sys.exit(f"Bootstrap failed: {e}")
    finally:
        bs_path.unlink()
    if not DIST_CLI.exists():
        sys.exit("Bootstrap failed: dist/cli.js not created.")

def fix_global_exita():
    """Ensure /usr/local/bin/exita is a symlink to dist/cli.js.
    Requires root privileges. If it fails, print a warning and continue.
    """
    if os.name != 'posix':
        return

    # Ensure dist/cli.js has a shebang
    try:
        with open(DIST_CLI, 'r') as f:
            first_line = f.readline()
        if not first_line.startswith('#!/usr/bin/env node'):
            print("Fixing shebang in dist/cli.js")
            with open(DIST_CLI, 'r') as f:
                content = f.read()
            with open(DIST_CLI, 'w') as f:
                f.write('#!/usr/bin/env node\n' + content)
        # Make executable
        st = os.stat(DIST_CLI)
        os.chmod(DIST_CLI, st.st_mode | stat.S_IEXEC)
    except Exception as e:
        print(f"Warning: Could not prepare dist/cli.js: {e}")
        return

    target = str(DIST_CLI.resolve())

    # Check if we can write to the global link location
    try:
        if os.path.exists(GLOBAL_LINK):
            if os.path.islink(GLOBAL_LINK) and os.readlink(GLOBAL_LINK) == target:
                return  # already correct
            os.remove(GLOBAL_LINK)
        os.symlink(target, GLOBAL_LINK)
        print(f"Global exita linked: {GLOBAL_LINK} -> {target}")
    except PermissionError:
        print(f"Permission denied: cannot update {GLOBAL_LINK}.")
        print(f"To enable the global 'exita' command, run:")
        print(f"  sudo rm -f {GLOBAL_LINK}")
        print(f"  sudo ln -sf {target} {GLOBAL_LINK}")
    except Exception as e:
        print(f"Warning: Could not update global exita link: {e}")

def main():
    bootstrap()
    fix_global_exita()
    node = find_node()
    if not node:
        sys.exit("Node.js required to run Exita.")
    # Replace the Python process with the real exita command
    args = [node, str(DIST_CLI)] + sys.argv[1:]
    os.execv(node, args)

if __name__ == "__main__":
    main()