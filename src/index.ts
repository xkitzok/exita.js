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
