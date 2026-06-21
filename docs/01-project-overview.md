# Yanegi Project Overview

## Purpose

Yanegi is a social event platform. The app helps users create profiles, discover nearby events, host events, join events, connect with other users, chat in groups or DMs, and receive notifications.

This document gives new team members a high-level understanding of the product, technology stack, feature areas, and safety rules before they touch the codebase.

## Product Summary

Yanegi is built around real-world social discovery. The core product promise is:

- Help users find relevant social events.
- Help hosts create and manage events.
- Help users build trust through profiles, friends, chats, and notifications.
- Make discovery location-aware and socially useful.

Because the app is live and real users exist, every engineering decision must protect production data, user privacy, and app reliability.

## Current Stack

- Frontend: Flutter
- Backend: Firebase
- Authentication: Firebase Auth
- Database: Cloud Firestore
- Storage: Firebase Storage
- Notifications: Firebase Cloud Messaging
- Server logic: Firebase Cloud Functions
- Maps: Mapbox
- Email delivery: Resend, if enabled for OTP

## Core User Flows

### Authentication

Users sign in with supported auth methods such as Google Sign-In and Email OTP. The same email must always resolve to the same Firebase Auth user to avoid duplicate accounts.

### Onboarding

Users create or complete a profile. Profile quality matters because Yanegi depends on trust. Users may be allowed to browse with an incomplete profile, but high-trust actions should require profile completion.

### Profile

Users manage name, username, photo, bio, social information, preferences, and visibility settings.

### Event Discovery

Users discover events through feeds, filters, maps, and social context.

### Event Creation

Hosts create event details, location, media, time, rules, and capacity.

### Event Joining

Users request or confirm participation depending on event type and privacy rules.

### Chat

Users communicate through DMs or group chats. Chat must be paginated and optimized to prevent Firestore read cost blowups.

### Notifications

Users receive activity, event, friend, chat, and request notifications through in-app notification records and push notifications.

## Important Engineering Principles

- Production data must never be used casually for testing.
- Interns should not access production Firebase, production secrets, or production user data.
- All risky changes must go through staging first.
- Firestore reads must be treated as a billable resource.
- Realtime listeners must be used carefully.
- User identity must be stable and deduplicated.
- Security rules must protect user data even if the client has bugs.

## High-Risk Areas

- Authentication and duplicate user creation
- Firestore security rules
- Chat listeners
- Event discovery queries
- Map loading behavior
- Image upload and delivery
- Cloud Functions errors
- Push notification reliability
- Production secrets
- Release workflow

## Definition of a Safe Change

A change is safe when:

- It has a clear owner.
- It is tested locally and in staging.
- It does not expose secrets.
- It does not increase Firestore reads without review.
- It does not weaken security rules.
- It has rollback steps if production breaks.

