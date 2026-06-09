#!/bin/bash
set -e

echo "📁 Creating Exita project structure..."

# Create subdirectories (if not already)
mkdir -p src/{parser,transforms,generator,utils}
mkdir -p test
mkdir -p examples

# ──────────────────────────────────────────
# package.json
# ──────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "exita-compiler",
  "version": "0.1.0",
  "description": "Exita compiler – Phase 1",
  "main": "dist/index.js",
  "bin": { "exita": "./dist/cli.js" },
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch",
    "start": "node dist/cli.js",
    "test": "echo \"No tests yet\""
  },
  "dependencies": {
    "@babel/generator": "^7.23.6",
    "@babel/parser": "^7.23.6",
    "@babel/traverse": "^7.23.6",
    "@babel/types": "^7.23.6",
    "commander": "^11.1.0",
    "glob": "^10.3.10"
  },
  "devDependencies": {
    "@types/babel__generator": "^7.6.4",
    "@types/babel__parser": "^7.1.1",
    "@types/babel__traverse": "^7.20.1",
    "@types/node": "^20.10.0",
    "typescript": "^5.3.2"
  }
}
EOF

# ──────────────────────────────────────────
# tsconfig.json
# ──────────────────────────────────────────
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationDir": "dist/types"
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist", "test", "examples"]
}
EOF

# ──────────────────────────────────────────
# src/types.ts – Shared type definitions
# ──────────────────────────────────────────
cat > src/types.ts << 'EOF'
export interface ExitaModule {
  name: string;
  headerPath: string;   // e.g. "Button.hxj"
  sourcePath: string;    // full path to .exj
  exports: ExitaExport[];
}

export interface ExitaExport {
  kind: 'function' | 'variable' | 'interface';
  name: string;
  typeAnnotation?: string;
  params?: ExitaParam[];
  returnType?: string;
  isSignal?: boolean;
  defaultValues?: Record<string, string>; // parameter name -> default expression
}

export interface ExitaParam {
  name: string;
  typeAnnotation?: string;
  defaultValue?: string;
}

export interface CompilerOptions {
  entry: string;
  outDir: string;
  generateHeaders: boolean;
  watch: boolean;
}
EOF

# ──────────────────────────────────────────
# src/utils/ast-helpers.ts
# ──────────────────────────────────────────
cat > src/utils/ast-helpers.ts << 'EOF'
import * as t from '@babel/types';

export function isExitaComponent(node: t.Node): node is t.FunctionDeclaration | t.FunctionExpression | t.ArrowFunctionExpression {
  if (t.isFunctionDeclaration(node) || t.isFunctionExpression(node) || t.isArrowFunctionExpression(node)) {
    // A component is a function that returns JSX or calls createElement
    // For simplicity, any function that starts with uppercase is a component
    if (node.id && /^[A-Z]/.test(node.id.name)) return true;
    // Also allow anonymous arrow functions assigned to variables starting with uppercase
    if (t.isVariableDeclarator(node as any) && t.isIdentifier((node as any).id) && /^[A-Z]/.test(((node as any).id as t.Identifier).name)) return true;
    return false;
  }
  return false;
}

export function extractAddModule(statement: t.Statement): { headerPath: string } | null {
  if (
    t.isExpressionStatement(statement) &&
    t.isCallExpression(statement.expression) &&
    t.isMemberExpression(statement.expression.callee) &&
    t.isIdentifier(statement.expression.callee.object, { name: 'Add' }) &&
    t.isIdentifier(statement.expression.callee.property, { name: 'Module' }) &&
    statement.expression.arguments.length === 1 &&
    t.isStringLiteral(statement.expression.arguments[0])
  ) {
    return { headerPath: statement.expression.arguments[0].value };
  }
  return null;
}

export function findExports(ast: t.File): t.ExportDeclaration[] {
  return ast.program.body.filter(
    (node): node is t.ExportDeclaration =>
      t.isExportNamedDeclaration(node) || t.isExportDefaultDeclaration(node) || t.isExportAllDeclaration(node)
  );
}
EOF

# ──────────────────────────────────────────
# src/parser/exita-parser.ts
# ──────────────────────────────────────────
cat > src/parser/exita-parser.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import { ExitaModule, ExitaExport, ExitaParam } from '../types';
import { extractAddModule, findExports } from '../utils/ast-helpers';

