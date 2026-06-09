import * as fs from 'fs';
import * as path from 'path';
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import generate from '@babel/generator';
import { ExitaModule, ExitaExport, ExitaParam } from '../types';

export function parseExitaFile(filePath: string): ExitaModule {
  const rawCode = fs.readFileSync(filePath, 'utf-8');

  // Extract Add.Module statements
  const addModuleRegex = /Add\.Module\s*\[([^\]]+)\]/g;
  const addModules: string[] = [];
  let match;
  while ((match = addModuleRegex.exec(rawCode)) !== null) {
    addModules.push(match[1].trim());
  }

  // Clean code for Babel
  const cleanCode = rawCode.replace(/Add\.Module\s*\[[^\]]+\]\s*;?\n?/g, '');

  const ast = parse(cleanCode, {
    sourceType: 'module',
    plugins: ['jsx', 'typescript'],
  });

  const moduleInfo: ExitaModule = {
    name: path.basename(filePath, '.exj'),
    headerPath: addModules.length > 0 ? addModules[0] : '',
    sourcePath: filePath,
    exports: [],
  };

  // First, grab explicit exports (if any) – still supported for compatibility
  traverse(ast, {
    ExportNamedDeclaration(path) {
      const declaration = path.node.declaration;
      if (!declaration) return;
      if (t.isFunctionDeclaration(declaration) && declaration.id) {
        addExportIfNotExists(moduleInfo, {
          kind: 'function',
          name: declaration.id.name,
          params: declaration.params.map(param => extractParam(param)),
          returnType: declaration.returnType && t.isTSTypeAnnotation(declaration.returnType)
            ? getTypeAnnotationSource(declaration.returnType.typeAnnotation)
            : undefined,
        });
      } else if (t.isVariableDeclaration(declaration)) {
        declaration.declarations.forEach(declarator => {
          if (t.isIdentifier(declarator.id)) {
            addExportIfNotExists(moduleInfo, {
              kind: 'variable',
              name: declarator.id.name,
              typeAnnotation: declarator.id.typeAnnotation && t.isTSTypeAnnotation(declarator.id.typeAnnotation)
                ? getTypeAnnotationSource(declarator.id.typeAnnotation.typeAnnotation)
                : undefined,
            });
          }
        });
      }
    },
    ExportDefaultDeclaration(path) {
      const declaration = path.node.declaration;
      if (t.isFunctionDeclaration(declaration) && declaration.id) {
        addExportIfNotExists(moduleInfo, {
          kind: 'function',
          name: 'default',
          params: declaration.params.map(param => extractParam(param)),
        });
      } else if (t.isIdentifier(declaration)) {
        addExportIfNotExists(moduleInfo, {
          kind: 'variable',
          name: declaration.name,
        });
      }
    },
  });

  // Now, if file declares a module (has Add.Module), auto-export all top-level
  // named functions and component variables as implicit exports
  if (addModules.length > 0) {
    ast.program.body.forEach(stmt => {
      if (t.isFunctionDeclaration(stmt) && stmt.id && /^[A-Z]/.test(stmt.id.name)) {
        addExportIfNotExists(moduleInfo, {
          kind: 'function',
          name: stmt.id.name,
          params: stmt.params.map(extractParam),
          returnType: stmt.returnType && t.isTSTypeAnnotation(stmt.returnType)
            ? getTypeAnnotationSource(stmt.returnType.typeAnnotation)
            : undefined,
        });
      } else if (t.isVariableDeclaration(stmt)) {
        stmt.declarations.forEach(declarator => {
          if (
            t.isIdentifier(declarator.id) &&
            /^[A-Z]/.test(declarator.id.name) &&
            declarator.init &&
            (t.isArrowFunctionExpression(declarator.init) || t.isFunctionExpression(declarator.init))
          ) {
            addExportIfNotExists(moduleInfo, {
              kind: 'function', // treat as component
              name: declarator.id.name,
              params: declarator.init.params.map(extractParam),
              returnType: declarator.init.returnType && t.isTSTypeAnnotation(declarator.init.returnType)
                ? getTypeAnnotationSource(declarator.init.returnType.typeAnnotation)
                : undefined,
            });
          }
        });
      }
    });
  }

  return moduleInfo;
}

// Helper: add export if no export with the same name already exists
function addExportIfNotExists(module: ExitaModule, newExport: ExitaExport) {
  if (!module.exports.some(e => e.name === newExport.name && e.kind === newExport.kind)) {
    module.exports.push(newExport);
  }
}

function extractParam(param: t.Identifier | t.Pattern | t.RestElement): ExitaParam {
  if (t.isIdentifier(param)) {
    return {
      name: param.name,
      typeAnnotation: param.typeAnnotation && t.isTSTypeAnnotation(param.typeAnnotation)
        ? getTypeAnnotationSource(param.typeAnnotation.typeAnnotation)
        : undefined,
    };
  }
  if (t.isAssignmentPattern(param) && t.isIdentifier(param.left)) {
    return {
      name: param.left.name,
      defaultValue: param.right ? generate(param.right).code : undefined,
    };
  }
  return { name: 'unknown' };
}

function getTypeAnnotationSource(node: t.Node): string {
  if (!node) return 'any';
  return generate(node).code.trim();
}
