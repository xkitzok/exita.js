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
  Diagnostic,
  DiagnosticSeverity,
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { parseExitaFile } from '../dist/parser/exita-parser';  // use compiled parser
import * as path from 'path';
import * as fs from 'fs';

const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

connection.onInitialize((params: InitializeParams) => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: { resolveProvider: true },
    },
  };
});

// Provide diagnostics (errors/warnings) from compiler
documents.onDidChangeContent(async (change) => {
  const doc = change.document;
  if (!doc.uri.endsWith('.exj')) return;

  try {
    // Write the document content to a temp file and parse it
    const tmpFile = path.join('/tmp', path.basename(doc.uri));
    fs.writeFileSync(tmpFile, doc.getText());
    const moduleInfo = parseExitaFile(tmpFile);
    // No errors = empty diagnostics; in future we'll collect real errors
    const diagnostics: Diagnostic[] = [];
    connection.sendDiagnostics({ uri: doc.uri, diagnostics });
  } catch (e: any) {
    connection.sendDiagnostics({
      uri: doc.uri,
      diagnostics: [{
        severity: DiagnosticSeverity.Error,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        message: e.message,
      }],
    });
  }
});

// Completions from .hxj headers in the workspace
connection.onCompletion((params) => {
  // Scan workspace for .hxj files and provide exports
  const completions: CompletionItem[] = [];
  // Dummy completions – real implementation would read .hxj from disk
  completions.push({ label: 'Button', kind: CompletionItemKind.Class });
  completions.push({ label: 'Add.Module', kind: CompletionItemKind.Snippet });
  return completions;
});

documents.listen(connection);
connection.listen();
