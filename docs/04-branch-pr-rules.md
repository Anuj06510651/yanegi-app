# Branch and Pull Request Rules

## Purpose

This guide prevents broken releases, unreviewed code, direct production changes, and merge conflicts.

## Protected Branches

### main

Purpose:

- Production-ready code only.
- Every commit should be releasable.

Rules:

- No direct pushes.
- Pull request required.
- Senior review required.
- CI must pass.

### develop

Purpose:

- Staging integration branch.
- Features merge here before production.

Rules:

- Pull request required.
- Feature owner review required.
- Must remain stable enough for QA.

## Branch Naming

Use clear branch names:

```text
feature/auth-otp
feature/event-map-filters
fix/chat-pagination
fix/profile-image-upload
hotfix/prod-login-crash
docs/firebase-staging-guide
refactor/event-service-cleanup
```

## Pull Request Requirements

Every PR must include:

- What changed
- Why it changed
- Screens affected
- Firebase collections affected
- Security rules affected
- Testing completed
- Risk level
- Screenshots for UI changes

## PR Size

Preferred:

- Small PRs
- One feature or fix per PR
- Avoid mixing refactor and feature work

Avoid:

- Large unrelated changes
- Formatting entire unrelated files
- Changing shared services without review

## Review Rules

Required reviewers:

- Feature owner
- Senior engineer for auth, rules, payment, release, or backend changes
- UI reviewer for visual changes

Intern PRs:

- Must be reviewed by a senior or feature owner
- Cannot self-approve
- Cannot deploy production

## Merge Strategy

Preferred:

- Squash merge for feature branches
- Clear PR title
- Clear release notes

Do not merge if:

- Tests fail
- Analyzer fails
- Reviewer requested changes
- Firestore rules are unclear
- Production credentials are included

## Hotfix Process

For urgent production issues:

```text
main -> hotfix/name -> PR -> main -> develop
```

Hotfix must include:

- Problem summary
- Fix summary
- Rollback plan
- Post-release monitoring owner

