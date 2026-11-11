import React,{useEffect,useRef,useState} from 'react';
import {auth} from './client';
import {publicConfig} from './public-config';

const clientId='929936102134-o18oh20rba3m09hu5qdfqm2fo4jq7di5.apps.googleusercontent.com';
const scope='https://www.googleapis.com/auth/photospicker.mediaitems.readonly';
const api='https://photospicker.googleapis.com/v1';
type TokenReply={access_token?:string;error?:string};
declare global{interface Window{google?:{accounts:{oauth2:{initTokenClient:(options:{client_id:string;scope:string;callback:(r:TokenReply)=>void;error_callback:()=>void})=>{requestAccessToken:()=>void}}}}}}
let scriptReady:Promise<void>|undefined;
function loadGoogle(){
 if(window.google)return Promise.resolve();
 return scriptReady??=new Promise<void>((resolve,reject)=>{const s=document.createElement('script');s.src='https://accounts.google.com/gsi/client';s.async=true;s.onload=()=>resolve();s.onerror=()=>{scriptReady=undefined;reject(new Error('Google Photos could not load. You can still upload files.'));};document.head.append(s);});
}
export function GooglePhotos({familyId,personId,remaining,onSaved}:{familyId:string;personId:string;remaining:number;onSaved:()=>Promise<void>}){
 const [ready,setReady]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[picker,setPicker]=useState('');
 const active=useRef(true),cancelled=useRef(false);
 useEffect(()=>{active.current=true;void loadGoogle().then(()=>{if(active.current)setReady(true)}).catch(e=>{if(active.current)setMessage(e.message)});return()=>{active.current=false;cancelled.current=true}},[]);
 const say=(text:string)=>{if(active.current)setMessage(text)};
 async function select(token:string){
  let sessionId='';
  try{
   const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
   const create=await fetch(api+'/sessions',{method:'POST',headers,body:JSON.stringify({pickingConfig:{maxItemCount:String(remaining)}})});
   if(!create.ok)throw new Error('Google Photos is not available for this account yet. You can upload files instead.');
   let session=await create.json();sessionId=session.id;
   const url=new URL(session.pickerUri);if(url.protocol!=='https:'||!(url.hostname==='photos.google.com'||url.hostname.endsWith('.photos.google.com')))throw new Error('Google returned an unsupported picker address.');
   if(active.current)setPicker(url.href+'/autoclose');
   say('Open Google Photos below, select your photos, and tap Done. Keep this page open.');
   const duration=(v:string|undefined,fallback:number)=>{const n=Number(v?.replace(/s$/,''));return Number.isFinite(n)&&n>0?n*1000:fallback};
   const deadline=Date.now()+Math.min(duration(session.pollingConfig?.timeoutIn,600000),900000);
   while(!session.mediaItemsSet){
    if(cancelled.current||!active.current)throw new Error('Photo selection cancelled.');
    if(Date.now()>deadline)throw new Error('The selection timed out. Please try again.');
    await new Promise(r=>setTimeout(r,Math.max(1000,duration(session.pollingConfig?.pollInterval,5000))));
    const poll=await fetch(api+'/sessions/'+encodeURIComponent(sessionId),{headers});if(!poll.ok)throw new Error('Google photo selection expired. Please try again.');session=await poll.json();
   }
   const selected=await fetch(api+'/mediaItems?'+new URLSearchParams({sessionId,pageSize:'100'}),{headers});if(!selected.ok)throw new Error('Could not read the selected photos.');
   const data=await selected.json();const items=data.mediaItems||[];
   if(items.length>remaining||data.nextPageToken)throw new Error(`Choose up to ${remaining} photos for this cast member.`);
   if(items.some((p:{type:string})=>p.type!=='PHOTO'))throw new Error('Choose photos only; videos are not supported.');
   if(!items.length)throw new Error('No photos selected.');
   const firebaseToken=await auth!.currentUser!.getIdToken();let count=0;
   for(const item of items){
    if(cancelled.current||!active.current)break;
    say(`Saving photo ${count+1} of ${items.length}…`);
    const response=await fetch(publicConfig.supabaseUrl+'/functions/v1/google-photo-import',{method:'POST',headers:{Authorization:'Bearer '+firebaseToken,apikey:publicConfig.supabasePublishableKey,'Content-Type':'application/json'},body:JSON.stringify({familyId,personId,sessionId,mediaItemId:item.id,googleAccessToken:token})});
    if(!response.ok){await onSaved();throw new Error((await response.json()).message||'Could not save this photo.');}count++;
   }
   await onSaved();say(`${count} photo${count===1?'':'s'} saved.`);
  }catch(e){say(e instanceof Error?e.message:'Google Photos could not finish. Try uploading files instead.');}
  finally{if(sessionId)await fetch(api+'/sessions/'+encodeURIComponent(sessionId),{method:'DELETE',headers:{Authorization:'Bearer '+token}}).catch(()=>{});if(active.current){setBusy(false);setPicker('')}}
 }
 function start(){
  if(!window.google||!remaining)return;cancelled.current=false;setBusy(true);setMessage('Connecting to Google…');
  window.google.accounts.oauth2.initTokenClient({client_id:clientId,scope,callback:r=>{if(r.error||!r.access_token){say('Google access was not granted. You can upload photos instead.');setBusy(false);return;}void select(r.access_token)},error_callback:()=>{say('Google sign-in was closed or blocked. Please try again.');setBusy(false)}}).requestAccessToken();
 }
 return <div className="google-photos"><button className="secondary" type="button" disabled={!ready||busy||remaining<1} onClick={start}>{busy?'Choosing photos…':'Choose from Google Photos'}</button>{picker&&<a className="photo-picker-link" href={picker} target="_blank" rel="noopener noreferrer">Open Google Photos →</a>}{message&&<p className="small" role="status">{message}</p>}{busy&&<button className="quiet" type="button" onClick={()=>{cancelled.current=true;say('Cancelling selection…')}}>Cancel</button>}</div>;
}
