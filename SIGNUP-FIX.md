# Verified signup without scheduled activation

Prepared change; production database migration requires explicit owner approval.

## Behavior

After Firebase email verification, the client refreshes its signed ID token and
opens the family's collection. No GitHub workflow has to add a custom role first.
Existing users retain their current identity and memberships. Verification is
checked on window focus and every five seconds while this page is visible.
Reset/verification emails have confirmation text, spam guidance, a sixty-second
resend countdown, and a return link to the app. This does not promise to speed
Firebase or recipient-provider email delivery.

## Permission change to review

Supabase validates Firebase JWT signatures before serving database requests.
Firebase tokens without a role claim execute as the Postgres `anon` role. The
migration allows that role through the same membership-based RLS policies used
by existing users, retaining the trusted issuer, audience, and verified-email
checks in `family_private.actor()`. Requests without a verified trusted identity
still have no actor and cannot read families or create them.

The migration grants only application table operations and guarded client RPCs;
it does not grant access to private records, runner commands, media permits,
membership mutation, or cast/comic writes. Storage uses the existing membership
policies. Anonymous visitors, unverified users, and outsiders must remain denied.

The automatic approval reviewer rejected the permanent production grants as a
security boundary change beyond the instruction to speed signup. The migration
was only exercised in a transaction that rolled back; it is NOT installed.
The frontend is not deployed while it depends on that migration. The temporary
photo-import deployment was restored byte-for-byte to its previous source.

## Validation

- `npm run build` and `npm test` pass.
- `tests/instant-verified-access.sql` passes with the migration inside a rolled
  back transaction: verified identity with no role can create/read its family;
  outsiders cannot read family data or storage; unverified/anonymous/wrong
  issuer/wrong audience are denied; runner commands and permits are denied.
- A real new-user email-verification test remains necessary after deployment.

## Rollout after approval

Apply `database/instant-verified-access.sql`, rerun isolation tests, deploy
`worker/google-photo-import.ts`, then publish this frontend. Keep the old Site
and existing family accounts intact. The old activation workflow is no longer
needed for app access, but does not need to be disabled to release this change.

The new family wizard remains a separate approved design proposal. This patch
addresses signup and activation first.
