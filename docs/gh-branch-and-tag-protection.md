# Lock down main and tags with GitHub CLI

This guide sets up repository protections so that:
- Only reviews from `@nsuberi` count for merging to `main` (via Code Owners + required code owner review)
- Direct pushes to `main` are disallowed, even for admins (merges via PR only)
- Only `@nsuberi` can create tags (using a repository ruleset)

Notes:
- GitHub does not support “only this user’s approval counts” as a pure branch setting. The supported way is to require Code Owner reviews and make `@nsuberi` the Code Owner for the repo. Update `CODEOWNERS` accordingly (e.g., add a rule `* @nsuberi`).
- Tag protections are deprecated. Use repository rulesets to restrict tag creation to `@nsuberi`.

## Commands

Set variables (optional):
```bash
REPO="nsuberi/llm-orchestration-eval-platform"
BRANCH="main"
```

Protect `main` (require PRs, require Code Owner review, include admins so no direct pushes):
```bash
cat > /tmp/branch_protection.json <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true
}
JSON

# Apply branch protection
gh api -X PUT \
  -H "Accept: application/vnd.github+json" \
  repos/${REPO}/branches/${BRANCH}/protection \
  --input /tmp/branch_protection.json
```

Create a repository ruleset to allow only `@nsuberi` to create tags:
```bash
N_ID=$(gh api users/nsuberi --jq '.id')

cat > /tmp/tag_ruleset.json <<'JSON'
{
  "name": "restrict-tag-creation",
  "target": "tag",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["refs/tags/*"], "exclude": [] }
  },
  "bypass_actors": [{ "actor_id": N_ID_PLACEHOLDER, "actor_type": "User", "bypass_mode": "always" }],
  "rules": [
    { "type": "creation", "parameters": { "block": true } }
  ]
}
JSON

# Inject the numeric user id for @nsuberi and create the ruleset
sed -i.bak "s/N_ID_PLACEHOLDER/${N_ID}/g" /tmp/tag_ruleset.json
gh api -X POST \
  -H "Accept: application/vnd.github+json" \
  repos/${REPO}/rulesets \
  --input /tmp/tag_ruleset.json
```

Verification:
- Open the repo Settings → Branches: `main` should show protections, “Include administrators” enabled
- Settings → Rules → Rulesets: a ruleset named `restrict-tag-creation` should be listed and active

Roll back (if needed):
```bash
# Remove branch protection
gh api -X DELETE -H "Accept: application/vnd.github+json" repos/${REPO}/branches/${BRANCH}/protection

# List tag protections
gh api -H "Accept: application/vnd.github+json" repos/${REPO}/tags/protection

# Delete tag protection by pattern (substitute the id from list if endpoint requires)
# Some gh/server versions support: gh api -X DELETE repos/${REPO}/tags/protection --input <(jq -n '{pattern:"*"}')
```