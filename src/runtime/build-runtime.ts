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
