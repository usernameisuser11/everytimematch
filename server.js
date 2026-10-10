'use strict';
const http=require('node:http');
const path=require('node:path');
const serveHandler=require('serve-handler');
const webpush=require('web-push');

const port=Number(process.env.PORT||8080);
const supabaseUrl=process.env.SUPABASE_URL;
const supabaseKey=process.env.SUPABASE_PUBLISHABLE_KEY;
const workerSecret=process.env.PUSH_WORKER_SECRET;
const publicKey=process.env.VAPID_PUBLIC_KEY;
const privateKey=process.env.VAPID_PRIVATE_KEY;
const pushConfigured=Boolean(supabaseUrl&&supabaseKey&&workerSecret&&publicKey&&privateKey);
let pushEnabled=pushConfigured;
let busy=false;

if(pushConfigured){
  try{
    webpush.setVapidDetails('https://everytimematch-production.up.railway.app',publicKey,privateKey);
  }catch(error){
    pushEnabled=false;
    console.error('Web Push disabled: invalid VAPID configuration:',error.message);
  }
}else{
  console.warn('Web Push disabled: required environment settings missing');
}

async function rpc(name,body){
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),10000);
  try{
    const response=await fetch(supabaseUrl+'/rest/v1/rpc/'+name,{
      method:'POST',
      headers:{apikey:supabaseKey,'Content-Type':'application/json'},
      body:JSON.stringify(body),
      signal:controller.signal
    });
    const raw=await response.text();
    if(!response.ok)throw new Error(name+': HTTP '+response.status+' '+raw.slice(0,280));
    return raw?JSON.parse(raw):null;
  }finally{clearTimeout(timeout);}
}

function trustedPushEndpoint(endpoint){
  try{
    const url=new URL(endpoint);
    if(url.protocol!=='https:'||url.username||url.password||(url.port&&url.port!=='443'))return false;
    const host=url.hostname.toLowerCase();
    return host==='fcm.googleapis.com' ||
      host==='updates.push.services.mozilla.com' ||
      host==='webpush.push.services.mozilla.com' ||
      host==='android.googleapis.com' ||
      host==='push.apple.com' || host.endsWith('.push.apple.com') ||
      host.endsWith('.notify.windows.com');
  }catch(_){return false;}
}

async function deliverPending(){
  if(!pushEnabled||busy)return;
  busy=true;
  try{
    const jobs=await rpc('claim_push_deliveries',{p_secret:workerSecret,p_limit:20});
    for(const job of jobs||[]){
      let result='retry';
      const kind=job.kind==='match'?'match':'message';
      const payload=JSON.stringify({
        title:kind==='match'?'💞 새로운 매칭이 생겼어요':'💬 새로운 메시지가 도착했어요',
        body:kind==='match'?'서로 관심을 보냈어요. 매칭 탭에서 확인해주세요.':'Everytime Match에서 새 메시지를 확인해보세요.',
        url:'/#matches',
        tag:'etmatch-'+kind+'-'+job.reference_id
      });
      try{
        if(!trustedPushEndpoint(job.endpoint)){
          result='gone';
          console.warn('Rejected untrusted push endpoint host');
        }else await webpush.sendNotification({
          endpoint:job.endpoint,
          keys:{p256dh:job.p256dh,auth:job.auth_secret}
        },payload,{TTL:3600,urgency:'normal',timeout:9000});
        result='sent';
      }catch(error){
        if(error.statusCode===404||error.statusCode===410)result='gone';
        console.warn('Push send failed:',error.statusCode||error.message);
      }
      try{
        await rpc('finish_push_delivery',{
          p_secret:workerSecret,
          p_delivery_id:job.delivery_id,
          p_result:result
        });
      }catch(error){console.error('Push delivery finalization failed:',error.message);}
    }
  }catch(error){console.error('Push worker failed:',error.message);}
  finally{busy=false;}
}

const server=http.createServer(async(req,res)=>{
  // Reject invalid request targets instead of allowing a malformed URL to crash Node.
  let pathname;
  try{
    const target=req.url||'/';
    if(!target.startsWith('/')||target.startsWith('//'))throw new Error('Invalid request target');
    pathname=new URL(target,'https://everytimematch.local').pathname;
  }catch(_){
    res.writeHead(400,{'Content-Type':'text/plain; charset=utf-8'});
    res.end('Bad request');
    return;
  }

  if(pathname==='/api/push/public-key'){
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.end(JSON.stringify({enabled:pushEnabled,publicKey:pushEnabled?publicKey:null}));
    return;
  }
  if(pathname==='/api/health'){
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.end(JSON.stringify({ok:true,pushEnabled}));
    return;
  }
  if(!['GET','HEAD'].includes(req.method)){
    res.writeHead(405,{'Content-Type':'text/plain; charset=utf-8'});
    res.end('Method not allowed');
    return;
  }

  // This project is a single-page app. Explicitly serve its entrypoint rather
  // than letting the static server treat '/' (or '/app/') as a directory.
  const isAsset=pathname==='/sw.js'||pathname==='/manifest.webmanifest'||
    /^\/icons\/[a-zA-Z0-9_-]+\.png$/.test(pathname);
  const acceptsHtml=(req.headers.accept||'').includes('text/html');
  const isAppPage=pathname==='/'||pathname==='/index.html'||
    pathname==='/app'||pathname==='/app/'||
    (acceptsHtml&&!path.posix.extname(pathname)&&!pathname.startsWith('/api/'));

  // Never serve repository documents, source code, environment files, or folders.
  if(!isAppPage&&!isAsset){
    res.writeHead(404,{'Content-Type':'text/plain; charset=utf-8'});
    res.end('Not found');
    return;
  }
  req.url=isAppPage?'/index.html':pathname;
  if(isAppPage)res.setHeader('Cache-Control','no-store');
  if(pathname==='/sw.js')res.setHeader('Cache-Control','no-cache');

  try{
    await serveHandler(req,res,{
      public:__dirname,
      directoryListing:false,
      cleanUrls:false
    });
  }catch(error){
    console.error('HTTP request failed:',error.message);
    if(!res.headersSent)res.writeHead(500,{'Content-Type':'text/plain; charset=utf-8'});
    res.end('Internal server error');
  }
});

server.listen(port,'0.0.0.0',()=>{
  console.log('Everytime Match listening on port '+port+', push enabled: '+pushEnabled);
});
setInterval(deliverPending,12000);
setTimeout(deliverPending,2000);
