import * as fs from 'fs';
import * as path from 'path';
import { parseExitaFile } from '../parser/exita-parser';

export function generateDts(filePath: string, outDir: string): string {
  const moduleInfo = parseExitaFile(filePath);
  const dtsPath = path.join(outDir, path.basename(filePath, '.exj') + '.d.ts');
  
  let content = `// Auto-generated type definitions for Exita module: ${moduleInfo.name}\n\n`;
  
  moduleInfo.exports.forEach(exp => {
    if (exp.kind === 'function') {
      content += `export declare function ${exp.name}(`;
      if (exp.params && exp.params.length > 0) {
        content += exp.params.map(p => `${p.name}${p.typeAnnotation ? ': ' + p.typeAnnotation : ''}`).join(', ');
      }
      content += `): ${exp.returnType || 'any'};\n\n`;
    } else if (exp.kind === 'variable') {
      content += `export declare const ${exp.name}: ${exp.typeAnnotation || 'any'};\n\n`;
    }
  });
  
  fs.mkdirSync(path.dirname(dtsPath), { recursive: true });
  fs.writeFileSync(dtsPath, content, 'utf-8');
  console.log(`Generated .d.ts: ${dtsPath}`);
  return dtsPath;
}
