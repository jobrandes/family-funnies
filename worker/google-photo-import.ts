import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
import {createRemoteJWKSet,jwtVerify} from 'npm:jose@6.1.0';

// Requests run with the signed-in user's Firebase JWT. No administrative key.
const origin='https://family-funnies.pages.dev';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
const reply=(status:number,message:string)=>Response.json({message},{status,headers:cors});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const firebaseKeys=createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
Deno.serve(async req=>{
 if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return reply(403,'Origin not allowed.');
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply(405,'POST required.');
 const authorization=req.headers.get('authorization');
 if(!authorization?.startsWith('Bearer '))return reply(401,'Sign in to import photos.');
 // Supabase's gateway does not validate third-party Firebase tokens. Verify the
 // signature, issuer, audience, expiry and verified role here before reading any
 // request body. Database requests additionally enforce the caller's RLS role.
 try{
  const {payload}=await jwtVerify(authorization.slice(7),firebaseKeys,{issuer:'https://securetoken.google.com/family-funnies',audience:'family-funnies',algorithms:['RS256'],requiredClaims:['exp','iat','auth_time','sub']});
  const now=Date.now()/1000;
  if(!payload.sub||payload.sub.length>128||typeof payload.iat!=='number'||payload.iat>now||typeof payload.auth_time!=='number'||payload.auth_time>now||payload.email_verified!==true||payload.role!=='authenticated')return reply(401,'Verify your account before importing photos.');
 }catch{return reply(401,'Sign in again to import photos.');}
 if(Number(req.headers.get('content-length'))>16000)return reply(413,'Request too large.');
 try{
  const body=await req.text();if(body.length>16000)return reply(413,'Request too large.');
  const {familyId,personId,sessionId,mediaItemId,googleAccessToken}=JSON.parse(body);
  if(!uuid.test(familyId)||!uuid.test(personId)||typeof sessionId!=='string'||sessionId.length>1000||typeof mediaItemId!=='string'||mediaItemId.length>1000||typeof googleAccessToken!=='string'||googleAccessToken.length>5000)return reply(400,'Invalid photo selection.');
  const keys=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}');
  const key=keys.default||'sb_publishable_xgM0vw1ZtNkhyo32-NH25A_zsvCC80h';
  const db=createClient(Deno.env.get('SUPABASE_URL')!,key,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const person=await db.from('people').select('id').eq('id',personId).eq('family_id',familyId).maybeSingle();
  if(person.error||!person.data)return reply(403,'You cannot add photos to this family.');
  const refs=await db.from('reference_photos').select('position').eq('person_id',personId).eq('family_id',familyId);
  if(refs.error)return reply(403,'Could not read this profile.');
  const occupied=new Set((refs.data||[]).map(r=>r.position));
  let position=0;while(occupied.has(position))position++;
  if(position>=6)return reply(409,'This cast member already has six photos.');
  const googleHeaders={Authorization:'Bearer '+googleAccessToken};
  const selection=await fetch('https://photospicker.googleapis.com/v1/mediaItems?'+new URLSearchParams({sessionId,pageSize:'100'}),{headers:googleHeaders,redirect:'error',signal:AbortSignal.timeout(20000)});
  if(!selection.ok)return reply(400,'Google photo selection expired. Choose your photos again.');
  const selected=await selection.json();
  const item=selected.mediaItems?.find((m:{id:string})=>m.id===mediaItemId);
  if(!item||item.type!=='PHOTO'||!item.mediaFile?.baseUrl)return reply(400,'Choose a photo from this Google Photos selection.');
  const photoUrl=new URL(item.mediaFile.baseUrl);
  if(photoUrl.protocol!=='https:'||!photoUrl.hostname.endsWith('.googleusercontent.com')||photoUrl.username||photoUrl.password||photoUrl.port)return reply(400,'Unsupported Google photo address.');
  // Restrict size for reference use; never forward a bearer through redirects.
  const photo=await fetch(photoUrl.href+'=w1600-h1600',{headers:googleHeaders,redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!photo.ok||!photo.body)return reply(400,'Could not download this photo. Try another selection.');
  const mime=(photo.headers.get('content-type')||'').split(';')[0];
  if(!['image/jpeg','image/png','image/webp'].includes(mime))return reply(400,'Choose a JPEG, PNG or WebP photo.');
  const reader=photo.body.getReader();const chunks:Uint8Array[]=[];let length=0;
  while(true){const part=await reader.read();if(part.done)break;length+=part.value.length;if(length>5*1024*1024){await reader.cancel();return reply(413,'This photo is too large. Choose a smaller photo.');}chunks.push(part.value);}
  const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  const path=`${familyId}/${personId}/${crypto.randomUUID()}`;
  const upload=await db.storage.from('family-references').upload(path,bytes,{contentType:mime,upsert:false});
  if(upload.error)return reply(400,'Could not save this photo. Please try again.');
  const insert=await db.from('reference_photos').insert({family_id:familyId,person_id:personId,object_path:path,position});
  if(insert.error){await db.storage.from('family-references').remove([path]);return reply(409,'The profile changed. Refresh and try again.');}
  return Response.json({saved:true},{headers:cors});
 }catch{return reply(400,'Could not import this photo. Choose it again or upload a file.');}
});
