import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/activity_notification_service.dart';
import '../services/memory_service.dart';
import '../services/notification_types.dart';
import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';

// ─── Simple data class for tagged users ──────────────────────────────────────

class _TaggedUser {
  final String uid;
  final String name;
  final String username;
  final String avatarUrl;
  const _TaggedUser({
    required this.uid,
    required this.name,
    required this.username,
    required this.avatarUrl,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class EventRecapScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String eventBannerUrl;

  const EventRecapScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.eventBannerUrl = '',
  });

  @override
  State<EventRecapScreen> createState() => _EventRecapScreenState();
}

class _EventRecapScreenState extends State<EventRecapScreen> {
  static const _emojis = ['😍', '🎉', '👍', '😐', '😞'];
  static const _emojiLabels = ['Amazing', 'Fun!', 'Good', 'Okay', 'Meh'];
  static const _maxTags = 5;

  // Rating
  int? _rating; // 0–4 index

  // Memory section
  bool _memoryExpanded = false;
  File? _selectedImage;
  final _captionCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Shoutout / tag section
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<_TaggedUser> _searchResults = [];
  final List<_TaggedUser> _taggedUsers = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Submission
  bool _isSubmitting = false;
  bool _submitted = false;

  // User-to-user rating step
  bool _showParticipantRating = false;
  List<_RateableUser> _participants = [];
  bool _loadingParticipants = false;
  bool _submittingPeerRatings = false;
  final Map<String, int> _peerRatings = {}; // uid → star count (1-5)

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _captionCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    final q = query.toLowerCase().replaceAll('@', '');
    if (q.isEmpty) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }

    try {
      // Prefix-search on usernameLower — fast, uses auto-index.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isGreaterThanOrEqualTo: q)
          .where('usernameLower', isLessThanOrEqualTo: '$q')
          .limit(12)
          .get();

      final seen = {_currentUid};
      final results = <_TaggedUser>[];

      for (final doc in snap.docs) {
        if (seen.contains(doc.id)) continue;
        seen.add(doc.id);
        final d = doc.data();
        if ((d['profileVisibility'] ?? '') == 'private') continue;
        final name = (d['name'] ?? d['username'] ?? 'User').toString().trim();
        final username = (d['username'] ?? '').toString().trim();
        final avatar = (d['avatarUrl'] ?? d['photoUrl'] ?? '').toString();
        results.add(_TaggedUser(
          uid: doc.id,
          name: name,
          username: username,
          avatarUrl: avatar,
        ));
      }

      if (mounted) setState(() { _searchResults = results; _isSearching = false; });
    } catch (_) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
    }
  }

  void _toggleTag(_TaggedUser user) {
    HapticFeedback.selectionClick();
    setState(() {
      final already = _taggedUsers.any((u) => u.uid == user.uid);
      if (already) {
        _taggedUsers.removeWhere((u) => u.uid == user.uid);
      } else if (_taggedUsers.length < _maxTags) {
        _taggedUsers.add(user);
      }
    });
  }

  // ── Image picker ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _selectedImage = File(picked.path));
  }

  // ── Submission ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_rating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap an emoji to rate your experience!')),
      );
      return;
    }
    if (_isSubmitting) return;
    if (_currentUid.isEmpty) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      // 1 — Write rating + recap flag to participant doc.
      await FirebaseFirestore.instance
          .collection('event_participants')
          .doc(widget.eventId)
          .collection('users')
          .doc(_currentUid)
          .update({
        'recapRating': _rating,
        'recapSubmittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2 — Create memory if image was selected.
      if (_selectedImage != null) {
        final caption = _captionCtrl.text.trim();
        await MemoryService().createMemory(
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
          description: caption.isNotEmpty ? caption : '${_emojis[_rating!]} ${widget.eventTitle}',
          imageFile: _selectedImage,
        );
      }

      // 3 — Send shoutout notifications (fire-and-forget).
      if (_taggedUsers.isNotEmpty) {
        unawaited(_sendShoutouts());
      }

      if (mounted) {
        setState(() { _isSubmitting = false; });
        HapticFeedback.heavyImpact();
        // Load participants for peer rating, then show that step
        await _loadParticipantsForRating();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save recap: $e')),
        );
      }
    }
  }

  Future<void> _sendShoutouts() async {
    final svc = ActivityNotificationService();
    for (final user in _taggedUsers) {
      try {
        await svc.createNotification(
          receiverId: user.uid,
          type: NotificationType.shoutout,
          message: 'gave you a shoutout after ${widget.eventTitle}',
          title: 'gave you a shoutout after ${widget.eventTitle}',
          eventId: widget.eventId,
          dedupeKey: 'shoutout:${widget.eventId}:$_currentUid:${user.uid}',
          dedupeWindow: const Duration(hours: 24),
        );
      } catch (_) {}
    }
  }

  Future<void> _loadParticipantsForRating() async {
    if (_loadingParticipants) return;
    setState(() => _loadingParticipants = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('event_participants')
          .doc(widget.eventId)
          .collection('users')
          .get();

      final users = <_RateableUser>[];
      for (final doc in snap.docs) {
        final uid = doc.id;
        if (uid == _currentUid) continue;
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final uData = userSnap.data() ?? {};
        users.add(_RateableUser(
          uid: uid,
          name: (uData['displayName'] ?? uData['name'] ?? 'User').toString(),
          avatarUrl: (uData['avatarUrl'] ?? '').toString(),
        ));
      }
      if (mounted) {
        setState(() {
          _participants = users;
          _loadingParticipants = false;
          _showParticipantRating = true;
        });
      }
    } catch (_) {
      // If loading fails, just go to success state directly
      if (mounted) setState(() { _loadingParticipants = false; _submitted = true; });
    }
  }

  Future<void> _submitPeerRatings() async {
    if (_submittingPeerRatings) return;
    setState(() => _submittingPeerRatings = true);
    final batch = FirebaseFirestore.instance.batch();
    for (final entry in _peerRatings.entries) {
      final ratedUid = entry.key;
      final stars = entry.value;
      // Write to user_ratings/{ratedUid}/ratings/{raterUid}
      final ref = FirebaseFirestore.instance
          .collection('user_ratings')
          .doc(ratedUid)
          .collection('ratings')
          .doc(_currentUid);
      batch.set(ref, {
        'stars': stars,
        'eventId': widget.eventId,
        'raterUid': _currentUid,
        'ratedAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } catch (_) {}
    if (mounted) setState(() { _submittingPeerRatings = false; _submitted = true; });
  }

  void _skipPeerRating() {
    setState(() => _submitted = true);
  }

  void _share() {
    final emoji = _rating != null ? _emojis[_rating!] : '🎉';
    Share.share(
      '$emoji Just had a great time at "${widget.eventTitle}"! Made some amazing memories on Yanegi.',
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccessState();
    if (_showParticipantRating) return _buildParticipantRatingScreen();

    return Scaffold(
      backgroundColor: YanegiColors.background,
      appBar: AppBar(
        backgroundColor: YanegiColors.background,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Skip',
              style: TextStyle(color: Colors.white.withAlpha(150))),
        ),
        title: const Text('Event Recap',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white70),
            tooltip: 'Share',
            onPressed: _share,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildRatingSection(),
            const SizedBox(height: 24),
            _buildMemorySection(),
            const SizedBox(height: 24),
            _buildShoutoutSection(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.eventBannerUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              widget.eventBannerUrl,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'How was it?',
          style: TextStyle(
            color: Colors.white.withAlpha(180),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.eventTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Rating section ────────────────────────────────────────────────────────────

  Widget _buildRatingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151C2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Rate your experience',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('required',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_emojis.length, (i) {
              final selected = _rating == i;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _rating = i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? YanegiColors.primary.withAlpha(40)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? YanegiColors.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(_emojis[i],
                          style: TextStyle(
                              fontSize: selected ? 32 : 28)),
                      const SizedBox(height: 4),
                      Text(
                        _emojiLabels[i],
                        style: TextStyle(
                          color: selected
                              ? YanegiColors.primary
                              : Colors.white.withAlpha(100),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Memory section ────────────────────────────────────────────────────────────

  Widget _buildMemorySection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151C2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _memoryExpanded = !_memoryExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C7AFF).withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        color: Color(0xFF7C7AFF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add a memory',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        Text('Optional — share a photo from the event',
                            style: TextStyle(
                                color: Colors.white.withAlpha(120),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(
                    _memoryExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white.withAlpha(150),
                  ),
                ],
              ),
            ),
          ),
          if (_memoryExpanded) ...[
            Divider(color: Colors.white.withAlpha(12), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Photo picker
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1420),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedImage != null
                              ? const Color(0xFF7C7AFF)
                              : Colors.white.withAlpha(20),
                          width: _selectedImage != null ? 2 : 1,
                        ),
                      ),
                      child: _selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.file(_selectedImage!, fit: BoxFit.cover),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded,
                                    size: 36,
                                    color: Colors.white.withAlpha(80)),
                                const SizedBox(height: 8),
                                Text('Tap to add a photo',
                                    style: TextStyle(
                                        color: Colors.white.withAlpha(120),
                                        fontSize: 13)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Caption
                  TextField(
                    controller: _captionCtrl,
                    maxLength: 200,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a caption…',
                      hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                      filled: true,
                      fillColor: const Color(0xFF0F1420),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      counterStyle:
                          TextStyle(color: Colors.white.withAlpha(80)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shoutout / tag section ────────────────────────────────────────────────────

  Widget _buildShoutoutSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151C2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22E7A2).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.people_rounded,
                      color: Color(0xFF22E7A2), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Give a shoutout',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      Text('Tag someone who made it great (up to $_maxTags)',
                          style: TextStyle(
                              color: Colors.white.withAlpha(120),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search bar
            TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '@search by username or name…',
                hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                filled: true,
                fillColor: const Color(0xFF0F1420),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withAlpha(120), size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: Colors.white.withAlpha(120), size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),

            // Search results
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: YanegiColors.primary,
                    ),
                  ),
                ),
              )
            else if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1420),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(12)),
                ),
                child: Column(
                  children: _searchResults.map((user) {
                    final isTagged = _taggedUsers.any((u) => u.uid == user.uid);
                    final isMaxed =
                        _taggedUsers.length >= _maxTags && !isTagged;
                    return _buildSearchResultTile(user, isTagged, isMaxed);
                  }).toList(),
                ),
              ),

            // Tagged user chips
            if (_taggedUsers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _taggedUsers
                    .map((u) => _buildTagChip(u))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(
      _TaggedUser user, bool isTagged, bool isMaxed) {
    return InkWell(
      onTap: isMaxed ? null : () => _toggleTag(user),
      child: Opacity(
        opacity: isMaxed ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AppUserAvatar(photoUrl: user.avatarUrl, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    if (user.username.isNotEmpty)
                      Text('@${user.username}',
                          style: TextStyle(
                              color: Colors.white.withAlpha(120),
                              fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                isTagged
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: isTagged
                    ? const Color(0xFF22E7A2)
                    : Colors.white.withAlpha(120),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagChip(_TaggedUser user) {
    return GestureDetector(
      onTap: () => _toggleTag(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF22E7A2).withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: const Color(0xFF22E7A2).withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppUserAvatar(photoUrl: user.avatarUrl, radius: 10),
            const SizedBox(width: 6),
            Text(
              user.name,
              style: const TextStyle(
                color: Color(0xFF22E7A2),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.close_rounded,
                size: 14, color: const Color(0xFF22E7A2).withAlpha(150)),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final ratingSelected = _rating != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: YanegiColors.background,
        border:
            Border(top: BorderSide(color: Colors.white.withAlpha(12))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: ratingSelected && !_isSubmitting ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: YanegiColors.primary,
                disabledBackgroundColor: YanegiColors.primary.withAlpha(60),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Done',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!ratingSelected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Rate your experience to submit',
                  style: TextStyle(
                      color: Colors.white.withAlpha(100), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────────

  Widget _buildSuccessState() {
    final emoji = _emojis[_rating!];
    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 16),
              const Text('Recap saved!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                _taggedUsers.isNotEmpty
                    ? 'Shoutouts sent to ${_taggedUsers.map((u) => u.name).join(', ')} 🎉'
                    : 'Thanks for sharing your experience!',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white.withAlpha(160), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Participant rating screen ──────────────────────────────────────────────────

  Widget _buildParticipantRatingScreen() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: YanegiColors.background,
      appBar: AppBar(
        backgroundColor: YanegiColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Rate the crew',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _skipPeerRating,
            child: Text('Skip',
                style: TextStyle(color: Colors.white.withAlpha(150))),
          ),
        ],
      ),
      body: _loadingParticipants
          ? const Center(
              child: CircularProgressIndicator(color: YanegiColors.primary))
          : _participants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🤝', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text('No other participants found',
                          style: TextStyle(
                              color: Colors.white.withAlpha(150), fontSize: 15)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _skipPeerRating,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YanegiColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'How was it meeting these people?',
                        style: TextStyle(
                            color: Colors.white.withAlpha(170),
                            fontSize: 14,
                            height: 1.4),
                      ),
                    ),
                    ..._participants.map((user) {
                      final stars = _peerRatings[user.uid] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151C2A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: stars > 0
                                  ? YanegiColors.primary.withAlpha(80)
                                  : Colors.white.withAlpha(12)),
                        ),
                        child: Row(
                          children: [
                            AppUserAvatar(
                                photoUrl: user.avatarUrl, radius: 22),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: List.generate(5, (i) {
                                      final filled = i < stars;
                                      return GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() =>
                                              _peerRatings[user.uid] = i + 1);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Icon(
                                            filled
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 28,
                                            color: filled
                                                ? const Color(0xFFFBBF24)
                                                : Colors.white.withAlpha(50),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
      bottomNavigationBar: _participants.isNotEmpty
          ? Container(
              padding:
                  EdgeInsets.fromLTRB(16, 12, 16, bottom + 12),
              decoration: BoxDecoration(
                color: YanegiColors.background,
                border: Border(
                    top: BorderSide(color: Colors.white.withAlpha(12))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submittingPeerRatings
                      ? null
                      : (_peerRatings.isNotEmpty
                          ? _submitPeerRatings
                          : _skipPeerRating),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _peerRatings.isNotEmpty
                        ? YanegiColors.primary
                        : YanegiColors.surfaceElevated,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submittingPeerRatings
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _peerRatings.isNotEmpty ? 'Submit ratings' : 'Skip',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            )
          : null,
    );
  }
}

// ─── Data class for rateable participants ──────────────────────────────────────

class _RateableUser {
  final String uid;
  final String name;
  final String avatarUrl;
  const _RateableUser(
      {required this.uid, required this.name, required this.avatarUrl});
}
