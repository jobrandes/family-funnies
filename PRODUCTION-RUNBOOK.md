# Staged standalone production

Parallel delivery is authorized. The existing daily comic task generates once on the original Site and mirrors each saved episode into the standalone app. Original Site production, guest-reader delivery and cadence remain active. New standalone families now have independent cast and episode production through the same morning tasks. Only the three legacy mirrored family IDs remain excluded from independent generation. Every run must catch up missing legacy archived episodes even if generation is skipped.

## Working connection

Supabase project: sonjzbvyghqowykufxxu
Media endpoint: https://sonjzbvyghqowykufxxu.supabase.co/functions/v1/production-media

Use the connected Supabase tools for authorized database operations. Never obtain or export administrator keys. The media function uses its platform-managed server credential internally and offers only one file transfer per capability. It exposes no profile or general database API.

Read families, people, reference_photos, story_moments, cast_versions and episodes using execute_sql. Only process the families authorized for the task. For episodes require production_enabled, a complete approved cast matching visual_revision, and no episode for today's America/Los_Angeles date. For casts use current-revision cast_jobs, including paused families, excluding ready jobs and active claims. Use runner_cast_queue() for due jobs; next_retry_at controls retries with no permanent three-attempt cutoff.

Claim with public.runner_command(command,fid,revision,claim,target_day,object_path,title,script,missing). Commands: cast_claim, cast_complete, cast_fail, episode_claim, episode_complete, episode_fail. Claim returns claimId; expiry is 30 minutes. Complete rechecks revision, claim, date and production/cast status transactionally. Episodes are insert-only and unique per family/day. Cast completion creates an unapproved draft. Never approve a cast automatically. Failed claims should be recorded with the corresponding fail command.

For each image download or generated PNG upload:
1. Generate 32 random bytes as a 64-character hexadecimal capability in memory; compute its SHA-256 hash. Never print, persist or put the capability into command arguments.
2. Through execute_sql insert only the hash, exact bucket, exact object_path, operation ('upload' or 'download'), expires_at (now()+interval '30 minutes') into family_private.media_permits. Do not put a plaintext credential into SQL.
3. Call the media endpoint using Authorization: Bearer <capability>. GET downloads the permitted image; POST accepts raw PNG bytes, at most 12MB. Pass credentials through hidden stdin/in-memory request headers. The permission is consumed once; retry requires a new permission.
4. Upload paths must be unique, under the exact family UUID, for example <familyId>/production/<claimId>-<randomUUID>.png. An upload never overwrites an object. Upload responses include byte count and SHA-256.
5. Complete the database job only after upload success. Read back the saved record and download its object through a separate permission; compare file hashes before claiming delivery.

Use built-in image generation, inspect the saved approved cast and relevant private reference photos, respect each family's own profiles and boundaries, keep memorial characters separate from living scenes, and preserve approved identity/clothing. No CPAP jokes. Never copy stories between families. Report concrete failures; do not claim an episode was delivered based only on a saved schedule.

## Validation performed

Live PNG upload/download matched byte-for-byte. Replayed capability and unauthenticated request both returned 401. SQL transaction tests passed paused-production rejection, duplicate claim rejection, forged claim rejection, valid completion and duplicate episode rejection; all test episode changes rolled back. Anonymous and ordinary authenticated clients cannot execute runner_command or consume_media_permit. The temporary migration importer remains disabled.

## Independent generation cutover

Daily comic delivery already mirrors original episodes into the standalone app. Profiles and cast edits are not bidirectionally synchronized; use the original Site for production inputs during this overlap. To later move independent generation to the standalone app, update the existing daily cast and comic automation prompts to use standalone data, preserving cadence and all humor/likeness requirements. Enable only manager-approved family series through enable_production. Do not switch until the owner requests it. Existing old-site reader links still depend on the original Site; their continued updates need a separately verified mirror before old production is retired.

## New public-app families (authorized November 10, 2026)

The 7 a.m. Pacific cast task and 8 a.m. Pacific comic task now query standalone data on every run, even when the original Site has no work. Exclude legacy mirrored IDs a558ec80-f1ee-4094-9bc2-689d0e54f063, 94c3f471-bd68-4390-89fe-74b250b40754 and e47f2cc4-c03b-4537-a08a-729c94fe41cf from standalone generation. Preserve all legacy delivery and sharing.