export function parseExitaFile(filePath: string): ExitaModule {
  const code = fs.readFileSync(filePath, 'utf-8');
  const ast = parse(code, {
    sourceType: 'module',
    plugins: ['jsx', 'typescript'],
  });

  const moduleInfo: ExitaModule = {
    name: path.basename(filePath, '.exj'),
    headerPath: '',
    sourcePath: filePath,
    exports: [],
  };

  // Find Add.Module statements (both declaration and imports)
  const addModuleStatements: string[] = [];
  ast.program.body.forEach(stmt => {
    const add = extractAddModule(stmt);
    if (add) addModuleStatements.push(add.headerPath);
  });

  if (addModuleStatements.length > 0) {
    // The first Add.Module is the declaration (e.g., Add.Module [Button.hxj])
    moduleInfo.headerPath = addModuleStatements[0];
  }

  // Traverse AST to find exports
  traverse(ast, {
    ExportNamedDeclaration(path) {
      const declaration = path.node.declaration;
      if (!declaration) return;
      if (t.isFunctionDeclaration(declaration) && declaration.id) {
        const exp: ExitaExport = {
          kind: 'function',
          name: declaration.id.name,
          params: declaration.params.map(param => extractParam(param)),
          returnType: declaration.returnType ? getTypeAnnotationSource(declaration.returnType.typeAnnotation, code) : undefined,
        };
        moduleInfo.exports.push(exp);
      } else if (t.isVariableDeclaration(declaration)) {
        declaration.declarations.forEach(declarator => {
          if (t.isIdentifier(declarator.id)) {
            const exp: ExitaExport = {
              kind: 'variable',
              name: declarator.id.name,
              typeAnnotation: declarator.id.typeAnnotation ? getTypeAnnotationSource(declarator.id.typeAnnotation.typeAnnotation, code) : undefined,
            };
            moduleInfo.exports.push(exp);
          }
        });
      }
    },
    ExportDefaultDeclaration(path) {
      // Handle default export (simplified)
      const declaration = path.node.declaration;
      if (t.isFunctionDeclaration(declaration) && declaration.id) {
        moduleInfo.exports.push({
          kind: 'function',
          name: 'default',
          params: declaration.params.map(param => extractParam(param)),
        });
      } else if (t.isIdentifier(declaration)) {
        moduleInfo.exports.push({
          kind: 'variable',
          name: declaration.name,
        });
      }
    },
  });

  return moduleInfo;
}

function extractParam(param: t.Identifier | t.Pattern | t.RestElement): ExitaParam {
  if (t.isIdentifier(param)) {
    return {
      name: param.name,
      typeAnnotation: param.typeAnnotation ? getTypeAnnotationSource(param.typeAnnotation.typeAnnotation, '') : undefined,
    };
  }
  if (t.isAssignmentPattern(param) && t.isIdentifier(param.left)) {
    return {
      name: param.left.name,
      defaultValue: param.right ? getSourceFromNode(param.right) : undefined,
    };
  }
  return { name: 'unknown' };
}

function getTypeAnnotationSource(node: t.Node, code: string): string {
  if (!node) return 'any';
  // Attempt to extract original source from code slice (simplistic)
  // For now return basic mapping
  if (t.isTSStringKeyword(node)) return 'string';
  if (t.isTSNumberKeyword(node)) return 'number';
  if (t.isTSBooleanKeyword(node)) return 'boolean';
  if (t.isTSAnyKeyword(node)) return 'any';
  if (t.isTSUnionType(node)) {
    return node.types.map(t => getTypeAnnotationSource(t, code)).join(' | ');
  }
  if (t.isTSLiteralType(node)) {
    return node.literal.raw || String(node.literal.value);
  }
  return 'any';
}

function getSourceFromNode(node: t.Node): string {
  if (t.isStringLiteral(node)) return `"${node.value}"`;
  if (t.isNumericLiteral(node)) return String(node.value);
  if (t.isBooleanLiteral(node)) return String(node.value);
  return node.type; // fallback
}
EOF

# ──────────────────────────────────────────
# src/transforms/signal-transform.ts
# ──────────────────────────────────────────
cat > src/transforms/signal-transform.ts << 'EOF'
import * as t from '@babel/types';
import generate from '@babel/generator';

/**
 * Transforms `let` variable declarations inside component functions
 * into reactive signals using a Proxy-based approach.
 * 
 * Simplistic implementation for Phase 1:
 * Replaces `let x = initialValue;` with:
 *   const _signal_x = __exita_signal(initialValue);
 * And all references to `x` within the component body become `_signal_x.value`.
 * Actually, we'll simulate signal behavior by wrapping in a function that creates a closure with getter/setter.
 * But to keep it compile-time, we convert to a Proxy-like object.
 * 
 * For now, let's just tag them as signals for .hxj generation and leave runtime transformation
 * to the second phase. We'll instead annotate the AST to mark signal variables.
 */
export function transformSignals(ast: t.File): void {
  // This transform will be expanded in Phase 2.
  // Currently, we identify signal variables (let declarations) and mark them
  // so the .hxj generator can include __signals.
  // The actual runtime transformation will be done by the bundler.
  console.log('Signal transform: identifying signals...');
  // TODO: Real transform will replace let with signal constructors.
}
EOF

# ──────────────────────────────────────────
# src/generator/hxj-generator.ts
# ──────────────────────────────────────────
cat > src/generator/hxj-generator.ts << 'EOF'
import * as fs from 'fs';
import * as path from 'path';
import { ExitaModule, ExitaExport } from '../types';

