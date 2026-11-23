import {MAX_PDF_BYTES,MAX_PDF_PAGES} from './invoice-core.js';
const asset=name=>new URL(`./vendor/invoice/${name}`,import.meta.url).href;
export function textRows(items){
 const rows=[];
 for(const item of items){
  if(!item.str?.trim())continue;
  const y=item.transform[5],x=item.transform[4];
  let row=rows.find(r=>Math.abs(r.y-y)<3);
  if(!row){row={y,parts:[]};rows.push(row);}row.parts.push({x,text:item.str});
 }
 return rows.sort((a,b)=>b.y-a.y).map(r=>r.parts.sort((a,b)=>a.x-b.x).map(p=>p.text).join(' ')).join('\n');
}
export async function inspectPdf(file){
 if(!file||file.size===0||file.size>MAX_PDF_BYTES)throw new Error('Choose a PDF between 1 byte and 20 MB.');
 if(!file.name.toLowerCase().endsWith('.pdf'))throw new Error('Only PDF invoices are supported.');
 const bytes=new Uint8Array(await file.arrayBuffer());
 if(!new TextDecoder('ascii').decode(bytes.slice(0,1024)).includes('%PDF-'))throw new Error('This file is not a valid PDF.');
 const hash=await crypto.subtle.digest('SHA-256',bytes);
 return {bytes,name:file.name,size:file.size,sha256:[...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,'0')).join('')};
}
export async function scanPdf(file,{signal,progress=()=>{},forceOcr=false}={}){
 let task,doc,worker,pendingWorker,renderTask,stopped=false;
 const abort=()=>{stopped=true;renderTask?.cancel();task?.destroy();worker?.terminate();};
 const check=()=>{if(signal?.aborted)throw new DOMException('Scanning cancelled','AbortError');};
 const bounded=async(promise,milliseconds=120000)=>{
  let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>{abort();reject(new Error('This page took too long to scan. Try a smaller or clearer PDF.'));},milliseconds);})]);}finally{clearTimeout(timer);}
 };
 signal?.addEventListener('abort',abort,{once:true});
 try{
  check();progress('Opening PDF…');
  const pdf=await import('./vendor/invoice/pdf.min.mjs');
  pdf.GlobalWorkerOptions.workerSrc=asset('pdf.worker.min.mjs');
  pdf.GlobalWorkerOptions.rendererSrc=asset('pdf.renderer.min.mjs');
  task=pdf.getDocument({data:file.bytes.slice(),isEvalSupported:false,enableXfa:false,maxImageSize:16000000,wasmUrl:asset('wasm/'),standardFontDataUrl:asset('standard_fonts/')});
  doc=await bounded(task.promise,30000);check();
  if(doc.numPages>MAX_PDF_PAGES)throw new Error(`Upload at most ${MAX_PDF_PAGES} pages per invoice. Split supporting documents before uploading.`);
  const pages=[];
  for(let n=1;n<=doc.numPages;n++){
   check();progress(`Reading page ${n} of ${doc.numPages}…`);
   const page=await bounded(doc.getPage(n)),content=await bounded(page.getTextContent());
   const base=page.getViewport({scale:1});
   const scale=Math.min(3,1800/Math.max(base.width,base.height));
   const viewport=page.getViewport({scale}),canvas=document.createElement('canvas');
   canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);
   renderTask=page.render({canvasContext:canvas.getContext('2d',{willReadFrequently:true}),viewport});await bounded(renderTask.promise);renderTask=null;
   let text=textRows(content.items),method='text',confidence=null;
   if(forceOcr||text.replace(/\s/g,'').length<40){
    progress(`Preparing English OCR for page ${n}…`);
    if(!worker){
     const {default:Tesseract}=await import('./vendor/invoice/tesseract.esm.min.js');
     pendingWorker=Tesseract.createWorker('eng',1,{workerPath:asset('worker.min.js'),corePath:asset('core/'),langPath:asset('lang'),workerBlobURL:false,gzip:true,logger:m=>{if(!signal?.aborted)progress(`OCR page ${n} of ${doc.numPages}: ${m.status}${m.progress>=0?' '+Math.round(m.progress*100)+'%':''}`);}});
     pendingWorker.then(w=>{if(stopped||signal?.aborted)w.terminate();},()=>{});
     worker=await bounded(pendingWorker);await worker.setParameters({preserve_interword_spaces:'1'});
    }
    check();const result=await bounded(worker.recognize(canvas));text=result.data.text;confidence=result.data.confidence;method='ocr';
   }
   check();const thumb=document.createElement('canvas');thumb.width=700;thumb.height=Math.ceil(canvas.height*700/canvas.width);thumb.getContext('2d').drawImage(canvas,0,0,thumb.width,thumb.height);
   pages.push({number:n,text,method,confidence,preview:thumb.toDataURL('image/jpeg',.8)});
   canvas.width=canvas.height=0;page.cleanup();
  }
  const methods=new Set(pages.map(p=>p.method));
  return {pages,text:pages.map(p=>p.text).join('\n\n'),method:methods.size>1?'mixed':pages[0].method};
 }catch(error){
  if(error.name==='PasswordException')throw new Error('This PDF is password protected. Upload an unlocked copy.');
  if(error.name==='InvalidPDFException')throw new Error('The PDF could not be read. Try exporting a fresh copy.');
  throw error;
 }finally{stopped=true;signal?.removeEventListener('abort',abort);await worker?.terminate();await task?.destroy();}
}
