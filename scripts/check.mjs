import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
async function walk(directory) {
  const values = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (['runtime', 'dist', 'test-results', '.git', 'node_modules'].includes(entry.name)) continue;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) values.push(...await walk(file)); else values.push(file);
  }
  return values;
}
const files = await walk(root);
for (const file of files) {
  if (file.endsWith('.json')) JSON.parse(await fs.readFile(file, 'utf8'));
  if (file.endsWith('.mjs')) {
    const result = spawnSync(process.execPath, ['--check', file], { windowsHide: true, encoding: 'utf8' });
    if (result.status !== 0) throw new Error(result.stderr || `Syntax failed: ${file}`);
  }
  if (file.endsWith('.ps1')) {
    const bytes = await fs.readFile(file);
    if (bytes[0] !== 0xef || bytes[1] !== 0xbb || bytes[2] !== 0xbf) throw new Error(`PowerShell 5.1 requires UTF-8 BOM: ${file}`);
  }
}
const manifest = JSON.parse(await fs.readFile(path.join(root, '.codex-plugin/plugin.json'), 'utf8'));
const pkg = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'));
if (manifest.version !== pkg.version) throw new Error('Plugin/package versions differ');
console.log(`PASS: ${files.length} source files, JSON manifests, JavaScript syntax, PowerShell encoding.`);