For every other family, prepare current queued cast jobs (including paused families) only once every named member has a reference or an approved previous likeness. Keep missing-reference jobs unclaimed. Respect active claims and next_retry_at. Use the trusted runner/media operations above. Managers review drafts; never auto-approve or auto-enable production. The Cast screen exposes Start daily comics after approval. Only enabled families with complete current approved casts receive an episode. Each family/day is unique. The cast task checks hourly from 7 a.m. through 9 p.m. Pacific. Do not present queued work as completed.

`tests/public-family-flow.sql` verifies the full database workflow and outsider privacy in a rollback transaction. It uses synthetic media paths and does not prove image generation or a real user's Google consent flow. Missing/forged Google-import JWTs return HTTP401. The Google import handler uses pinned JOSE to verify Firebase signatures/issuer/audience/expiry/verified role, then performs all profile/storage writes under that user's database policies. It has no administrative key. Google access tokens remain in memory and are not logged or persisted.

## Google Photos launch prerequisites

The app and `google-photo-import` handler support multi-photo Picker sessions, up to six references per person. File upload continues to work independently. The Google Cloud owner must configure the existing web OAuth client to authorize `https://family-funnies.pages.dev`, configure the Picker scope, and complete Google's audience/publishing/verification requirements for external users. Do not claim arbitrary-user Google Photos readiness until an external account has completed the real consent and import flow. Changes to Google-owned settings require access to the owner's Google Cloud console; this repository cannot grant them. See `GOOGLE-PHOTOS-SETUP.md`.

## Durable cast retries (November 13, 2026)

`database/cast-retry.sql` is applied in production. Each failed claim schedules its next retry after 5, 15, 60, 180, then 360 minutes (360 thereafter). The existing hourly task picks it up on the first scheduled check after that time. Attempts are cumulative; there is no permanent three-attempt cutoff. No new paid service or generation API is used.

Call `runner_cast_queue()` at the start and end of every cast run. It recovers expired claims and returns due jobs plus pending/retrying/processing/overdue counts. Claim eligible work before downloading photos, retain claimId, retry transient steps within that claim, and record unresolved failures through cast_fail. A replacement worker invalidates the old claim. Completion preserves the manager approval gate and production setting.

Unclaimed work remains due; a run that leaves eligible jobs unattempted must report RUN INCOMPLETE and the concrete reason. Work pending over two hours must be reported as overdue. These database guarantees preserve retry eligibility and prevent duplicate publication; the ChatGPT automation remains the image-generation executor. The app cannot itself invoke the built-in ChatGPT image tool. A schedule or normal automation completion label is not proof of successful generation.

`tests/cast-retry.sql` verifies backoff, retries beyond three failures, expired-worker recovery, rejection of stale claims, ready-job duplicate prevention and restricted queue access in a rollback transaction.

## Cast continuity (prepared November 13, 2026)

After applying `database/cast-continuity.sql`, additions, reference-photo changes and appearance updates leave the family's existing production opt-in unchanged. The runner selects the latest complete approved cast and returns approvedCastId when claiming an episode. Download and inspect THAT approved image; use only its approved characters. Newly added characters wait until the manager approves their replacement cast. Never treat the unapproved preview as approved. The episode claim pins approvedCastId; a different approval arriving during generation invalidates completion. Profiles/revision changes still invalidate the in-flight claim.

Explicitly paused families stay paused. Removing a person or changing their name, kind or memorial status pauses production for review. Initial setup still requires owner approval and production opt-in. The app combines those initial owner choices into one clearly labelled Approve cast & start daily comics button, and shows an owner-only review notice on the home shelf. Existing mirrored collections continue using original-Site delivery.

Update both generation automation prompts after deployment: independently enabled families qualify with ANY complete approved cast, while runner_command still takes the family's current visual revision. Use returned approvedCastId for the episode. Never require the latest unapproved replacement to be approved before continuing the previous cast. Preserve all family privacy, memorial and duplicate-day guards.
