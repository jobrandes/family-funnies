#!/usr/bin/env bash
# Run from the owner's Google Cloud Shell. No private key is created/downloaded.
# Grants the single main-branch activation workflow permission to impersonate
# the existing dedicated service account. No billing/policy changes are made.
set -euo pipefail
project_id='family-funnies'
repository_id='1452076285'
repository_owner_id='10978577'
pool_id='family-funnies-github'
provider_id='github'
project_number="$(gcloud projects describe "$project_id" --format='value(projectNumber)')"
if [[ "$project_number" != '929936102134' ]]; then echo 'Unexpected project. Stopped.' >&2; exit 1; fi
mapfile -t accounts < <(gcloud iam service-accounts list --project="$project_id" --filter='displayName="Family Funnies Login"' --format='value(email)')
if [[ "${#accounts[@]}" != 1 ]]; then echo 'Expected exactly one Family Funnies Login service account. Stopped.' >&2; exit 1; fi
account_email="${accounts[0]}"
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com cloudresourcemanager.googleapis.com --project="$project_id"
if ! gcloud iam workload-identity-pools describe "$pool_id" --location=global --project="$project_id" >/dev/null 2>&1; then
 gcloud iam workload-identity-pools create "$pool_id" --location=global --project="$project_id" --display-name='Family Funnies GitHub login'
fi
condition="assertion.repository_id == '$repository_id' && assertion.repository_owner_id == '$repository_owner_id' && assertion.ref == 'refs/heads/main' && assertion.workflow_ref == 'jobrandes/family-funnies/.github/workflows/activate-accounts.yml@refs/heads/main' && assertion.event_name in ['schedule','workflow_dispatch']"
if gcloud iam workload-identity-pools providers describe "$provider_id" --workload-identity-pool="$pool_id" --location=global --project="$project_id" >/dev/null 2>&1; then
 echo 'Provider already exists. Review its settings before changing trust; no changes applied.' >&2; exit 1
fi
gcloud iam workload-identity-pools providers create-oidc "$provider_id" --location=global --workload-identity-pool="$pool_id" --project="$project_id" --issuer-uri='https://token.actions.githubusercontent.com' --attribute-mapping='google.subject=assertion.sub,attribute.repository_id=assertion.repository_id' --attribute-condition="$condition"
gcloud iam service-accounts add-iam-policy-binding "$account_email" --project="$project_id" --role='roles/iam.workloadIdentityUser' --member="principalSet://iam.googleapis.com/projects/$project_number/locations/global/workloadIdentityPools/$pool_id/attribute.repository_id/$repository_id"
printf '\nAdd these two PUBLIC GitHub Actions repository variables:\nWIF_PROVIDER=projects/%s/locations/global/workloadIdentityPools/%s/providers/%s\nWIF_SERVICE_ACCOUNT=%s\n' "$project_number" "$pool_id" "$provider_id" "$account_email"
