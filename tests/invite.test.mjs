import test from 'node:test';
import assert from 'node:assert/strict';
import {tokenFromHash,pendingInvite,forgetInvite,inviteUrl} from '../src/invite.mjs';
const token='a'.repeat(64),other='b'.repeat(64);
const store=()=>{const m=new Map();return {m,getItem:k=>m.get(k)??null,setItem:(k,v)=>void m.set(k,v),removeItem:k=>void m.delete(k)}};
test('reads a well-formed token and rejects anything else',()=>{
 assert.equal(tokenFromHash('#invite='+token),token);
 assert.equal(tokenFromHash('#invite=abc'),null);
 assert.equal(tokenFromHash('#invite='+token.toUpperCase()),null);
 assert.equal(tokenFromHash(''),null);
});
test('survives a new tab that has no fragment',()=>{const s=store();assert.equal(pendingInvite('#invite='+token,s,1000),token);assert.equal(pendingInvite('',s,2000),token)});
test('a newer link replaces the remembered one',()=>{const s=store();pendingInvite('#invite='+token,s,1);assert.equal(pendingInvite('#invite='+other,s,2),other);assert.equal(pendingInvite('',s,3),other)});
test('forgotten after seven days',()=>{const s=store();pendingInvite('#invite='+token,s,0);assert.equal(pendingInvite('',s,7*864e5+1),null);assert.equal(s.m.size,0)});
test('forgetInvite clears it',()=>{const s=store();pendingInvite('#invite='+token,s,0);forgetInvite(s);assert.equal(pendingInvite('',s,1),null)});
test('tampered storage is ignored and cleaned up',()=>{const s=store();s.setItem('family-funnies:pending-invite','{"token":"<script>","saved":1}');assert.equal(pendingInvite('',s,2),null);assert.equal(s.m.size,0);s.setItem('family-funnies:pending-invite','not json');assert.equal(pendingInvite('',s,2),null)});
test('blocked storage still honours the link in this tab',()=>{const s={getItem(){throw Error('blocked')},setItem(){throw Error('blocked')},removeItem(){throw Error('blocked')}};assert.equal(pendingInvite('#invite='+token,s),token);assert.equal(pendingInvite('',s),null);forgetInvite(s)});
test('continue link carries only a valid token',()=>{assert.equal(inviteUrl('https://x.test',token),'https://x.test/#invite='+token);assert.equal(inviteUrl('https://x.test',null),'https://x.test');assert.equal(inviteUrl('https://x.test','bad'),'https://x.test')});
