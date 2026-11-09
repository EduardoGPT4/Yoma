const fs = require('fs');
let script = fs.readFileSync(require('node:path').join(__dirname, '../android/app/src/main/assets/native-integration.js'), 'utf8');
script = script.replace('/*YOMA_ANIME_BRAND*/', JSON.stringify('data:image/png;base64,fixture')).replace('/*YOMA_NATIVE_LAYOUT*/', JSON.stringify(''));
new Function(script);
console.log('Sintaxis del script nativo verificada.');
