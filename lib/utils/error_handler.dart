import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// User-facing failure categories. Every UI surface that needs to report
/// a failure should pick the closest enum value; the [ErrorHandler] maps it
/// to a polished, production-grade message.
///
/// Never expose raw exception strings, Firestore paths, collection names,
/// stack traces, or Firebase error codes to users.
enum AppErrorType {
  // Generic
  generic,
  network,
  permissionDenied,
  notFound,
  rateLimited,
  timeout,
  notSignedIn,
  blocked,

  // Auth
  authGeneric,
  authInvalidEmail,
  authEmailInUse,
  authWrongPassword,
  authWeakPassword,
  authRequiresRecentLogin,
  authVerificationFailed,
  authSignInCancelled,
  authOtpInvalid,

  // Profile
  profileLoadFailed,
  profileSaveFailed,
  profileUsernameTaken,
  profileVisibilityUpdateFailed,
  profileThemeUpdateFailed,

  // Friends
  friendRequestSendFailed,
  friendRequestAcceptFailed,
  friendRequestDeclineFailed,
  friendRemoveFailed,
  friendsLoadFailed,
  friendBlocked,

  // Events
  eventLoadFailed,
  eventCreateFailed,
  eventCreateRateLimited,
  eventJoinFailed,
  eventLeaveFailed,
  eventJoinRequestFailed,
  eventApproveFailed,
  eventRejectFailed,
  eventShareFailed,
  eventDeleteFailed,
  eventFull,

  // Chat
  chatLoadFailed,
  chatSendFailed,
  chatUnavailable,
  chatImageUploadFailed,

  // Notifications
  notificationsLoadFailed,
  notificationsUnavailable,

  // Image / Media
  imagePickFailed,
  imageUploadFailed,
  imageDeleteFailed,
  bucketUnavailable,

  // Map / Location
  locationServiceDisabled,
  locationPermissionDenied,
  locationLookupFailed,

  // Search
  searchFailed,

  // Settings
  settingsUpdateFailed,
  emailUpdateFailed,
  accountDeactivateFailed,
  accountDeleteFailed,

  // Memories
  memoryAddFailed,
  memoryLoadFailed,

  // Reporting / Feedback
  reportSubmitFailed,
  feedbackSubmitFailed,
}

/// Centralized translator from [AppErrorType] / raw [Object] errors into
/// user-friendly text and SnackBar/Dialog surfaces. Use this everywhere
/// instead of interpolating exceptions into UI strings.
class ErrorHandler {
  ErrorHandler._();

