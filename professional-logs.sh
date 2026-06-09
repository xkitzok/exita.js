#!/bin/bash
set -e

echo "Patching compiler output to use only success/error/warning/info"

# ── 1. Patch src/runtime/build-runtime.ts ──
cat > src/runtime/build-runtime.ts << 'RUNTIME_EOF'
import * as esbuild from 'esbuild';
import * as path from 'path';
import { success, error } from '../utils/diagnostics';

export async function buildRuntime(outDir: string) {
  const projectRoot = process.cwd();
  const runtimeSource = path.join(projectRoot, 'src', 'runtime', 'exita-runtime.ts');
  const outFile = path.join(outDir, 'runtime.js');

  try {
    await esbuild.build({
      entryPoints: [runtimeSource],
      bundle: true,
      minify: true,
      format: 'esm',
      outfile: outFile,
      platform: 'browser',
      target: 'es2020',
    });

    await esbuild.build({
      entryPoints: [runtimeSource],
      bundle: true,
      minify: false,
      format: 'esm',
      outfile: path.join(outDir, 'runtime.dev.js'),
      platform: 'browser',
      target: 'es2020',
    });

    success('Runtime built');
  } catch (e: any) {
    error(e.message);
  }
}
RUNTIME_EOF

# ── 2. Patch src/index.ts ──
cat > src/index.ts << 'INDEX_EOF'
import { parseExitaFile } from './parser/exita-parser';
import { generateHeader } from './generator/hxj-generator';
import { generateDts as emitDts } from './generator/dts-generator';
import { compileToJS } from './generator/js-generator';
import { buildRuntime } from './runtime/build-runtime';
import { globSync } from 'glob';
import { success, info, error } from './utils/diagnostics';

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
  if (files.length === 0) {
    warn(`No .exj files found matching pattern: ${entry}`);
    return;
  }

  for (const file of files) {
    // Keep informational message concise
    info(`Compiling ${file}`);
    try {
      const moduleInfo = parseExitaFile(file);

      if (generateHeaders) generateHeader(moduleInfo, outDir);
      if (generateJS) compileToJS(file, outDir);
      if (generateDts) emitDts(file, outDir);
    } catch (e: any) {
      error(e.message);
    }
  }

  if (generateRuntime) {
    await buildRuntime(outDir);
  }

  success('Build completed');
}
INDEX_EOF

# ── 3. Patch the style extractor and JS generator to use diagnostics ──
cat > src/generator/js-generator.ts << 'JS_EOF'
import * as fs from 'fs';
import * as path from 'path';
import * as ts from 'typescript';
import { parseExitaFile } from '../parser/exita-parser';
import { signalTransformer } from '../transforms/signal-transformer';
import { extractStylesFromCode } from '../transforms/style-extractor';
import { success, info, error } from '../utils/diagnostics';

export function compileToJS(filePath: string, outDir: string): string {
  const rawCode = fs.readFileSync(filePath, 'utf-8');
  const moduleInfo = parseExitaFile(filePath);

  // Style extraction (optional)
  if (rawCode.includes('<style>')) {
    const componentName = moduleInfo.name;
    extractStylesFromCode(rawCode, componentName, outDir);
  }

  // Remove Add.Module lines
  let cleanCode = rawCode.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');

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
  // No output here – the build loop already says "Compiling ..."

  return outFile;
}
JS_EOF

# ── 4. Rebuild ──
npm run build

echo ""
echo "Now run: exita run"
echo "All output is clean diagnostic messages."
