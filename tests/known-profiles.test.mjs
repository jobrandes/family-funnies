import test from 'node:test';
import assert from 'node:assert/strict';
import {profileKey, groupKnownProfiles} from '../src/known-profiles.mjs';

test('one picker entry per name and kind, preserving every source profile', () => {
  const profiles = [
    {id:'1', name:'Jo',kind:'person',family_id:'a'},
    {id:'2', name:' jo ',kind:'person',family_id:'b'},
    {id:'3', name:'JO',kind:'person',family_id:'c'},
    {id:'4', name:'Coco',kind:'pet',family_id:'a'},
    {id:'5', name:'Coco',kind:'pet',family_id:'b'},
    {id:'6', name:'Coco',kind:'person',family_id:'c'},
  ];
  const original = structuredClone(profiles);
  const groups = groupKnownProfiles(profiles);
  assert.equal(groups.length, 3);
  assert.deepEqual(groups[0].sources.map(p=>p.id), ['1','2','3']);
  assert.deepEqual(profiles, original);
  assert.notEqual(profileKey(profiles[3]),profileKey(profiles[5]));
});

test('current family profiles match all copied versions, without merging their details', () => {
  const groups = groupKnownProfiles([{name:'Caden',kind:'person',appearance:'black sweatshirt'},{name:' Caden ',kind:'person',appearance:'white sweatshirt'}]);
  const current = new Set([{name:'CADEN',kind:'person'}].map(profileKey));
  assert.equal(current.has(groups[0].key),true);
  assert.deepEqual(groups[0].sources.map(p=>p.appearance),['black sweatshirt','white sweatshirt']);
  assert.equal(profileKey({name:'Uncle   David'}),profileKey({name:'Uncle David',kind:'person'}));
});
