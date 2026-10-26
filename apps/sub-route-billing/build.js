const fs = require('fs');
const path = require('path');

const srcFile = path.join(__dirname, 'src', 'main.js');
const distDir = path.join(__dirname, 'dist');
const distFile = path.join(distDir, 'main.js');

if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir);
}

// Read the source app file and mimic a bundle process by stripping local imports 
// so the browser treats it as a standard standalone execution layer
let code = fs.readFileSync(srcFile, 'utf8');
code = code.replace("import { SHARED_CONFIG } from '@mfe/shared-contracts';", "const SHARED_CONFIG = { apiEndpoint: 'https://homelab.local' };");

fs.writeFileSync(distFile, code);
console.log('Billing micro-frontend compiled successfully to dist/main.js');
