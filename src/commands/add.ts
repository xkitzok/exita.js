import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

export function addPackage(packageName: string) {
  const cwd = process.cwd();
  const exitapkgPath = path.join(cwd, 'exitapkg.json');
  if (!fs.existsSync(exitapkgPath)) {
    console.error('No exitapkg.json found. Run `exita init` first.');
    return;
  }

  const exitapkg = JSON.parse(fs.readFileSync(exitapkgPath, 'utf-8'));
  exitapkg.dependencies = exitapkg.dependencies || {};
  exitapkg.dependencies[packageName] = '*';
  fs.writeFileSync(exitapkgPath, JSON.stringify(exitapkg, null, 2));

  // Create a temporary package.json for npm compatibility
  const pkgJson = {
    name: exitapkg.name,
    version: exitapkg.version,
    dependencies: exitapkg.dependencies,
    devDependencies: exitapkg.devDependencies,
  };
  fs.writeFileSync(path.join(cwd, 'package.json'), JSON.stringify(pkgJson, null, 2));

  try {
    console.log(`Installing ${packageName}...`);
    execSync(`npm install --save ${packageName}`, { stdio: 'inherit', cwd });

    // Rename lock file to exitapkg.json.lock
    if (fs.existsSync(path.join(cwd, 'package-lock.json'))) {
      fs.copyFileSync(
        path.join(cwd, 'package-lock.json'),
        path.join(cwd, 'exitapkg.json.lock')
      );
      fs.unlinkSync(path.join(cwd, 'package-lock.json'));
    }
    console.log(`✅ Added ${packageName}`);
  } finally {
    // Clean up the temporary package.json
    if (fs.existsSync(path.join(cwd, 'package.json'))) {
      fs.unlinkSync(path.join(cwd, 'package.json'));
    }
  }
}
