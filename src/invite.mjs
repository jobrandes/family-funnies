// An invitation link carries its token in the URL fragment. New members usually
// finish email verification in a different tab, where that fragment is gone, so
// the token is also remembered in this browser until it is used or dismissed.
const KEY='family-funnies:pending-invite';
const VALID=/^[a-f0-9]{64}$/;
const MAX_AGE=7*24*60*60*1000; // invitations expire after seven days
export function tokenFromHash(hash){
 const token=new URLSearchParams(String(hash||'').replace(/^#/,'')).get('invite');
 return token&&VALID.test(token)?token:null;
}
export function pendingInvite(hash,storage,now=Date.now()){
 const fromUrl=tokenFromHash(hash);
 try{
  if(fromUrl){storage.setItem(KEY,JSON.stringify({token:fromUrl,saved:now}));return fromUrl;}
  const saved=JSON.parse(storage.getItem(KEY)||'null');
  if(saved&&typeof saved.token==='string'&&VALID.test(saved.token)&&typeof saved.saved==='number'&&now-saved.saved>=0&&now-saved.saved<MAX_AGE)return saved.token;
  storage.removeItem(KEY);
 }catch{/* private browsing or blocked storage: the link in this tab still works */}
 return fromUrl;
}
export function forgetInvite(storage){try{storage.removeItem(KEY)}catch{/* nothing stored */}}
export function inviteUrl(origin,token){return token&&VALID.test(token)?`${origin}/#invite=${token}`:origin;}