export function generateHeader(module: ExitaModule, outDir: string): string {
  const headerPath = path.join(outDir, module.headerPath || `${module.name}.hxj`);
  
  let content = `// ${module.headerPath} - AUTO-GENERATED, DO NOT EDIT MANUALLY
Add.Module [${path.basename(module.sourcePath)}]

`;

  // Generate interfaces and type exports
  module.exports.forEach(exp => {
    if (exp.kind === 'function') {
      content += `export declare function ${exp.name}(`;
      if (exp.params && exp.params.length > 0) {
        content += exp.params.map(p => {
          let paramStr = p.name;
          if (p.typeAnnotation) paramStr += `: ${p.typeAnnotation}`;
          if (p.defaultValue) paramStr += ` = ${p.defaultValue}`;
          return paramStr;
        }).join(', ');
      }
      content += `): ${exp.returnType || 'JSXElement'}\n\n`;
    } else if (exp.kind === 'variable') {
      content += `export declare const ${exp.name}: ${exp.typeAnnotation || 'any'}\n\n`;
    } else if (exp.kind === 'interface') {
      content += `export interface ${exp.name} { /* inferred */ }\n\n`;
    }
  });

  // If any signal variables were found, export __signals
  // In Phase 1, we just check if any export has isSignal flag (unset currently)
  content += `// Optional: exported signals for external optimization\n`;
  content += `export declare const __signals: string[]\n`;

  fs.mkdirSync(path.dirname(headerPath), { recursive: true });
  fs.writeFileSync(headerPath, content, 'utf-8');
  console.log(`Generated header: ${headerPath}`);
  return headerPath;
}
EOF

# ──────────────────────────────────────────
# src/index.ts – Main compiler entry
# ──────────────────────────────────────────
cat > src/index.ts << 'EOF'
import { parseExitaFile } from './parser/exita-parser';
import { generateHeader } from './generator/hxj-generator';
import * as fs from 'fs';
import * as path from 'path';
import { globSync } from 'glob';

export interface BuildOptions {
  entry: string;
  outDir: string;
  generateHeaders?: boolean;
}

export function build(options: BuildOptions) {
  const { entry, outDir, generateHeaders: genHeaders = true } = options;
  const files = globSync(entry);
  
  if (files.length === 0) {
    console.error(`No .exj files found matching pattern: ${entry}`);
    return;
  }

  files.forEach(file => {
    console.log(`Compiling ${file}...`);
    const moduleInfo = parseExitaFile(file);
    
    if (genHeaders) {
      generateHeader(moduleInfo, outDir);
    }
    
    // In Phase 2, we would also emit the transformed .js file
    console.log(`  -> ${moduleInfo.exports.length} exports found`);
  });

  console.log('Build completed.');
}

// Additional functions like watch mode can be added later
EOF

# ──────────────────────────────────────────
# src/cli.ts – Command-line interface
# ──────────────────────────────────────────
cat > src/cli.ts << 'EOF'
#!/usr/bin/env node
import { Command } from 'commander';
import { build } from './index';

const program = new Command();

program
  .name('exita')
  .description('Exita compiler CLI – Phase 1')
  .version('0.1.0');

program
  .command('build')
  .description('Compile .exj files and generate .hxj headers')
  .option('-e, --entry <pattern>', 'File pattern for .exj files', 'src/**/*.exj')
  .option('-o, --outDir <dir>', 'Output directory for headers', 'headers')
  .action((options) => {
    build({
      entry: options.entry,
      outDir: options.outDir,
    });
  });

// Placeholder for future commands
program
  .command('check-breaking <header> <version>')
  .description('Check for breaking changes (Phase 3)')
  .action(() => {
    console.log('Breaking change detection not yet implemented.');
  });

program.parse(process.argv);
EOF

# ──────────────────────────────────────────
# Example files to test
# ──────────────────────────────────────────
cat > examples/Button.exj << 'EOF'
Add.Module [Button.hxj]

function Button({ variant = "primary", size = "md", children }) {
  let isHovering = false

  return (
    <>
      <style>
        {`
          .btn-primary { background: blue; }
          .btn-secondary { background: gray; }
        `}
      </style>
      <button 
        class={`btn-${variant}`}
        onMouseEnter={() => isHovering = true}
        onMouseLeave={() => isHovering = false}
      >
        {children}
      </button>
    </>
  )
}

export { Button }
EOF

cat > examples/App.exj << 'EOF'
Add.Module [App.hxj]
Add.Module [./Button.hxj]

function App() {
  let count = 0

  return (
    <div>
      <h1>Count: {count}</h1>
      <Button variant="secondary" onClick={() => count++}>
        Increment
      </Button>
    </div>
  )
}

export default App
EOF

echo ""
echo "✅ Project files created!"
echo "Now run:"
echo "  npm install"
echo "  npm run build"
echo "  node dist/cli.js build --entry 'examples/*.exj' --outDir headers"
