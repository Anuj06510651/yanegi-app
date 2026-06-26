import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';
import 'event_detail_admin_screen.dart';
import 'user_detail_screen.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: YanegiColors.surface,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Search everything',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: YanegiColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Users, events — by name, username, title, or UID',
                style: TextStyle(
                    fontSize: 13, color: YanegiColors.textTertiary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(
                    fontSize: 14, color: YanegiColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type a name, username, event title, or UID...',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: YanegiColors.textTertiary),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: YanegiColors.textTertiary),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              size: 16, color: YanegiColors.textTertiary),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: YanegiColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(YanegiRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _SearchResults(query: _query)),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final String query;

  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.length < 2) {
      return const AdminEmptyState(
        message: 'Type at least 2 characters to search',
        icon: Icons.search_rounded,
      );
    }

    final resultsAsync = ref.watch(adminGlobalSearchResultsProvider(query));

    return resultsAsync.when(
      loading: () => const AdminSkeletonList(itemCount: 5),
      error: (e, _) => AdminErrorState(message: e.toString()),
      data: (results) {
        if (results.isEmpty) {
          return AdminEmptyState(
            message: 'No results for "$query"',
            icon: Icons.search_off_rounded,
          );
        }

        final users = results.where((r) => r['type'] == 'user').toList();
        final events = results.where((r) => r['type'] == 'event').toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (users.isNotEmpty) ...[
              _GroupHeader('USERS', users.length),
              const SizedBox(height: 8),
              ...users.map((r) => _ResultTile(result: r)),
              const SizedBox(height: 20),
            ],
            if (events.isNotEmpty) ...[
              _GroupHeader('EVENTS', events.length),
              const SizedBox(height: 8),
              ...events.map((r) => _ResultTile(result: r)),
            ],
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;

  const _GroupHeader(this.label, this.count);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: YanegiColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: YanegiColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
                fontSize: 10, color: YanegiColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Map<String, dynamic> result;

  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final type = result['type'] as String;
    final id = result['id'] as String;
    final title = result['title'] as String;
    final subtitle = result['subtitle'] as String;
    final avatarUrl = result['avatarUrl'] as String?;

    final isUser = type == 'user';

    return Card(
      color: YanegiColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YanegiRadius.sm),
        side: BorderSide(color: Colors.white.withAlpha(8)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: YanegiColors.surfaceElevated,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? CachedNetworkImageProvider(avatarUrl,
                  maxWidth: 80, maxHeight: 80)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Icon(
                  isUser ? Icons.person_rounded : Icons.event_rounded,
                  size: 18,
                  color: YanegiColors.textTertiary,
                )
              : null,
        ),
        title: Text(
          title.isNotEmpty ? title : '(untitled)',
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: YanegiColors.textPrimary),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
              fontSize: 12, color: YanegiColors.textSecondary),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isUser ? YanegiColors.primary : const Color(0xFF818CF8))
                .withAlpha(26),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            type.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isUser ? YanegiColors.primary : const Color(0xFF818CF8),
            ),
          ),
        ),
        onTap: () {
          if (isUser) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UserDetailScreen(uid: id),
            ));
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EventDetailAdminScreen(eventId: id),
            ));
          }
        },
      ),
    );
  }
}
