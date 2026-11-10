import {initializeApp} from 'firebase/app';
import {getAuth} from 'firebase/auth';
import {createClient} from '@supabase/supabase-js';
const env=import.meta.env;
export const configured=Boolean(env.VITE_FIREBASE_API_KEY&&env.VITE_FIREBASE_PROJECT_ID&&env.VITE_FIREBASE_APP_ID&&env.VITE_FIREBASE_AUTH_DOMAIN&&env.VITE_SUPABASE_URL&&env.VITE_SUPABASE_PUBLISHABLE_KEY);
export const auth=configured?getAuth(initializeApp({apiKey:env.VITE_FIREBASE_API_KEY,projectId:env.VITE_FIREBASE_PROJECT_ID,appId:env.VITE_FIREBASE_APP_ID,authDomain:env.VITE_FIREBASE_AUTH_DOMAIN})):null;
export const db=configured?createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{accessToken:async()=>auth?.currentUser?await auth.currentUser.getIdToken():null}):null;
export async function assertAccess(){
 const u=auth?.currentUser;
 if(!u||!u.emailVerified)throw new Error('Verify your email before opening your families.');
 let token=await u.getIdTokenResult();
 if(token.claims.role!=='authenticated'){
  const response=await fetch('/api/bootstrap',{method:'POST',headers:{Authorization:`Bearer ${token.token}`}});
  if(!response.ok)throw new Error('Account connection is not ready yet. Your email is verified; the administrator still needs to finish connecting sign-in.');
  token=await u.getIdTokenResult(true);
  if(token.claims.role!=='authenticated')throw new Error('Please sign in again to finish connecting your account.');
 }
}
export async function rows(table:string,familyId?:string){
 if(!db)throw new Error('The app connection is not configured yet.');
 await assertAccess();
 let q=db.from(table).select('*');if(familyId)q=q.eq('family_id',familyId);
 const {data,error}=await q;if(error)throw error;return data??[];
}
export async function rpc(name:string,args:Record<string,unknown>){
 if(!db)throw new Error('The app connection is not configured yet.');
 await assertAccess();const {data,error}=await db.rpc(name,args);if(error)throw error;return data;
}
export async function signedImage(bucket:string,path:string){
 if(!db)throw new Error('The app connection is not configured yet.');
 const {data,error}=await db.storage.from(bucket).createSignedUrl(path,300);if(error)throw error;return data.signedUrl;
}
