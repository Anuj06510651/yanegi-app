import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'media_storage_service.dart';
import 'rate_limiter_service.dart';
import '../utils/media_url_resolver.dart';

class UserService {
  UserService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    MediaStorageService? mediaStorageService,
    RateLimiterService? rateLimiter,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _mediaStorageService = mediaStorageService ?? MediaStorageService(),
        _rateLimiter = rateLimiter ??
            RateLimiterService(firestore: firestore, auth: auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final MediaStorageService _mediaStorageService;
  final RateLimiterService _rateLimiter;
  static const int _maxUsernameEditsPerMonth = 2;

  // Collection reference
  CollectionReference get _users => _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  DocumentReference<Map<String, dynamic>> _mainSettingsRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('main');
  }

  // Idempotent: safe to call from multiple bootstrap paths (AuthBootstrapper,
  // Google handler, OTP handler) without a TOCTOU race. The exists-check
  // runs inside the same Firestore transaction as the set, so concurrent
  // callers are serialized at the document and the second one sees `exists`
  // and returns early. Callers MUST invoke this before any other merge-set
  // on the user doc so that immutable fields like createdAt are established.
  Future<void> createOrGetUser({
    required String uid,
    String? email,
    String? authProvider,
  }) async {
    final normalizedEmail = (email ?? '').trim().toLowerCase();
    final userRef = _users.doc(uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (snapshot.exists) return;

      final now = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{
        'userId': uid,
        'uid': uid,
        'email': normalizedEmail,
        'hasCompletedProfile': false,
        'createdAt': now,
        'updatedAt': now,
        'created_at': now,
        'updated_at': now,
      };

      if (authProvider != null && authProvider.trim().isNotEmpty) {
        payload['authProvider'] = authProvider.trim();
      }

      debugPrint('USER WRITE START: UserService createOrGetUser (txn)');
      debugPrint('USER WRITE UID: $uid');
      debugPrint('USER WRITE PAYLOAD: ${payload.keys.toList()}');
      transaction.set(userRef, payload, SetOptions(merge: true));
      debugPrint('USER WRITE SUCCESS: UserService createOrGetUser (txn enqueued)');
    });
  }

  // Create or Update User
  Future<void> saveUser({
    required String name,
    required String username,
    String? gender,
    DateTime? dob,
    String? avatarUrl,
    String? bio,
    List<String>? vibes,
    String? onboardingStep,
    bool? hasCompletedProfile,
  }) async {
    final user = _auth.currentUser;
    if (user != null) {
      String? finalAvatarUrl = avatarUrl;

      // Upload avatar to Firebase Storage if it's a local file path
      if (avatarUrl != null && !avatarUrl.startsWith('http')) {
        final file = File(avatarUrl);
        if (!file.existsSync()) {
          throw Exception('Selected image not found. Please pick it again.');
        }

        try {
          finalAvatarUrl = await _mediaStorageService.uploadProfileImage(
            userId: user.uid,
            localFilePath: avatarUrl,
          );
          print(
              'TESTING [STORAGE UPLOAD]: Successfully uploaded avatar for UID: ${user.uid} | URL: $finalAvatarUrl');
        } catch (e) {
          debugPrint('Upload failed: $e');
          throw Exception('Image upload failed. Please try again.');
        }
      }

      if (finalAvatarUrl != null && !finalAvatarUrl.startsWith('http')) {
        finalAvatarUrl = null;
      }

      try {
        final docRef = _users.doc(user.uid);
        final existingDoc = await docRef.get();
        final existingData = existingDoc.data() as Map<String, dynamic>?;
        final normalizedAvatarUrl = resolveRemoteMediaUrl(<dynamic>[
          finalAvatarUrl,
          existingData?['photoUrl'],
          existingData?['avatarUrl'],
          existingData?['avatar_url'],
        ]);

        debugPrint('USER WRITE START: UserService saveUser');
        debugPrint('USER WRITE UID: ${user.uid}');
        debugPrint('USER WRITE PAYLOAD: name, username, bio, photoUrl, email, hasCompletedProfile, ...');

        // Use update() so only allowlisted fields are touched.
        // userId, uid, createdAt, created_at are NOT in the update allowlist
        // and are already set by createOrGetUser — do not re-write them.
        final Map<String, dynamic> payload = {
          'name': name,
          'username': username,
          'usernameLower': username.startsWith('@')
              ? username.substring(1).toLowerCase()
              : username.toLowerCase(),
          'bio': bio,
          'photoUrl': normalizedAvatarUrl,
          'avatarUrl': normalizedAvatarUrl,
          'avatar_url': normalizedAvatarUrl,
          'email': user.email ?? existingData?['email'] ?? '',
          'hasCompletedProfile': hasCompletedProfile ??
              (existingData?['hasCompletedProfile'] ?? false),
          'phone': _normalizePhone(user.phoneNumber) ?? existingData?['phone'],
          'profileVisibility': existingData?['profileVisibility'] ?? true,
          'bannerUrl': existingData?['bannerUrl'],
          'banner_url': existingData?['banner_url'] ?? existingData?['bannerUrl'],
          'gender': gender,
          'dob': dob?.toIso8601String(),
          'vibes': vibes ?? [],
          'usernameEditCount': existingData?['usernameEditCount'] ?? 0,
          'lastEditTime': existingData?['lastEditTime'],
          'updatedAt': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        };
        await docRef.update(payload);
        debugPrint('USER WRITE SUCCESS: UserService saveUser');
        print(
            'TESTING [FIRESTORE WRITE]: Successfully saved user data for UID: ${user.uid} | Fields: name=$name, username=$username, gender=$gender, vibes=$vibes, avatarUrl=$finalAvatarUrl');
      } catch (e) {
        debugPrint('USER WRITE FAILED: UserService saveUser: $e');
        print(
            'TESTING [ERROR]: Firestore write failed for UID: ${user.uid} with error: $e');
        rethrow;
      }
    } else {
      print(
          'TESTING [ERROR]: Cannot save user data, no authenticated user found.');
    }
  }

  Future<void> saveOnboardingProfile({
    required String name,
    required String username,
    required String bio,
    String? avatarUrl,
    String onboardingStep = 'photo',
    bool hasCompletedProfile = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
          'Cannot save onboarding profile: no authenticated user.');
    }

    String? finalAvatarUrl = avatarUrl;
    if (avatarUrl != null &&
        avatarUrl.isNotEmpty &&
        !avatarUrl.startsWith('http')) {
      final file = File(avatarUrl);
      if (file.existsSync()) {
        finalAvatarUrl = await _mediaStorageService.uploadProfileImage(
          userId: user.uid,
          localFilePath: avatarUrl,
        );
      }
    }

    if (finalAvatarUrl != null && !finalAvatarUrl.startsWith('http')) {
      finalAvatarUrl = null;
    }

    final docRef = _users.doc(user.uid);
    final existingDoc = await docRef.get();
    final existingData = existingDoc.data() as Map<String, dynamic>?;
    final existingCreatedAt =
        existingData?['createdAt'] ?? existingData?['created_at'];
    final normalizedAvatarUrl = resolveRemoteMediaUrl(<dynamic>[
      finalAvatarUrl,
      existingData?['photoUrl'],
      existingData?['avatarUrl'],
      existingData?['avatar_url'],
    ]);

    debugPrint('USER WRITE START: UserService saveOnboardingProfile');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: name, username, bio, photoUrl, email, hasCompletedProfile, ...');
    await docRef.set({
      'userId': user.uid,
      'uid': user.uid,
      'name': name,
      'username': username,
      'usernameLower': username.startsWith('@')
          ? username.substring(1).toLowerCase()
          : username.toLowerCase(),
      'bio': bio,
      'photoUrl': normalizedAvatarUrl,
      'avatarUrl': normalizedAvatarUrl,
      'email': user.email ?? existingData?['email'] ?? '',
      'phone': _normalizePhone(user.phoneNumber) ?? existingData?['phone'],
      'hasCompletedProfile': hasCompletedProfile,
      'profileVisibility': existingData?['profileVisibility'] ?? true,
      'bannerUrl': existingData?['bannerUrl'],
      'createdAt': existingCreatedAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'usernameEditCount': existingData?['usernameEditCount'] ?? 0,
      'lastEditTime': existingData?['lastEditTime'],

      // Backward compatibility
      'avatar_url': normalizedAvatarUrl,
      'banner_url': existingData?['banner_url'] ?? existingData?['bannerUrl'],
      'created_at': existingData?['created_at'] ??
          existingCreatedAt ??
          FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService saveOnboardingProfile');
  }

  // Get User
  Future<Map<String, dynamic>?> getUser(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      if (doc.exists) {
        print(
            'TESTING [FIRESTORE READ]: Successfully read user data for UID: $uid');
        return doc.data() as Map<String, dynamic>;
      }
      print('TESTING [FIRESTORE READ]: User document not found for UID: $uid');
      return null;
    } catch (e) {
      print(
          'TESTING [ERROR]: Firestore read failed for UID: $uid with error: $e');
      return null;
    }
  }

  Stream<Map<String, dynamic>?> watchCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream<Map<String, dynamic>?>.empty();
    }
    return _users
        .doc(user.uid)
        .snapshots()
        .map((doc) => _normalizeUserData(doc.data() as Map<String, dynamic>?));
  }

  Future<Map<String, dynamic>?> refreshCurrentUserProfile({
    bool forceServer = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    await user.reload();
    final snapshot = await _users.doc(user.uid).get(
          GetOptions(
            source: forceServer ? Source.server : Source.serverAndCache,
          ),
        );
    final normalized = _normalizeUserData(
      snapshot.data() as Map<String, dynamic>?,
    );
    // Write-back removed: spreading the entire doc (including any legacy
    // denied fields like isOnline/location) would cause PERMISSION_DENIED
    // under the field-allowlist update rule.
    debugPrint('USER WRITE SKIPPED: UserService refreshCurrentUserProfile — write-back removed to avoid allowlist violation');
    return normalized;
  }

  Future<void> updateProfileFields({
    required String name,
    required String username,
    required String bio,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final normalizedUsername = _normalizeUsername(username);
    final nextUsernameLower = normalizedUsername;
    final trimmedPhoto = resolveRemoteMediaUrl(<dynamic>[photoUrl]);

    if (nextUsernameLower.isEmpty) {
      throw StateError('Username is required.');
    }

    final quotaCheck =
        await _rateLimiter.check(RateLimiterService.profileUpdatePerDay);
    if (!quotaCheck.allowed) {
      throw StateError(
        'You’ve updated your profile a lot today. Please try again later.',
      );
    }

    await updateUsername(normalizedUsername);

    final userRef = _users.doc(user.uid);

    final payload = <String, dynamic>{
      'userId': user.uid,
      'uid': user.uid,
      'name': name.trim(),
      'username': normalizedUsername,
      'usernameLower': nextUsernameLower,
      'bio': bio.trim(),
      'email': user.email,
      'phone': _normalizePhone(user.phoneNumber),
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (trimmedPhoto.isNotEmpty) {
      payload['photoUrl'] = trimmedPhoto;
      payload['avatarUrl'] = trimmedPhoto;
      payload['avatar_url'] = trimmedPhoto;
    }

    debugPrint('USER WRITE START: UserService updateProfileFields');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: ${payload.keys.toList()}');
    await userRef.set(payload, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService updateProfileFields');
    unawaited(_rateLimiter.record(RateLimiterService.profileUpdatePerDay));
  }

  Future<bool> checkUsernameAvailable(String username) async {
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty) return false;

    final user = _auth.currentUser;
    final usernameDoc = await _usernames.doc(normalized).get();
    if (!usernameDoc.exists) return true;

    final claimedBy =
        ((usernameDoc.data()?['uid'] ?? usernameDoc.data()?['userId']) ?? '')
            .toString()
            .trim();

    return user != null && claimedBy == user.uid;
  }

  Future<UsernameQuotaStatus> getUsernameQuotaStatus({String? uid}) async {
    final targetUid = (uid ?? _auth.currentUser?.uid ?? '').trim();
    if (targetUid.isEmpty) {
      return const UsernameQuotaStatus(usedThisMonth: 0, remaining: 2);
    }

    final doc = await _users.doc(targetUid).get();
    final data = doc.data() as Map<String, dynamic>?;

    final now = DateTime.now().toUtc();
    final lastEditTime = _toDateTime(data?['lastEditTime']);
    final isSameMonth = lastEditTime != null && _isSameMonth(lastEditTime, now);
    final used = isSameMonth ? _toInt(data?['usernameEditCount']) : 0;
    final boundedUsed = used.clamp(0, _maxUsernameEditsPerMonth);
    final remaining = (_maxUsernameEditsPerMonth - boundedUsed)
        .clamp(0, _maxUsernameEditsPerMonth);

    return UsernameQuotaStatus(
      usedThisMonth: boundedUsed,
      remaining: remaining,
    );
  }

  Future<void> updateUsername(String newUsername) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final normalized = _normalizeUsername(newUsername);
    if (normalized.isEmpty) {
      throw StateError('Username is required.');
    }

    final userRef = _users.doc(user.uid);
    final newUsernameRef = _usernames.doc(normalized);

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data() as Map<String, dynamic>?;
      final currentUsernameLower =
          (userData?['usernameLower'] as String?)?.trim().toLowerCase() ??
              _normalizeUsername((userData?['username'] as String?) ?? '');
      final usernameChanged = currentUsernameLower != normalized;

      final now = DateTime.now().toUtc();
      final lastEditTime = _toDateTime(userData?['lastEditTime']);
      final withinSameMonth =
          lastEditTime != null && _isSameMonth(lastEditTime, now);
      final existingCount = _toInt(userData?['usernameEditCount']);
      final effectiveCount = withinSameMonth ? existingCount : 0;

      if (usernameChanged && effectiveCount >= _maxUsernameEditsPerMonth) {
        throw StateError('Limit reached');
      }

      final newUsernameSnapshot = await transaction.get(newUsernameRef);
      final claimedBy = ((newUsernameSnapshot.data()?['uid'] ??
                  newUsernameSnapshot.data()?['userId']) ??
              '')
          .toString()
          .trim();

      if (newUsernameSnapshot.exists && claimedBy != user.uid) {
        throw StateError('Username taken');
      }

      final nowTs = FieldValue.serverTimestamp();

      transaction.set(
        newUsernameRef,
        {
          'uid': user.uid,
          'userId': user.uid,
          'username': normalized,
          'updatedAt': nowTs,
          'createdAt': newUsernameSnapshot.exists
              ? (newUsernameSnapshot.data()?['createdAt'] ?? nowTs)
              : nowTs,
        },
        SetOptions(merge: true),
      );

      if (usernameChanged &&
          currentUsernameLower.isNotEmpty &&
          currentUsernameLower != normalized) {
        final oldUsernameRef = _usernames.doc(currentUsernameLower);
        final oldUsernameSnapshot = await transaction.get(oldUsernameRef);
        final oldClaimedBy = ((oldUsernameSnapshot.data()?['uid'] ??
                    oldUsernameSnapshot.data()?['userId']) ??
                '')
            .toString()
            .trim();
        if (oldUsernameSnapshot.exists && oldClaimedBy == user.uid) {
          transaction.delete(oldUsernameRef);
        }
      }

      final payload = <String, dynamic>{
        'username': normalized,
        'usernameLower': normalized,
        'updatedAt': nowTs,
        'updated_at': nowTs,
      };

      if (usernameChanged) {
        payload['usernameEditCount'] = effectiveCount + 1;
        payload['lastEditTime'] = nowTs;
      } else if (!withinSameMonth && existingCount != 0) {
        payload['usernameEditCount'] = 0;
      }

      debugPrint('USER WRITE START: UserService updateUsername (txn)');
      debugPrint('USER WRITE UID: ${user.uid}');
      debugPrint('USER WRITE PAYLOAD: ${payload.keys.toList()}');
      transaction.set(userRef, payload, SetOptions(merge: true));
      debugPrint('USER WRITE SUCCESS: UserService updateUsername (txn enqueued)');
    });
  }

  Map<String, dynamic>? _normalizeUserData(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;

    final normalizedPhotoUrl = resolveRemoteMediaUrl(<dynamic>[
      data['photoUrl'],
      data['avatarUrl'],
      data['avatar_url'],
      data['profileImage'],
      data['profile_image'],
    ]);
    final normalizedBannerUrl = resolveRemoteMediaUrl(<dynamic>[
      data['bannerUrl'],
      data['banner_url'],
      data['bannerImage'],
      data['banner_image'],
    ]);

    return <String, dynamic>{
      ...data,
      'photoUrl': normalizedPhotoUrl,
      'avatarUrl': normalizedPhotoUrl,
      'avatar_url': normalizedPhotoUrl,
      'bannerUrl': normalizedBannerUrl,
      'banner_url': normalizedBannerUrl,
    };
  }

  Future<void> updateProfileVisibility({required bool isVisible}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }
    debugPrint('USER WRITE START: UserService updateProfileVisibility');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: {profileVisibility, updatedAt, updated_at}');
    await _users.doc(user.uid).set({
      'profileVisibility': isVisible,
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService updateProfileVisibility');
  }

  Future<void> updateEmail({required String newEmail}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final normalizedEmail = newEmail.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    await user.verifyBeforeUpdateEmail(normalizedEmail);
    debugPrint('USER WRITE START: UserService updateEmail');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: {email, updatedAt, updated_at}');
    await _users.doc(user.uid).set({
      'email': normalizedEmail,
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService updateEmail');
  }

  Future<void> syncAuthContactFields() async {
    final user = _auth.currentUser;
    if (user == null) return;

    debugPrint('USER WRITE START: UserService syncAuthContactFields');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: {email, phone, updatedAt, updated_at}');
    await _users.doc(user.uid).set({
      'email': user.email,
      'phone': _normalizePhone(user.phoneNumber),
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService syncAuthContactFields');
  }

  Future<void> updateFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;

    debugPrint('USER WRITE START: UserService updateFcmToken');
    debugPrint('USER WRITE UID: ${user.uid}');
    debugPrint('USER WRITE PAYLOAD: {fcmToken, fcmTokenUpdatedAt, updatedAt, updated_at}');
    await _users.doc(user.uid).set({
      'fcmToken': normalizedToken,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('USER WRITE SUCCESS: UserService updateFcmToken');
  }

  Future<bool> getPushNotificationsEnabled({bool defaultValue = true}) async {
    final user = _auth.currentUser;
    if (user == null) return defaultValue;

    final doc = await _mainSettingsRef(user.uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final raw = data['pushNotifications'];
    if (raw is bool) return raw;
    return defaultValue;
  }

  Future<void> setPushNotificationsEnabled(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await _mainSettingsRef(user.uid).set({
      'pushNotifications': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> getNearbyActivityEnabled({bool defaultValue = true}) async {
    final user = _auth.currentUser;
    if (user == null) return defaultValue;

    final doc = await _mainSettingsRef(user.uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final raw = data['nearbyActivity'];
    if (raw is bool) return raw;
    return defaultValue;
  }

  Future<void> setNearbyActivityEnabled(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await _mainSettingsRef(user.uid).set({
      'nearbyActivity': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> getShowProfileInEventsEnabled({bool defaultValue = true}) async {
    final user = _auth.currentUser;
    if (user == null) return defaultValue;

    final doc = await _mainSettingsRef(user.uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final raw = data['showProfileInEvents'];
    if (raw is bool) return raw;
    return defaultValue;
  }

  Future<void> setShowProfileInEventsEnabled(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await _mainSettingsRef(user.uid).set({
      'showProfileInEvents': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String? _normalizePhone(String? raw) {
    final value = (raw ?? '').trim();
    return value.isEmpty ? null : value;
  }

  String _normalizeUsername(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('@')) {
      value = value.substring(1);
    }
    return value;
  }

  DateTime? _toDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) return DateTime.tryParse(raw)?.toUtc();
    return null;
  }

  int _toInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }
}

class UsernameQuotaStatus {
  final int usedThisMonth;
  final int remaining;

  const UsernameQuotaStatus({
    required this.usedThisMonth,
    required this.remaining,
  });

  bool get exhausted => remaining <= 0;
}
