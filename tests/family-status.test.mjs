import test from 'node:test';import assert from 'node:assert/strict';import {familyStatus} from '../src/family-status.mjs';
const f={visual_revision:9,onboarding_step:5,production_enabled:false};
test('stale approved art is queued, never falsely awaiting an approval',()=>assert.equal(familyStatus(f,{visual_revision:8,approved_at:'yes'},null,null,'2026-11-11','owner'),'Cast refresh queued'));
test('current unapproved art offers review',()=>assert.equal(familyStatus(f,{visual_revision:9},null,null,'2026-11-11','owner'),'Ready to review cast'));
test('approved art and disabled production are distinguished',()=>assert.equal(familyStatus(f,{visual_revision:9,approved_at:'yes'},null,null,'2026-11-11','owner'),'Cast approved · daily comics off'));
test('readers are never asked to manage profiles or cast',()=>assert.equal(familyStatus(f,null,null,{day:'2026-11-11'},'2026-11-11','reader'),'✦ New today'));
test('unfinished wizard is resumable even if cast work is queued',()=>assert.equal(familyStatus({...f,onboarding_step:3},null,{state:'queued'},null,'2026-11-11','owner'),'Continue setup'));

test('mirrored families do not show standalone production disabled',()=>assert.equal(familyStatus(f,{visual_revision:9,approved_at:'yes'},null,null,'2026-11-13','owner',true),'Comics from original collection'));
test('mirrored local revisions do not claim an independent cast is queued',()=>assert.equal(familyStatus(f,{visual_revision:8,approved_at:'yes'},{state:'queued'},null,'2026-11-13','owner',true),'Comics from original collection'));
test('mirrored new episode still highlights today',()=>assert.equal(familyStatus(f,null,null,{day:'2026-11-13'},'2026-11-13','owner',true),'✦ New today'));
test('failed casts remain retryable after three attempts',()=>assert.equal(familyStatus(f,null,{state:'failed',attempts:4},null,'2026-11-13','owner'),'Cast retry scheduled'));

test('approved production continues while a replacement waits for review',()=>assert.equal(familyStatus({...f,production_enabled:true},{visual_revision:9,approved_at:null},null,null,'2026-11-13','owner'),'Daily comics on · review cast update'));
test('active production does not look paused while cast refresh runs',()=>assert.equal(familyStatus({...f,production_enabled:true},{visual_revision:8,approved_at:'yes'},{state:'queued'},null,'2026-11-13','owner'),'Daily comics on · cast update queued'));
