# Deployment setup (not yet deployed)

## Browser configuration

Register a Web app in the existing Firebase project (Project settings → General → Your apps → Web). Firebase Hosting is not needed. Copy the public `firebaseConfig` fields into the matching `.env.example` variables for the build environment. Use the Supabase API URL and a publishable key for the other two public variables. These are public identifiers; never use a Supabase secret/service key here.

## Authentication bridge — required before login can access families

Enable Firebase email/password signup and verification. Add the exact Firebase project to Supabase Authentication → Third-party Auth. Configure the exact issuer and audience in `family_private.identity_providers` using an administrative connection.

New Firebase users need the server-issued `role: authenticated` custom claim for Supabase. Service-account key creation is blocked by the project's organization policy. Keep that policy enabled. The app no longer needs a `GOOGLE_SERVICE_ACCOUNT` key or a Cloudflare bootstrap function.

Run `scripts/setup-keyless-login.sh` in the owner's Google Cloud Shell after reviewing its changes. It enables IAM/STS APIs, creates a workload identity pool/provider and grants only the repository's main-branch `activate-accounts.yml` workflow service-account impersonation. The existing service account still has only the custom `firebaseauth.users.get` and `firebaseauth.users.update` role. The script creates no private key and changes no billing or organization policies. Stop on permission/policy errors rather than disabling controls.

Copy the two public values printed by the script into GitHub repository Settings → Secrets and variables → Actions → Variables: `WIF_PROVIDER` and `WIF_SERVICE_ACCOUNT`. Then run the 'Activate verified family accounts' workflow manually once. It uses short-lived Google tokens, activates verified enabled accounts without an existing explicit role, preserves other server claims, and logs aggregate counts only. No user records or credentials are written to workflow artifacts.

The workflow is scheduled at ten-minute intervals but GitHub schedules can be delayed and public-repository schedules can stop after 60 days of inactivity. The app says activation is pending until a refreshed token carries the claim; it does not promise immediate activation. A manager can run the workflow manually if delayed. This is an interim small-family solution, not a guaranteed real-time provisioning service. Standard public-repository GitHub-hosted runners are free under the current plan; do not switch to paid runners or a paid plan.

## Cloudflare Free

The GitHub repository is connected to Cloudflare Pages at `https://family-funnies.pages.dev/`. Build command `npm run build`, output `dist`. Public configuration is in source; optional environment overrides are supported. Add `family-funnies.pages.dev` to Firebase Authorized domains. Do not switch to a paid plan or add billing-only services. No public personal content is included in the bundle.

## Validation gates before inviting relatives

- `npm ci` and `npm run build`.
- Apply the two schema migrations to a new test database and run both SQL tests; scripts roll back fixtures.
- Complete real signup, email verification, sign-in, password reset and sign-out.
- Test two different accounts/families and check reference photos stay private.
- Test single-use invitation acceptance, revoked/expired links and reader restrictions end-to-end.
- Test phone/tablet/desktop in browser. CSS breakpoints alone are not evidence of visual testing.
- Implement and validate comic-only guest sharing and the generation runner before offering them in the new app.

Keep the current Site, production schedule and guest links active until migration has been backed up and verified.
