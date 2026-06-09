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
