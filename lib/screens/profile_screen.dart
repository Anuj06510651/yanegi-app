import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/local_profile_cache.dart';
import '../theme/yanegi_theme.dart';
import '../utils/error_handler.dart';
import '../widgets/share_to_chat_sheet.dart';
import 'settings_screen.dart';
import '../config/app_environment.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  // Live counters from Firestore — driven by streams below.
  String _username = '';
  String _displayName = '';
  String _avatarUrl = '';
  final String _bio =
      'Adventure seeker • Coffee enthusiast • Making memories one event at a time ✨';
  int _friendsCount = 0;
  File? _profileImage;
  File? _bannerImage;

  // Live stat streams.
  Stream<int>? _eventsHostedStream;
  Stream<int>? _eventsJoinedStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      // Instant paint: pre-fill from the local cache before Firestore returns.
      // The Firestore .get() below still runs and overwrites with fresh data.
      final cached = LocalProfileCache.load(uid);
      if (cached != null) {
        _displayName = cached.name.trim();
        _username = cached.username.trim();
        _avatarUrl = (cached.avatarUrl ?? '').trim();
      }

      // Load display name + username once.
      FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
        if (!mounted || !doc.exists) return;
        final data = doc.data() ?? {};
        setState(() {
          _displayName = (data['name'] ?? data['displayName'] ?? '').toString().trim();
          _username = (data['username'] ?? '').toString().trim();
          _friendsCount = (data['friendsCount'] ?? 0) as int? ?? 0;
          _avatarUrl = (data['photoUrl'] ?? data['avatarUrl'] ?? data['avatar_url'] ?? '').toString().trim();
        });
      });

      _eventsHostedStream = FirebaseFirestore.instance
          .collection('events')
          .where('hostId', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .map((s) => s.docs.length);

      _eventsJoinedStream = FirebaseFirestore.instance
          .collectionGroup('users')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .map((s) => s.docs.where((d) {
                final data = d.data();
                if (!data.containsKey('eventId')) return false;
                final status = (data['status'] ?? '').toString().toLowerCase();
                return status.isEmpty || status == 'active' || status == 'joined';
              }).length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildProfileAppBar(),
          _buildProfileContent(),
        ],
      ),
    );
  }

  Widget _buildProfileAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: YanegiColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_rounded, color: Colors.white),
          onPressed: _shareProfile,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: _showProfileOptions,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner Image
            _buildBannerSection(),
            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            // Profile Picture
            Positioned(
              bottom: 20,
              left: 20,
              child: _buildProfilePicture(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerSection() {
    return GestureDetector(
      onTap: _changeBannerImage,
      child: Container(
        decoration: BoxDecoration(
          gradient: _bannerImage == null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    YanegiColors.primary.withOpacity(0.8),
                    YanegiColors.secondary,
                    YanegiColors.tertiary.withOpacity(0.6),
                  ],
                )
              : null,
          image: _bannerImage != null
              ? DecorationImage(
                  image: FileImage(_bannerImage!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _bannerImage == null
            ? Center(
                child: Icon(
                  Icons.add_a_photo_outlined,
                  size: 40,
                  color: Colors.white.withOpacity(0.7),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildProfilePicture() {
    return GestureDetector(
      onTap: _changeProfileImage,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          gradient: _profileImage == null
              ? LinearGradient(
                  colors: [
                    YanegiColors.primary,
                    YanegiColors.tertiary,
                  ],
                )
              : null,
          image: _profileImage != null
              ? DecorationImage(
                  image: FileImage(_profileImage!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _profileImage == null
            ? Icon(
                Icons.person,
                size: 50,
                color: Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildProfileContent() {
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name and username
              _buildNameSection(),
              const SizedBox(height: 16),

              // Stats row
              _buildStatsRow(),
              const SizedBox(height: 20),

              // Bio
              _buildBioSection(),
              const SizedBox(height: 24),

              // Social media
              _buildSocialSection(),
              const SizedBox(height: 32),

              // Memories section header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Memories',
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _addMemory,
                    child: Text(
                      'Add +',
                      style: TextStyle(
                        color: YanegiColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Memories grid
              _buildMemoriesGrid(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildNameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayName,
          style: TextStyle(
            color: YanegiColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _username,
          style: TextStyle(
            color: YanegiColors.textSecondary,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildLiveStatItem('Events Joined', _eventsJoinedStream),
        _buildStatDivider(),
        _buildLiveStatItem('Events Hosted', _eventsHostedStream),
        _buildStatDivider(),
        _buildStatItem('Friends', _friendsCount),
      ],
    );
  }

  Widget _buildLiveStatItem(String label, Stream<int>? stream) {
    if (stream == null) return _buildStatItem(label, 0);
    return Expanded(
      child: StreamBuilder<int>(
        stream: stream,
        builder: (context, snap) {
          return _buildStatItemContent(label, snap.data ?? 0);
        },
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Expanded(child: _buildStatItemContent(label, count));
  }

  Widget _buildStatItemContent(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            color: YanegiColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: YanegiColors.textSecondary,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 30,
      color: YanegiColors.textSecondary.withOpacity(0.3),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildBioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          style: TextStyle(
            color: YanegiColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _bio,
          style: TextStyle(
            color: YanegiColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSocialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect',
          style: TextStyle(
            color: YanegiColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildSocialButton(Icons.link, 'Instagram', '@alex_wanderer'),
            const SizedBox(width: 12),
            _buildSocialButton(Icons.link, 'Twitter', '@alexchen'),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialButton(IconData icon, String platform, String handle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: YanegiColors.textSecondary.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: YanegiColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    platform,
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    handle,
                    style: TextStyle(
                      color: YanegiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoriesGrid() {
    // Sample memory data
    final memories = List.generate(
        8,
        (index) => {
              'image': null,
              'title': 'Memory ${index + 1}',
              'date': '2024-0${(index % 9) + 1}-${(index * 3 + 10) % 28 + 1}',
            });

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: memories.length + 1, // +1 for add button
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAddMemoryCard();
        }

        final memory = memories[index - 1];
        return _buildMemoryCard(memory);
      },
    );
  }

  Widget _buildAddMemoryCard() {
    return GestureDetector(
      onTap: _addMemory,
      child: Container(
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: YanegiColors.primary.withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              color: YanegiColors.primary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'Add Memory',
              style: TextStyle(
                color: YanegiColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    return Container(
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YanegiColors.primary.withOpacity(0.1),
            YanegiColors.secondary.withOpacity(0.1),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: YanegiColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.photo_outlined,
                  color: YanegiColors.textSecondary,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              memory['title'],
              style: TextStyle(
                color: YanegiColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              memory['date'],
              style: TextStyle(
                color: YanegiColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeProfileImage() async {
    final XFile? image = await _pickImageWithRecovery(
      source: ImageSource.gallery,
    );
    if (image == null) return;

    setState(() {
      _profileImage = File(image.path);
    });
  }

  void _changeBannerImage() async {
    final XFile? image = await _pickImageWithRecovery(
      source: ImageSource.gallery,
    );
    if (image == null) return;

    setState(() {
      _bannerImage = File(image.path);
    });
  }

  void _addMemory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add Memory',
              style: TextStyle(
                color: YanegiColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildMemoryOption(
                    Icons.camera_alt_outlined,
                    'Take Photo',
                    () => _pickMemoryImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMemoryOption(
                    Icons.photo_library_outlined,
                    'From Gallery',
                    () => _pickMemoryImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: YanegiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: YanegiColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: YanegiColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickMemoryImage(ImageSource source) async {
    Navigator.pop(context);
    final XFile? image = await _pickImageWithRecovery(source: source);
    if (!mounted) return;
    if (image == null) return;

    // In a real app, you would save this to your memories collection
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Memory added!'),
        backgroundColor: YanegiColors.primary,
      ),
    );
  }

  Future<XFile?> _pickImageWithRecovery({required ImageSource source}) async {
    try {
      final lostData = await _picker.retrieveLostData();
      if (lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('Recovered lost image picker data');
        return lostData.files!.first;
      }
      if (lostData.exception != null) {
        debugPrint(
            'Image picker lost-data recovery error: ${lostData.exception}');
      }

      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) {
        debugPrint('User cancelled image selection');
        return null;
      }
      return image;
    } catch (e) {
      debugPrint('ProfileScreen image pick failed: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not select image. Please try again.')),
      );
      return null;
    }
  }

  Future<void> _shareProfile() async {
    final userId = (FirebaseAuth.instance.currentUser?.uid ??
            _username.replaceFirst('@', '').trim())
        .trim();
    if (userId.isEmpty || !mounted) return;

    final profileUrl = '${AppEnvironment.webBaseUrl}/profile/$userId';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF101726),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _ProfileShareOptionTile(
              icon: Icons.chat_bubble_rounded,
              label: 'Share in Chat',
              subtitle: 'Send as a card to a DM',
              onTap: () {
                Navigator.pop(context);
                showShareToChatSheet(
                  context,
                  shareType: 'profile_card',
                  metadata: {
                    'targetId': userId,
                    'title': _displayName,
                    'subtitle': _username,
                    'avatarUrl': _avatarUrl,
                    'emoji': '👤',
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            _ProfileShareOptionTile(
              icon: Icons.link_rounded,
              label: 'Copy / Share Link',
              subtitle: profileUrl,
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.share(
                    'Check out this profile on Yanegi: $profileUrl',
                  );
                } catch (e, stack) {
                  if (!mounted) return;
                  ErrorHandler.showUserMessage(
                    context,
                    AppErrorType.generic,
                    error: e,
                    stackTrace: stack,
                    where: 'profile_screen._shareProfile',
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: YanegiColors.primary),
              title: Text(
                'Edit Profile',
                style: TextStyle(color: YanegiColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                // Navigate to edit profile
              },
            ),
            ListTile(
              leading: Icon(Icons.settings, color: YanegiColors.textSecondary),
              title: Text(
                'Settings',
                style: TextStyle(color: YanegiColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileShareOptionTile extends StatelessWidget {
  const _ProfileShareOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2535),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: YanegiColors.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: YanegiColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.white.withAlpha(80),
            ),
          ],
        ),
      ),
    );
  }
}
