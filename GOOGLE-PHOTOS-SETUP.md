# Google Photos public launch

Owner console: https://console.cloud.google.com/auth/clients?project=family-funnies

Existing web OAuth client: `929936102134-o18oh20rba3m09hu5qdfqm2fo4jq7di5.apps.googleusercontent.com` (public identifier).

1. Add `https://family-funnies.pages.dev` to that client's **Authorized JavaScript origins**. Keep the existing app origin so its Google Photos feature keeps working.
2. Confirm Photos Picker API is enabled and the requested scope is `https://www.googleapis.com/auth/photospicker.mediaitems.readonly`.
3. Review **Google Auth Platform → Audience**. A Testing app only accepts approved testers. Follow Google's publishing and scope-verification requirements before advertising availability to any account. Test-user registration is not a public launch.
4. Complete the consent branding, support contact and privacy/domain requirements in Google Cloud. Do not make promises in the privacy policy that the implementation does not satisfy.
5. Use an external Google account to sign into the app, create a test family, add a person, choose multiple photos, press Done, and verify the photos persist after reopening the profile. Then verify another account cannot access that family.

No OAuth client secret is needed for the browser token flow. Never put administrative credentials or Google access tokens into this repository, URLs, logs or browser persistent storage. Tokens are kept in memory for the selection and import, then discarded. The backend retrieves only selected photo IDs from the authenticated Picker session, rather than accepting arbitrary download URLs.

Reference docs:
- https://developers.google.com/photos/picker/guides/get-started-picker
- https://developers.google.com/identity/oauth2/web/guides/use-token-model
- https://developers.google.com/photos/picker/guides/sessions