  static const Map<AppErrorType, String> _messages = {
    AppErrorType.generic: 'Something went wrong. Please try again.',
    AppErrorType.network:
        'Connection problem. Please check your internet and try again.',
    AppErrorType.permissionDenied:
        "You don't have access to perform this action.",
    AppErrorType.notFound: "We couldn't find what you were looking for.",
    AppErrorType.rateLimited:
        'You’re doing that a little too quickly. Please wait a moment and try again.',
    AppErrorType.timeout: 'This is taking longer than usual. Please try again.',
    AppErrorType.notSignedIn: 'Please sign in to continue.',
    AppErrorType.blocked: "You can’t interact with this person.",

    AppErrorType.authGeneric:
        'Sign-in failed. Please try again.',
    AppErrorType.authInvalidEmail: 'Please enter a valid email address.',
    AppErrorType.authEmailInUse:
        'That email is already used by another account.',
    AppErrorType.authWrongPassword:
        'The email or password you entered is incorrect.',
    AppErrorType.authWeakPassword:
        'Please choose a stronger password.',
    AppErrorType.authRequiresRecentLogin:
        'Please sign in again, then retry this action.',
    AppErrorType.authVerificationFailed:
        'We couldn’t verify your account. Please try again.',
    AppErrorType.authSignInCancelled:
        'Sign-in was cancelled.',
    AppErrorType.authOtpInvalid:
        'That code is invalid or expired. Please request a new one.',

    AppErrorType.profileLoadFailed: 'We couldn’t load this profile.',
    AppErrorType.profileSaveFailed:
        'Your changes couldn’t be saved. Please try again.',
    AppErrorType.profileUsernameTaken:
        'That username is already taken. Please pick another.',
    AppErrorType.profileVisibilityUpdateFailed:
        'Could not update profile visibility. Please try again.',
    AppErrorType.profileThemeUpdateFailed:
        'Could not update theme. Please try again.',

    AppErrorType.friendRequestSendFailed:
        'Friend request couldn’t be sent.',
    AppErrorType.friendRequestAcceptFailed:
        'Friend request couldn’t be accepted. Please try again.',
    AppErrorType.friendRequestDeclineFailed:
        'Friend request couldn’t be declined. Please try again.',
    AppErrorType.friendRemoveFailed:
        'Could not remove friend right now. Please try again.',
    AppErrorType.friendsLoadFailed: 'We couldn’t load your friends list.',
    AppErrorType.friendBlocked: "You can’t interact with this person.",

    AppErrorType.eventLoadFailed: 'We couldn’t load this event.',
    AppErrorType.eventCreateFailed:
        'Failed to create event. Please try again.',
    AppErrorType.eventCreateRateLimited:
        'You can only create one event every few minutes. Please wait and try again.',
    AppErrorType.eventJoinFailed:
        'Event request couldn’t be processed. Please try again.',
    AppErrorType.eventLeaveFailed:
        'Could not leave the event right now. Please try again.',
    AppErrorType.eventJoinRequestFailed:
        'Your join request couldn’t be sent. Please try again.',
    AppErrorType.eventApproveFailed:
        'Could not approve this request right now. Please try again.',
    AppErrorType.eventRejectFailed:
        'Could not reject this request right now. Please try again.',
    AppErrorType.eventShareFailed:
        'Could not share the event right now. Please try again.',
    AppErrorType.eventDeleteFailed:
        'Could not delete the event right now. Please try again.',
    AppErrorType.eventFull: 'This event is already full.',

    AppErrorType.chatLoadFailed:
        'Chat is temporarily unavailable. Please try again.',
    AppErrorType.chatSendFailed:
        'Your message couldn’t be sent. Please try again.',
    AppErrorType.chatUnavailable: 'Chat is temporarily unavailable.',
    AppErrorType.chatImageUploadFailed:
        'Photo couldn’t be sent. Please try again.',

    AppErrorType.notificationsLoadFailed:
        'We couldn’t load your notifications.',
    AppErrorType.notificationsUnavailable:
        'Notifications are currently unavailable.',

    AppErrorType.imagePickFailed:
        'Could not select image. Please try again.',
    AppErrorType.imageUploadFailed:
        'Photo upload failed. Please try again.',
    AppErrorType.imageDeleteFailed:
        'Could not remove the photo right now. Please try again.',
    AppErrorType.bucketUnavailable:
        'Photo storage is temporarily unavailable. Please try again.',

    AppErrorType.locationServiceDisabled:
        'Location is turned off. Turn it on in Settings to see nearby events.',
    AppErrorType.locationPermissionDenied:
        'Location permission is needed to show nearby events.',
    AppErrorType.locationLookupFailed:
        'We couldn’t get your location. Showing a default area.',

    AppErrorType.searchFailed:
        'Search isn’t working right now. Please try again.',

    AppErrorType.settingsUpdateFailed:
        'Could not update that setting. Please try again.',
    AppErrorType.emailUpdateFailed:
        'Unable to update email right now. Please try again.',
    AppErrorType.accountDeactivateFailed:
        'Could not deactivate your account right now. Please try again.',
    AppErrorType.accountDeleteFailed:
        'Could not delete your account right now. Please try again.',

    AppErrorType.memoryAddFailed:
        'Failed to add memory. Please try again.',
    AppErrorType.memoryLoadFailed: 'We couldn’t load memories right now.',

    AppErrorType.reportSubmitFailed:
        'Could not submit report right now. Please try again.',
    AppErrorType.feedbackSubmitFailed:
        'Could not send feedback right now. Please try again.',
  };

  /// Returns the production-grade message for [type]. Use this when you
  /// already know which failure category applies (preferred).
  static String messageFor(AppErrorType type) =>
      _messages[type] ?? _messages[AppErrorType.generic]!;

