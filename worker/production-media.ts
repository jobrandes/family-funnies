import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
// No family API, generic database operations, URL fetching, or stored client secret.
// A connector-issued, single-use capability permits exactly one object transfer.
Deno.serve(async req=>{
 if(!['GET','POST'].includes(req.method))return new Response('Method not allowed',{status:405});
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
 if(!token||!/^[a-f0-9]{64}$/.test(token))return new Response('Unauthorized',{status:401});
 try{
  let bytes:Uint8Array|undefined;
  if(req.method==='POST'){
   const length=Number(req.headers.get('content-length'));
   if(!Number.isFinite(length)||length<8||length>12*1024*1024)return new Response('PNG maximum 12MB',{status:413});
   const reader=req.body?.getReader();if(!reader)return new Response('PNG required',{status:400});
   const chunks:Uint8Array[]=[];let total=0;
   while(true){const r=await reader.read();if(r.done)break;total+=r.value.length;if(total>12*1024*1024){await reader.cancel();return new Response('Too large',{status:413})}chunks.push(r.value)}
   bytes=new Uint8Array(total);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length}
   if(![137,80,78,71,13,10,26,10].every((v,i)=>bytes![i]===v))return new Response('PNG required',{status:400});
  }
  const keys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');
  const db=createClient(Deno.env.get('SUPABASE_URL')!,keys.default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:permit,error}=await db.rpc('consume_media_permit',{token,requested_operation:req.method==='POST'?'upload':'download'});
  if(error||!permit)return new Response('Unauthorized',{status:401});
  if(req.method==='GET'){
   const {data,error}=await db.storage.from(permit.bucket).download(permit.path);
   if(error)return new Response('Image unavailable',{status:404});
   return new Response(data,{headers:{'Content-Type':data.type||'image/png','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
  }
  const {error:uploadError}=await db.storage.from(permit.bucket).upload(permit.path,bytes!,{contentType:'image/png',upsert:false});
  if(uploadError)return new Response('Upload failed',{status:409});
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes!)),v=>v.toString(16).padStart(2,'0')).join('');
  return Response.json({path:permit.path,bytes:bytes!.length,sha256:digest},{headers:{'Cache-Control':'no-store'}});
 }catch{return new Response('Transfer failed',{status:500});}
});
