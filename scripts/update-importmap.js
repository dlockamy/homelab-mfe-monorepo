#!/usr/bin/env node
// Point one import-map specifier at a new target, in place.
//   usage: update-importmap.js <importmap.json> <specifier> <target-path>
const fs = require('fs');

const [file, specifier, target] = process.argv.slice(2);
if (!file || !specifier || !target) {
  console.error('usage: update-importmap.js <importmap.json> <specifier> <target-path>');
  process.exit(2);
}

const data = JSON.parse(fs.readFileSync(file, 'utf8'));
data.imports = data.imports || {};
data.imports[specifier] = target;
fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
console.log(`importmap: ${specifier} -> ${target}`);
