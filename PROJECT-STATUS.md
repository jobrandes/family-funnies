# Standalone migration status

## Implemented in source

- React/TypeScript app with cream-paper bookshelf home and compact family tabs; responsive CSS for desktop, tablet and phone.
- Firebase email/password signup, verification, reset and sign-out screens. Missing deployment configuration shows an honest setup state.
- Membership-scoped family listing/creation; reader/contributor/manager views.
- Person/pet profiles, memorial instructions, six private photo reference slots, photo removal, story jar and family preferences.
- Cast draft viewing, stale/missing-member checks and owner-only approval. Generation connection is explicitly pending.
- Single-use invitation links with hashed tokens, seven-day expiry, acceptance and revocation. Only owners create/revoke invitations; contributor/reader roles only.
- Private comic archive viewing for signed-in members. New guest sharing is not implemented; old reader links continue to work.
- Cloudflare Pages authentication bootstrap with cryptographic Firebase token validation and server-only Google account provisioning. Secrets and live integration remain pending.
- Pinned dependencies, lockfile and browser security headers.

## Applied database migrations

`database/foundation.sql` and `database/invitations.sql` are applied to the separate new project. The current owner-private Site, existing reader, production automations and other projects remain unchanged. No real family data is migrated.

## Verified

- TypeScript check and production build.
- Both SQL integration tests against the new database, with synthetic fixtures rolled back: isolation, role escalation, reader profile privacy, contributor restrictions, cast invalidation, job queueing, daily uniqueness, invite roles/replay/expiry/revocation and owner-only/stale-cast approval.
- Authentication bridge unit tests: valid signatures, wrong issuer/audience, expired/future tokens, unverified/disabled/revoked users, request origin, missing secrets and uid-scoped provisioning.

Database advisors report three informational notices for intentionally default-deny private tables; no warning/error findings at last check.

## Remaining launch work

- Firebase Web app is registered and public browser identifiers are configured. The exact Firebase issuer/audience is registered in the database allowlist.
- Connect Firebase as the Supabase third-party provider. Database allowlisting alone does not configure the API gateway.
- Configure the Cloudflare Free deployment and server-only authentication bootstrap credentials.
- Run real sign-in/email recovery and two-family end-to-end tests, upload tests and phone/tablet/desktop visual QA. CSS breakpoints are not evidence of browser testing.
- Implement cast worker claim/complete/fail endpoints, trusted runner connection and guarded production enable. Job tables alone do not produce images. New app production remains paused.
- Implement stable revocable comic-only guest links, authorized profile reuse/import, member removal/ownership transfer and verified data migration.
- Add storage/traffic caps, recovery exports and abuse limits before broader onboarding.

## Budget and privacy

Additional spend remains $0. No paid upgrade, Firebase Functions, SMS login or paid image API is enabled. Never commit private profiles, photos, comics, tokens or service keys. Keep existing Site sharing and reader links intact until migration is tested and complete.
