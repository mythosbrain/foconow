import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateAlarmSounds } from './generate-alarm-sounds.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'dist');
const output = path.join(root, 'Apple', 'WebContent');
fs.mkdirSync(output, { recursive: true });
// These controlled modules are bundled as a classic script to run from file://
// in WebKit without private preferences or a local server.
const model = fs.readFileSync(path.join(source, 'model.js'), 'utf8').replace(/^export /gm, '');
const insights = fs.readFileSync(path.join(source, 'insights.js'), 'utf8').replace(/^export /gm, '');
const phoneHistory = fs.readFileSync(path.join(source, 'phone-history.js'), 'utf8').replace(/^export /gm, '');
const phoneUI = fs.readFileSync(path.join(source, 'phone-ui.js'), 'utf8').replace(/^export /gm, '');
const appSource = fs.readFileSync(path.join(source, 'app.js'), 'utf8');
const app = appSource.replace(/^import \{[^\n]+\} from '\.\/(?:model|insights|phone-ui|phone-history)\.js';\n/gm, '');
if (app === appSource || /^\s*(?:import|export) /m.test(app) || /^\s*(?:import|export) /m.test(model)) {
  throw new Error('The native bundler needs updating for the current module structure.');
}
fs.writeFileSync(path.join(output, 'app.bundle.js'), `(()=>{\n'use strict';\n${model}\n${insights}\n${phoneHistory}\n${phoneUI}\n${app}\n})();\n`);
let html = fs.readFileSync(path.join(source, 'index.html'), 'utf8')
  .replace('<script type="module" src="app.js"></script>', '<script defer src="app.bundle.js"></script>');
html = html.replace('<meta name="viewport" content="width=device-width, initial-scale=1">', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">');
fs.writeFileSync(path.join(output, 'index.html'), html);
for (const name of ['styles.css', 'appearance.css', 'premium.css', 'desktop.css', 'noir.css', 'tasks.css', 'controls.css', 'insights.css', 'phone.css', 'controls.js', 'icon.svg']) fs.copyFileSync(path.join(source, name), path.join(output, name));
generateAlarmSounds(output);
console.log(`Prepared offline native assets in ${output}`);
