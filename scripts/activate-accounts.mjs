// Run only in the trusted GitHub workflow with a short-lived Google access token.
// Never print tokens, account records, email addresses or provider error bodies.
export function activationUpdate(user){
 if(!user.localId||user.disabled||user.emailVerified!==true)return null;
 let claims;try{claims=user.customAttributes?JSON.parse(user.customAttributes):{}}catch{throw new Error('Invalid server claims; account left unchanged')}
 if(!claims||typeof claims!=='object'||Array.isArray(claims))throw new Error('Invalid server claims; account left unchanged');
 if(claims.role)return null; // Preserve all existing explicit authorization roles.
 return {localId:user.localId,customAttributes:JSON.stringify({...claims,role:'authenticated'})};
}
export async function activateAccounts({project,accessToken,fetcher=fetch}){
 if(project!=='family-funnies'||!accessToken)throw new Error('Activation configuration missing');
 const base=`https://identitytoolkit.googleapis.com/v1/projects/${project}/accounts`;
 const headers={Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'};
 let page='',scanned=0,activated=0,pages=0;
 do{
  if(++pages>100)throw new Error('Account safety limit reached');
  const query=new URLSearchParams({maxResults:'1000'});if(page)query.set('nextPageToken',page);
  const response=await fetcher(base+':batchGet?'+query,{headers});
  if(!response.ok)throw new Error(`Account listing failed (${response.status})`);
  const batch=await response.json();
  for(const user of batch.users??[]){scanned++;const update=activationUpdate(user);if(!update)continue;
   const result=await fetcher(base+':update',{method:'POST',headers,body:JSON.stringify(update)});
   if(!result.ok)throw new Error(`Account activation failed (${result.status})`);activated++;
  }
  page=batch.nextPageToken??'';
 }while(page);
 return {scanned,activated};
}
if(process.argv[1]&&import.meta.url===new URL('file://'+process.argv[1]).href){
 try{console.log(JSON.stringify(await activateAccounts({project:process.env.FIREBASE_PROJECT_ID,accessToken:process.env.GOOGLE_ACCESS_TOKEN})))}
 catch(e){console.error(e.message);process.exitCode=1}
}
