# Deployment setup (not yet deployed)

## Browser configuration

Register a Web app in the existing Firebase project (Project settings → General → Your apps → Web). Firebase Hosting is not needed. Copy the public `firebaseConfig` fields into the matching `.env.example` variables for the build environment. Use the Supabase API URL and a publishable key for the other two public variables. These are public identifiers; never use a Supabase secret/service key here.

## Authentication bridge — required before login can access families

Enable Firebase email/password signup and verification. Add the exact Firebase project to Supabase Authentication → Third-party Auth. Configure the exact issuer and audience in `family_private.identity_providers` using an administrative connection.

New Firebase users need the server-issued `role: authenticated` custom claim for Supabase. `functions/api/bootstrap.ts` and `worker/auth-bridge.mjs` implement the Cloudflare Pages bootstrap: verify the Firebase signature, project, expiry, timestamps, verified email and uid, then check the account is enabled and tokens not revoked before provisioning that same user. It preserves existing server claims and never accepts a requested uid/role from the client. Tests use real signed local JWTs and mocked Google administration calls; the live integration is not tested yet.

The Pages Function needs `FIREBASE_PROJECT_ID` and a server-only `GOOGLE_SERVICE_ACCOUNT` JSON secret for the same project. Use a dedicated account with only the Firebase user read/update permissions required by the bootstrap. Do not paste its private key into chat or Git. Add it directly to encrypted deployment secrets after reviewing its permissions. Do not grant client-selected roles or enable paid Firebase Functions. The browser deliberately refuses database access without the claim. Add deployment-level abuse/rate limiting before opening registration widely.

## Cloudflare Free

Connect the GitHub repository to Cloudflare Pages on Free. Build command `npm run build`, output `dist`. Add the six public environment variables and the deployment hostname to Firebase Authorized domains. Do not switch to a paid plan or add billing-only services. No public personal content is included in the bundle.

## Validation gates before inviting relatives

- `npm ci` and `npm run build`.
- Apply the two schema migrations to a new test database and run both SQL tests; scripts roll back fixtures.
- Complete real signup, email verification, sign-in, password reset and sign-out.
- Test two different accounts/families and check reference photos stay private.
- Test single-use invitation acceptance, revoked/expired links and reader restrictions end-to-end.
- Test phone/tablet/desktop in browser. CSS breakpoints alone are not evidence of visual testing.
- Implement and validate comic-only guest sharing and the generation runner before offering them in the new app.

Keep the current Site, production schedule and guest links active until migration has been backed up and verified.
