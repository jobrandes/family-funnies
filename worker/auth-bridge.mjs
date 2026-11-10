import {createRemoteJWKSet,importPKCS8,jwtVerify,SignJWT} from 'jose';
const firebaseKeys=createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
export async function verifyFirebaseToken(token,project,keys=firebaseKeys){
 const {payload}=await jwtVerify(token,keys,{algorithms:['RS256'],issuer:`https://securetoken.google.com/${project}`,audience:project,requiredClaims:['sub','exp','iat','auth_time']});
 if(typeof payload.sub!=='string'||!payload.sub||payload.sub.length>128||payload.email_verified!==true||typeof payload.iat!=='number'||payload.iat>Math.floor(Date.now()/1000)||typeof payload.auth_time!=='number'||payload.auth_time>payload.iat)throw new Error('Verified account required');
 return payload;
}
async function googleAccess(account,fetcher){
 const key=await importPKCS8(account.private_key,'RS256');
 const assertion=await new SignJWT({scope:'https://www.googleapis.com/auth/identitytoolkit'})
 .setProtectedHeader({alg:'RS256'}).setIssuer(account.client_email)
 .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('5m').sign(key);
 const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});
 if(!response.ok)throw new Error('Account provisioning unavailable');
 const result=await response.json();if(!result.access_token)throw new Error('Account provisioning unavailable');return result.access_token;
}
const json=(value,status)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
/** No client-supplied uid, role or service credentials are accepted. */
export async function handleBootstrap(request,env,deps={}){
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 if(request.headers.get('Origin')!==new URL(request.url).origin)return json({error:'Origin not allowed'},403);
 const token=request.headers.get('Authorization')?.match(/^Bearer ([^\s]+)$/)?.[1];
 if(!token)return json({error:'Sign-in required'},401);
 if(!env.FIREBASE_PROJECT_ID||!env.GOOGLE_SERVICE_ACCOUNT)return json({error:'Account connection is not configured yet'},503);
 let account;try{account=JSON.parse(env.GOOGLE_SERVICE_ACCOUNT);if(account.project_id!==env.FIREBASE_PROJECT_ID||typeof account.private_key!=='string'||typeof account.client_email!=='string')throw new Error();}catch{return json({error:'Account connection is not configured yet'},503)}
 let payload;try{payload=await (deps.verify??verifyFirebaseToken)(token,env.FIREBASE_PROJECT_ID)}catch{return json({error:'Verified sign-in required'},401)}
 const fetcher=deps.fetch??fetch;
 try{
  const access=await googleAccess(account,fetcher);
  const base=`https://identitytoolkit.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/accounts`;
  const headers={'Content-Type':'application/json',Authorization:`Bearer ${access}`};
  const lookup=await fetcher(base+':lookup',{method:'POST',headers,body:JSON.stringify({localId:[payload.sub]})});
  if(!lookup.ok)throw new Error();const found=await lookup.json();const user=found.users?.find(u=>u.localId===payload.sub);
  if(!user||user.disabled||user.emailVerified!==true||Number(user.validSince??0)>payload.auth_time)return json({error:'Sign in again to continue'},401);
  const current=user.customAttributes?JSON.parse(user.customAttributes):{};
  if(current.role!=='authenticated'){
   const result=await fetcher(base+':update',{method:'POST',headers,body:JSON.stringify({localId:payload.sub,customAttributes:JSON.stringify({...current,role:'authenticated'})})});
   if(!result.ok)throw new Error();
  }
  return json({ready:true},200);
 }catch{return json({error:'Account connection is temporarily unavailable'},503)}
}
