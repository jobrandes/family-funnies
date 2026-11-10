# Standalone migration status

This repository starts the independent Family Funnies application. It does not yet contain a deployable web app.

## Completed

- Separate database project and the schema in `database/foundation.sql`.
- Owner, contributor and reader membership permissions.
- Private reference-photo and comic buckets with family-scoped access.
- Cast revision tracking and queued jobs when visual profiles change.
- Memorial profile fields and up to six reference slots per person.
- Unique comic per family per day.
- Live database integration tests in `tests/isolation.sql`, run successfully with all synthetic fixtures rolled back.

## Pending

- Firebase project setup, verified email/password login and trusted issuer configuration.
- Server-only Firebase custom-claim provisioning. Do not enable paid Firebase Functions to implement this.
- Standalone responsive bookshelf UI, family onboarding and profile editing.
- Single-use expiring management invitations and revocable comic-only guest archive links.
- Cast job claim, completion, failure, approval and production-readiness APIs.
- Generation runner integration, Cloudflare deployment and verified data migration.
- End-to-end authentication, invitations, upload and responsive-browser tests.

The identity-provider allowlist currently has no entries: the new database denies end-user access until the sign-in integration is configured. Tables for jobs, invitations and shares are groundwork; they do not imply these features are available.

## Budget and privacy

Additional spending must remain $0. No paid upgrades, pay-as-you-go services, SMS login or paid image API may be enabled. Free storage/traffic quotas require limits and monitoring; no promise of unlimited free operation.

The current owner-private Site, existing comic reader links and scheduled production remain in place during development. Never publish their profiles, photos, comics, service tokens or exported data in this repository. Keep administrative keys in deployment secrets. Database migrations contain schema only.
