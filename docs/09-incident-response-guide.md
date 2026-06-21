# Incident Response Guide

## Purpose

This guide explains what to do when Yanegi production breaks or user data may be at risk.

## Severity Levels

### SEV-1

Critical production issue.

Examples:

- App unusable
- Authentication broken
- User data exposed
- Production database damaged
- Major security issue

Response:

- Immediate action
- Founder and senior engineer notified
- Stop deploys
- Begin rollback or mitigation

### SEV-2

Major user-facing issue.

Examples:

- Event joining broken
- Chat broken for many users
- Notifications failing broadly
- Storage uploads failing

Response:

- Same-day fix or rollback
- Status updates until resolved

### SEV-3

Moderate issue.

Examples:

- One screen broken
- Workaround exists
- Limited user impact

Response:

- Fix in next patch release

### SEV-4

Low-risk issue.

Examples:

- Cosmetic bug
- Minor copy issue
- Low-priority UI bug

Response:

- Add to backlog

## First Response Steps

1. Confirm the issue.
2. Stop related deployments.
3. Assign an incident owner.
4. Notify founder/senior team.
5. Capture logs, screenshots, timestamps, and affected user reports.
6. Determine severity.
7. Decide mitigation or rollback.
8. Communicate status internally.

## Common Incidents

### Auth Failure

Check:

- Firebase Auth status
- Recent auth code changes
- Cloud Function errors
- Provider configuration
- App config

### Firestore Permission Denied

Check:

- Firestore rules deploy
- User auth state
- Collection path
- Required fields
- Recent schema changes

### Cloud Function Failure

Check:

- Function logs
- Environment variables
- Recent deploy
- External API failures
- Permission/IAM issues

### Push Notification Failure

Check:

- FCM token storage
- Invalid tokens
- Cloud Function logs
- Notification payload
- iOS/Android permissions

### Firestore Cost Spike

Check:

- New listeners
- Broad queries
- Chat/message reads
- Map/event discovery reads
- Notification reads

Immediate actions:

- Disable risky feature if possible.
- Reduce listener scope.
- Add pagination/limits.

## Rollback Process

Rollback options:

- Revert app release.
- Redeploy previous Cloud Functions.
- Restore previous Firestore rules.
- Restore previous Storage rules.
- Disable feature remotely if supported.

## Communication

Internal updates should include:

- Current status
- Impact
- Owner
- Next action
- Estimated next update time

For SEV-1 or SEV-2:

- Updates every 30-60 minutes.
- Postmortem required.

## Postmortem Template

Include:

- Incident title
- Severity
- Start time
- End time
- Affected users/features
- Root cause
- What fixed it
- What went well
- What went poorly
- Prevention actions
- Owners and deadlines

