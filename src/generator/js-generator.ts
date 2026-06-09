import * as fs from 'fs';
import * as path from 'path';
import * as ts from 'typescript';
import { parseExitaFile } from '../parser/exita-parser';
import { signalTransformer } from '../transforms/signal-transformer';
import { extractStylesFromCode } from '../transforms/style-extractor';

export function compileToJS(filePath: string, outDir: string): string {
  const rawCode = fs.readFileSync(filePath, 'utf-8');
  const moduleInfo = parseExitaFile(filePath);

  // Style extraction from original source (before transformation)
  const componentName = moduleInfo.name;
  const scopedClass = extractStylesFromCode(rawCode, componentName, outDir);

  // Remove Add.Module lines
  let cleanCode = rawCode.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');

  // Insert the scoped class into the root element of the component if available (advanced)
  // For now, just let the user manually add class={scopedClass} later. We'll inject a prop.

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
  console.log(`Generated JS: ${outFile}`);
  return outFile;
}
