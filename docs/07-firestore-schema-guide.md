# Firestore Schema Guide

## Purpose

This guide documents Firestore collections, ownership, security expectations, and cost risks. It prevents random schema drift and duplicate data models.

## General Schema Rules

- User documents should use Firebase Auth UID as document ID.
- Emails must be normalized with trim and lowercase.
- Usernames must be normalized with trim and lowercase.
- Avoid unbounded arrays.
- Use subcollections for growing data.
- Use timestamps consistently.
- Add indexes intentionally.
- Never rely only on client-side validation.

## users/{uid}

Purpose:

Stores user account and profile data.

Required fields:

- uid
- email
- name
- username
- hasCompletedProfile
- createdAt
- updatedAt

Optional fields:

- bio
- photoUrl
- avatarUrl
- gender
- dob
- vibes
- profileVisibility

Security:

- User can read public-safe profile fields.
- User can edit their own editable profile fields.
- Sensitive fields should be backend/admin-only.

Cost risk:

- Repeated profile reads across chat, event, and profile screens.

Optimization:

- Cache profile summaries.
- Use lightweight user summary data in lists.

## usernames/{username}

Purpose:

Reserves usernames and prevents duplicates.

Fields:

- userId
- username
- createdAt
- updatedAt

Security:

- Should only be written through controlled logic.

## events/{eventId}

Purpose:

Stores full event details.

Fields:

- eventId
- hostId
- title
- description
- startTime
- endTime
- location
- visibility
- category
- capacity
- attendeeCount
- status
- createdAt
- updatedAt

Security:

- Host can edit own event.
- Users can read public events.
- Private events require membership/request rules.

Cost risk:

- Loading full event docs in feeds and maps.

Optimization:

- Create lightweight event cards or map marker docs.

## event_requests/{requestId}

Purpose:

Tracks requests to join events.

Fields:

- eventId
- requesterId
- hostId
- status
- createdAt
- updatedAt

Security:

- Requester can create request.
- Host can approve/reject for their event.

## friends/{friendshipId}

Purpose:

Tracks friendships or connection requests.

Fields:

- requesterId
- receiverId
- status
- createdAt
- updatedAt

Security:

- Only involved users can read.
- Only involved users can create/respond.

Cost risk:

- Loading all friends at once.

Optimization:

- Paginate.
- Maintain friend count.

## chats/{chatId}

Purpose:

Stores chat room metadata.

Fields:

- chatId
- memberIds
- lastMessage
- lastMessageAt
- unreadCounts
- isGroup
- createdAt
- updatedAt

Security:

- Only members can read/write.

Cost risk:

- Chat list should not read message history.

Optimization:

- Use parent chat doc for preview.

## chats/{chatId}/messages/{messageId}

Purpose:

Stores chat messages.

Fields:

- senderId
- text
- mediaUrl
- createdAt
- readBy

Security:

- Only chat members can read/write.

Cost risk:

- Realtime listeners reading too many messages.

Optimization:

- Listen to latest 30-50 messages.
- Load older messages manually.

## notifications/{notificationId}

Purpose:

Stores in-app notification records.

Fields:

- userId
- type
- title
- body
- senderId
- eventId
- chatId
- read
- createdAt

Security:

- Only recipient can read.
- Client should not freely create arbitrary notifications.

Optimization:

- Paginate.
- Maintain unread count.
- Delete or archive old notifications.

## email_otps/{email}

Purpose:

Stores hashed OTP records for email authentication.

Fields:

- email
- otpHash
- expiresAt
- lastSentAt
- attempts
- sendCount
- windowStartAt

Security:

- Client must not read or write.
- Only Cloud Functions/Admin SDK should access.

Retention:

- Delete after success.
- Delete expired records through verification or scheduled cleanup.

