import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export function updateExita() {
  const repoUrl = 'https://github.com/xkitzok/exita.js';
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'exita-update-'));

  try {
    console.log('⬇️  Cloning latest Exita...');
    execSync(`git clone --depth 1 ${repoUrl} ${tempDir}`, { stdio: 'inherit' });
    execSync('npm install', { cwd: tempDir, stdio: 'inherit' });
    execSync('npm run build', { cwd: tempDir, stdio: 'inherit' });

    // Find current Exita package root (above dist/commands)
    const packageRoot = path.resolve(__dirname, '../..');

    console.log(`Updating Exita in ${packageRoot}...`);
    // Copy the new dist and node_modules
    execSync(`cp -r ${path.join(tempDir, 'dist')} ${packageRoot}`);
    execSync(`cp -r ${path.join(tempDir, 'node_modules')} ${packageRoot}`);
    console.log('✅ Exita updated to the latest version!');
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}
