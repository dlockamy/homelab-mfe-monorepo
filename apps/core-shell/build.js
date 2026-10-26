const fs = require('fs');
const path = require('path');

const srcFile = path.join(__dirname, 'src', 'index.html');
const distDir = path.join(__dirname, 'dist');
const distFile = path.join(distDir, 'index.html');

if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir);
}

fs.copyFileSync(srcFile, distFile);
console.log('Core shell app compiled successfully to dist/index.html');
