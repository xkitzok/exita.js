#!/bin/bash
set -e

echo "🔧 Fixing module resolution & LSP errors, rebuilding"

# ── 1. Update tsconfig.json to support Node16 module resolution ──
cat > tsconfig.json << 'TS_EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020", "DOM"],
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationDir": "dist/types",
    "moduleResolution": "node16"
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist", "test", "examples"]
}
TS_EOF

# ── 2. Fix LSP server with proper types ──
cat > src/lsp/server.ts << 'LS_EOF'
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  DidChangeConfigurationNotification,
  CompletionItem,
  CompletionItemKind,
  TextDocumentSyncKind,
  InitializeResult,
  WorkspaceFolder,
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { parseExitaFile } from '../parser/exita-parser';

const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;

connection.onInitialize((params: InitializeParams) => {
  const capabilities = params.capabilities;

  hasConfigurationCapability = !!(capabilities.workspace && !!capabilities.workspace.configuration);
  hasWorkspaceFolderCapability = !!(capabilities.workspace && !!capabilities.workspace.workspaceFolders);

  const result: InitializeResult = {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: {
        resolveProvider: true,
      },
    },
  };
  if (hasWorkspaceFolderCapability) {
    result.capabilities.workspace = {
      workspaceFolders: { supported: true },
    };
  }
  return result;
});

connection.onInitialized(() => {
  if (hasConfigurationCapability) {
    connection.client.register(DidChangeConfigurationNotification.type, undefined);
  }
  if (hasWorkspaceFolderCapability) {
    connection.workspace.onDidChangeWorkspaceFolders((_event: any) => {
      connection.console.log('Workspace folder change event received.');
    });
  }
});

connection.onCompletion(
  (_textDocumentPosition: any): CompletionItem[] => {
    return [
      { label: 'Button', kind: CompletionItemKind.Class, data: 1 },
      { label: 'App', kind: CompletionItemKind.Class, data: 2 },
      { label: 'Add.Module', kind: CompletionItemKind.Snippet, data: 3 },
    ];
  }
);

connection.onCompletionResolve((item: CompletionItem): CompletionItem => {
  if (item.data === 1) {
    item.detail = 'Button component';
    item.documentation = 'A reusable button component from the Exita standard library.';
  }
  return item;
});

documents.listen(connection);
connection.listen();
LS_EOF

# ── 3. Remove the runtime/build-runtime.ts that uses __dirname incorrectly ──
# It's already fixed earlier but let's ensure it uses process.cwd()
cat > src/runtime/build-runtime.ts << 'RUNTIME_EOF'
import * as esbuild from 'esbuild';
import * as path from 'path';

export async function buildRuntime(outDir: string) {
  const projectRoot = process.cwd();
  const runtimeSource = path.join(projectRoot, 'src', 'runtime', 'exita-runtime.ts');
  const outFile = path.join(outDir, 'runtime.js');

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

  console.log('⚡ Optimized runtime built:', outFile);
}
RUNTIME_EOF

# ── 4. Rebuild the whole compiler ──
npm run build

# ── 5. Make sure the dist/runtime.js is generated (exita run will also generate it, but let's pre-generate) ──
node -e "
  const { buildRuntime } = require('./dist/runtime/build-runtime.js');
  buildRuntime('dist');
" || true

# ── 6. Build examples so app.exj.js appears ──
node dist/cli.js build --entry 'examples/*.exj' --outDir dist

echo ""
echo "✅ Fixes applied. Now run:"
echo "   exita run"
