// WaveDrom の JSON を SVG にする
//   使い方: node render_wavedrom.js <入力.json> <出力.svg>
//   準備  : npm install wavedrom(NODE_PATH に node_modules を指定してもよい)
'use strict';
const fs = require('fs');
const wavedrom = require('wavedrom');
const src = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const res = wavedrom.renderAny(0, src, wavedrom.waveSkin);
fs.writeFileSync(process.argv[3], wavedrom.onml.stringify(res));
