# Family Funnies

A standalone family comic app for creators and readers, with private family memberships and simple comic-only sharing.

Planned stack: Cloudflare hosting, Firebase Authentication on Spark, and Supabase database/private storage. Additional spending must remain $0.

## Current state

The standalone app source is implemented and builds, but is not yet deployed or connected to live sign-in. The existing family comic app and shared links remain unchanged.

- [Applied database schema](database/foundation.sql)
- [Database isolation integration tests](tests/isolation.sql)
- [Completed work and remaining setup](PROJECT-STATUS.md)
- [Deployment configuration and verification gates](DEPLOYMENT.md)

## Development

Run `npm ci`, copy `.env.example` to `.env.local` and fill in the public web-app configuration, then run `npm run dev`. Run `npm test` and `npm run build` before deployment. No administrative credential belongs in a `VITE_` variable.

No private profiles, family photos, comics or credentials belong in this repository. Reference data is stored privately outside Git. Do not commit environment secrets or service account files.

## Database tests

Run `tests/isolation.sql` using an administrative connection to a disposable database with the foundation applied. It creates synthetic fixtures inside a transaction and rolls them back. It tests family isolation, cross-family writes, reader privacy, role escalation, contributor permissions, visual revision invalidation, cast queueing, unique daily comics, identity issuer restrictions and anonymous denial. These database tests passed against the new project; real sign-in and end-to-end application tests remain pending.
