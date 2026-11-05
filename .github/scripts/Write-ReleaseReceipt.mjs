import {resolve} from 'node:path';
import {runReceipt} from './wss-ci/receipt.mjs';
if(process.argv.length!==6) throw new Error('Four trusted workspace paths are required');
const [sourceRoot,toolsRoot,contractRoot,outputRoot]=process.argv.slice(2).map(x=>resolve(x));
await runReceipt({sourceRoot,toolsRoot,contractRoot,outputRoot});
