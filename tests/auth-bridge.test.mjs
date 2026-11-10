import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPair,exportJWK,exportPKCS8,createLocalJWKSet,SignJWT} from 'jose';
import {verifyFirebaseToken,handleBootstrap} from '../worker/auth-bridge.mjs';
const {publicKey,privateKey}=await generateKeyPair('RS256',{extractable:true});
const keys=createLocalJWKSet({keys:[{...await exportJWK(publicKey),kid:'test',alg:'RS256'}]});
const project='test-project';
const now=Math.floor(Date.now()/1000);
async function token(changes={}){return new SignJWT({sub:'user-one',email_verified:true,auth_time:now,iss:`https://securetoken.google.com/${project}`,aud:project,iat:now,exp:now+300,...changes}).setProtectedHeader({alg:'RS256',kid:'test'}).sign(privateKey)}
test('valid signature and exact Firebase project accepted',async()=>{assert.equal((await verifyFirebaseToken(await token(),project,keys)).sub,'user-one')});
for(const [label,changes] of Object.entries({issuer:{iss:'https://evil.invalid'},audience:{aud:'other-project'},expired:{exp:now-30},unverified:{email_verified:false},futureIssued:{iat:now+3600},futureAuth:{auth_time:now+3600},emptySubject:{sub:''}}))test('rejects '+label,async()=>{await assert.rejects(()=>token(changes).then(t=>verifyFirebaseToken(t,project,keys)))});
const request=(headers={},method='POST')=>new Request('https://app.example/api/bootstrap',{method,headers:{Origin:'https://app.example',Authorization:'Bearer test',...headers}});
test('bootstrap fails closed without deployment secrets',async()=>{assert.equal((await handleBootstrap(request(),{})).status,503)});
test('rejects cross-origin bootstrap',async()=>{assert.equal((await handleBootstrap(request({Origin:'https://evil.invalid'}),{})).status,403)});
test('rejects anonymous bootstrap',async()=>{assert.equal((await handleBootstrap(request({Authorization:''}),{})).status,401)});
test('rejects GET',async()=>{assert.equal((await handleBootstrap(request({},'GET'),{})).status,405)});
const env={FIREBASE_PROJECT_ID:project,GOOGLE_SERVICE_ACCOUNT:JSON.stringify({project_id:project,client_email:'test@example.invalid',private_key:await exportPKCS8(privateKey)})};
test('provisions only the verified uid and preserves server claims',async()=>{
 const calls=[];const fetcher=async(url,options)=>{calls.push({url,body:JSON.parse(options.body instanceof URLSearchParams?'{}':options.body)});if(url.includes('oauth2'))return Response.json({access_token:'test-oauth'});if(url.endsWith(':lookup'))return Response.json({users:[{localId:'user-one',emailVerified:true,customAttributes:'{"existing":"keep"}'}]});return Response.json({localId:'user-one'})};
 const result=await handleBootstrap(request(),env,{verify:async()=>({sub:'user-one',auth_time:now}),fetch:fetcher});assert.equal(result.status,200);assert.equal(calls[2].body.localId,'user-one');assert.deepEqual(JSON.parse(calls[2].body.customAttributes),{existing:'keep',role:'authenticated'});
});
for(const [label,user] of Object.entries({disabled:{disabled:true},revoked:{validSince:String(now+1)},unverified:{emailVerified:false}}))test('does not provision '+label+' account',async()=>{
 let updates=0;const fetcher=async(url)=>{if(url.includes('oauth2'))return Response.json({access_token:'test-oauth'});if(url.endsWith(':lookup'))return Response.json({users:[{localId:'user-one',emailVerified:true,...user}]});updates++;return Response.json({})};
 const result=await handleBootstrap(request(),env,{verify:async()=>({sub:'user-one',auth_time:now}),fetch:fetcher});assert.equal(result.status,401);assert.equal(updates,0);
});
