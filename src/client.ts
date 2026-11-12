import {initializeApp} from 'firebase/app';
import {getAuth} from 'firebase/auth';
import {createClient} from '@supabase/supabase-js';
import {publicConfig} from './public-config';
const env=import.meta.env;
export const firebaseProjectId=env.VITE_FIREBASE_PROJECT_ID||publicConfig.firebase.projectId;
const firebaseConfig={apiKey:env.VITE_FIREBASE_API_KEY||publicConfig.firebase.apiKey,projectId:firebaseProjectId,appId:env.VITE_FIREBASE_APP_ID||publicConfig.firebase.appId,authDomain:env.VITE_FIREBASE_AUTH_DOMAIN||publicConfig.firebase.authDomain};
const supabaseUrl=env.VITE_SUPABASE_URL||publicConfig.supabaseUrl;
const publishableKey=env.VITE_SUPABASE_PUBLISHABLE_KEY||publicConfig.supabasePublishableKey;
export const configured=Boolean(firebaseConfig.apiKey&&firebaseConfig.projectId&&firebaseConfig.appId&&firebaseConfig.authDomain&&supabaseUrl&&publishableKey);
export const auth=configured?getAuth(initializeApp(firebaseConfig)):null;
export const db=configured?createClient(supabaseUrl,publishableKey,{accessToken:async()=>auth?.currentUser?await auth.currentUser.getIdToken():null}):null;
export async function assertAccess(){
 const u=auth?.currentUser;
 if(!u||!u.emailVerified)throw new Error('Verify your email before opening your families.');
 // Refresh after verification, but do not wait for a scheduled custom claim.
 // Supabase verifies the signature; actor() verifies issuer/audience/email and
 // every operation still enforces the caller's family membership through RLS.
 const token=await u.getIdTokenResult();
 if(token.claims.email_verified!==true)await u.getIdToken(true);
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
