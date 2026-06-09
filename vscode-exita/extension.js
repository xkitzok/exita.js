const { LanguageClient } = require('vscode-languageclient/node');

function activate(context) {
  const serverModule = context.asAbsolutePath('../lsp-package/server.js');
  const client = new LanguageClient('exita', 'Exita Language Server', { run: { module: serverModule, transport: { kind: 'stdio' } }, debug: { module: serverModule, transport: { kind: 'stdio' } } }, { documentSelector: [{ language: 'exj' }] });
  client.start();
}
exports.activate = activate;
