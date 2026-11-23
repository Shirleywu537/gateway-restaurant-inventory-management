import {createServer} from 'node:http';
import {execFile} from 'node:child_process';
import {readFile,stat} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
const root=resolve(new URL('../dist/',import.meta.url).pathname);
const mime={'.html':'text/html','.css':'text/css','.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm','.pdf':'application/pdf','.gz':'application/gzip','.svg':'image/svg+xml','.png':'image/png'};
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');const requested=decodeURIComponent(url.pathname);const file=resolve(root,'.'+(requested==='/'?'/index.html':requested));if(!file.startsWith(root+sep)){res.writeHead(403);res.end();return;}if(!(await stat(file)).isFile())throw Error('Not found');res.writeHead(200,{'Content-Type':`${mime[extname(file)]||'application/octet-stream'}; charset=utf-8`,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(await readFile(file));}catch{res.writeHead(404);res.end('Not found');}});
server.on('error',error=>{console.error(error.code==='EADDRINUSE'?'The website is already running. Open http://127.0.0.1:4173 in your browser.':error.message);process.exitCode=1;});
server.listen(4173,'127.0.0.1',()=>{console.log('Local: http://127.0.0.1:4173');if(process.argv.includes('--open')&&process.platform==='darwin')execFile('open',['http://127.0.0.1:4173']);});
