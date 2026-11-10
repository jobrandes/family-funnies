# Family Funnies

A standalone family comic app for creators and readers, with private family memberships and simple comic-only sharing.

Planned stack: Cloudflare hosting, Firebase Authentication on Spark, and Supabase database/private storage. Additional spending must remain $0.

## Current state

Database foundation only; the standalone website is not yet deployed. The existing family comic app and shared links remain unchanged.

- [Applied database schema](database/foundation.sql)
- [Database isolation integration tests](tests/isolation.sql)
- [Completed work and remaining setup](PROJECT-STATUS.md)

No private profiles, family photos, comics or credentials belong in this repository. Reference data is stored privately outside Git. Do not commit environment secrets or service account files.

## Database tests

Run `tests/isolation.sql` using an administrative connection to a disposable database with the foundation applied. It creates synthetic fixtures inside a transaction and rolls them back. It tests family isolation, cross-family writes, reader privacy, role escalation, contributor permissions, visual revision invalidation, cast queueing, unique daily comics, identity issuer restrictions and anonymous denial. These database tests passed against the new project; real sign-in and end-to-end application tests remain pending.
