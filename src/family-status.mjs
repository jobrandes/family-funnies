export function familyStatus(family,cast,job,latest,today,role){
 if(role==='owner'&&family.onboarding_step>0&&family.onboarding_step<5)return 'Continue setup';
 if(role==='reader')return latest?.day===today?'✦ New today':latest?'Your comic collection':'First comic pending';
 const current=cast?.visual_revision===family.visual_revision;
 if(current&&cast?.missing?.length)return 'Cast needs references';
 if(current&&!cast.approved_at)return 'Ready to review cast';
 if(!current){
  if(job?.state==='failed'&&job.attempts>=3)return 'Cast needs attention';
  if(job?.state==='processing'&&new Date(job.claim_expires_at)>new Date())return 'Creating cast preview';
  return cast?'Cast refresh queued':'Cast setup pending';
 }
 if(latest?.day===today)return '✦ New today';
 if(family.production_enabled)return latest?'Daily comics on':'First comic pending';
 return 'Cast approved · daily comics off';
}