  /// Classifies a raw [error] from a `catch` block into the closest
  /// [AppErrorType] using runtime checks against Firebase / Dart exception
  /// shapes. Falls back to [fallback].
  ///
  /// Never call this with user input — it inspects exception types only.
  static AppErrorType classify(Object? error,
      {AppErrorType fallback = AppErrorType.generic}) {
    if (error == null) return fallback;

    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return error is TimeoutException
          ? AppErrorType.timeout
          : AppErrorType.network;
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return AppErrorType.authInvalidEmail;
        case 'email-already-in-use':
          return AppErrorType.authEmailInUse;
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-credential':
          return AppErrorType.authWrongPassword;
        case 'weak-password':
          return AppErrorType.authWeakPassword;
        case 'requires-recent-login':
          return AppErrorType.authRequiresRecentLogin;
        case 'too-many-requests':
          return AppErrorType.rateLimited;
        case 'network-request-failed':
          return AppErrorType.network;
        case 'invalid-verification-code':
        case 'invalid-verification-id':
        case 'expired-action-code':
          return AppErrorType.authOtpInvalid;
        case 'sign-in-cancelled':
        case 'web-context-cancelled':
        case 'popup-closed-by-user':
        case 'canceled':
          return AppErrorType.authSignInCancelled;
        default:
          return AppErrorType.authGeneric;
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return AppErrorType.permissionDenied;
        case 'unavailable':
        case 'deadline-exceeded':
          return AppErrorType.network;
        case 'not-found':
          return AppErrorType.notFound;
        case 'cancelled':
          return AppErrorType.generic;
      }
      // firebase_storage raises FirebaseException with `storage/*` codes.
      switch (error.code) {
        case 'storage/object-not-found':
          return AppErrorType.notFound;
        case 'storage/unauthorized':
          return AppErrorType.permissionDenied;
        case 'storage/retry-limit-exceeded':
        case 'storage/server-file-wrong-size':
          return AppErrorType.imageUploadFailed;
      }
      return fallback;
    }

    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('network')) return AppErrorType.network;
      if (code.contains('permission')) return AppErrorType.permissionDenied;
      if (code.contains('canceled') || code.contains('cancelled')) {
        return AppErrorType.authSignInCancelled;
      }
      return fallback;
    }

    return fallback;
  }

  /// Log the technical detail to the debug console (and, in the future,
  /// Crashlytics). Never log user-visible strings here — those are decided
  /// by [messageFor].
  static void _logTechnical(
    Object? error, {
    StackTrace? stackTrace,
    String? where,
  }) {
    if (kDebugMode) {
      debugPrint('[ErrorHandler${where != null ? ':$where' : ''}] $error');
      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    // TODO(observability): forward to Crashlytics non-fatal once configured.
  }

  /// Shows a floating top-toast popup with the friendly message for [type].
  static void showUserMessage(
    BuildContext context,
    AppErrorType type, {
    Object? error,
    StackTrace? stackTrace,
    String? where,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _logTechnical(error, stackTrace: stackTrace, where: where);
    if (!context.mounted) return;
    _showTopToast(context, messageFor(type), duration: duration);
  }

  /// Convenience: classifies the raw [error] and shows the resulting message.
  static void showFromError(
    BuildContext context,
    Object error, {
    StackTrace? stackTrace,
    AppErrorType fallback = AppErrorType.generic,
    String? where,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final type = classify(error, fallback: fallback);
    showUserMessage(
      context,
      type,
      error: error,
      stackTrace: stackTrace,
      where: where,
      duration: duration,
    );
  }

  static OverlayEntry? _activeToast;

  static void _showTopToast(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 3)}) {
    _activeToast?.remove();
    _activeToast = null;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        onDismiss: () {
          entry.remove();
          if (_activeToast == entry) _activeToast = null;
        },
        duration: duration,
      ),
    );
    _activeToast = entry;
    overlay.insert(entry);
  }

  /// For non-UI code paths (services, repositories) that need a friendly
  /// string to bubble up. Never returns raw exception text.
  static String friendlyMessage(
    Object? error, {
    AppErrorType fallback = AppErrorType.generic,
    String? where,
  }) {
    _logTechnical(error, where: where);
    return messageFor(classify(error, fallback: fallback));
  }
}

class _TopToast extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final Duration duration;
  const _TopToast(
      {required this.message, required this.onDismiss, required this.duration});

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  late final Animation<double> _fade;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slide = Tween<double>(begin: -1, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() async {
    _dismissTimer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => FractionalTranslation(
          translation: Offset(0, _slide.value),
          child: Opacity(
            opacity: _fade.value,
            child: GestureDetector(
              onTap: _dismiss,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2235),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withAlpha(22), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withAlpha(28),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.error_outline_rounded,
                            color: Color(0xFFEF4444), size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.close_rounded,
                          size: 16, color: Colors.white.withAlpha(100)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}
