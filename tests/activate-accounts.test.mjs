import {test} from 'node:test';import assert from 'node:assert/strict';
import {activationUpdate,activateAccounts} from '../scripts/activate-accounts.mjs';
test('only verified enabled users with no existing role are eligible',()=>{
 assert.equal(activationUpdate({localId:'one',emailVerified:false}),null);
 assert.equal(activationUpdate({localId:'one',emailVerified:true,disabled:true}),null);
 assert.equal(activationUpdate({localId:'one',emailVerified:true,customAttributes:'{"role":"admin"}'}),null);
 assert.equal(activationUpdate({localId:'one',emailVerified:true,customAttributes:'{"role":"authenticated"}'}),null);
});
test('preserves server claims and assigns only authenticated',()=>assert.deepEqual(activationUpdate({localId:'one',emailVerified:true,customAttributes:'{"keep":1}'}),{localId:'one',customAttributes:'{"keep":1,"role":"authenticated"}'}));
test('rejects malformed claims',()=>assert.throws(()=>activationUpdate({localId:'one',emailVerified:true,customAttributes:'[]'})));
test('rejects wrong project and missing credentials before network access',async()=>{
 await assert.rejects(()=>activateAccounts({project:'other',accessToken:'test'}));
 await assert.rejects(()=>activateAccounts({project:'family-funnies',accessToken:''}));
});
test('paginates and updates only eligible accounts',async()=>{
 let calls=[];const fetcher=async(url,options)=>{calls.push({url,options});if(url.endsWith(':update'))return Response.json({});return url.includes('nextPageToken=second')?Response.json({users:[{localId:'two',emailVerified:true,disabled:true}]}):Response.json({users:[{localId:'one',emailVerified:true}],nextPageToken:'second'})};
 assert.deepEqual(await activateAccounts({project:'family-funnies',accessToken:'test',fetcher}),{scanned:2,activated:1});
 assert.equal(calls.length,3);assert.deepEqual(JSON.parse(calls[1].options.body),{localId:'one',customAttributes:'{"role":"authenticated"}'});
});
test('failure messages do not expose provider response or tokens',async()=>{
 await assert.rejects(()=>activateAccounts({project:'family-funnies',accessToken:'never-log-this',fetcher:async()=>new Response('sensitive account record',{status:403})}),/^Error: Account listing failed \(403\)$/);
});
