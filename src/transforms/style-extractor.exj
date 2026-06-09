import * as t from '@babel/types';
import * as fs from 'fs';
import * as path from 'path';

export function extractStylesFromCode(code: string, componentName: string, outDir: string): string {
  // Simple regex-based extraction for now (we already have the transpiled code)
  // We'll scan the original source for <style>`...`</style>
  const styleRegex = /<style>\s*`([^`]*)`\s*<\/style>/g;
  let cssContent = '';
  let match;
  while ((match = styleRegex.exec(code)) !== null) {
    cssContent += match[1];
  }

  if (!cssContent) return '';

  // Scope with a unique class
  const scopedClass = `exita-${componentName.toLowerCase()}-${Math.random().toString(36).substr(2, 5)}`;
  const scopedCSS = `.${scopedClass} {\n${cssContent}\n}`;

  const cssDir = path.join(outDir, 'styles');
  fs.mkdirSync(cssDir, { recursive: true });
  fs.writeFileSync(path.join(cssDir, `${componentName}.exj.css`), scopedCSS);
  console.log(`  Styles extracted: ${componentName}.exj.css`);
  return scopedClass;
}
