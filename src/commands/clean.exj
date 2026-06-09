import * as fs from 'fs';
import * as path from 'path';

export function cleanProject() {
  const distPath = path.join(process.cwd(), 'dist');
  const lockPath = path.join(process.cwd(), 'exitapkg.json.lock');

  if (fs.existsSync(distPath)) {
    fs.rmSync(distPath, { recursive: true, force: true });
    console.log('🧹 Removed dist/');
  }

  if (fs.existsSync(lockPath)) {
    fs.unlinkSync(lockPath);
    console.log('🧹 Removed exitapkg.json.lock');
  }

  console.log('✅ Cleaned.');
}
