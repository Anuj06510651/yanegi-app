import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/memory.dart';
import '../../theme/yanegi_theme.dart';

class MemoryDetailScreen extends StatelessWidget {
  final Memory memory;

  const MemoryDetailScreen({super.key, required this.memory});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, y • h:mm a').format(memory.createdAt);

    return SafeArea(
      child: Scaffold(
        backgroundColor: YanegiColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Memory',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: memory.imageUrl != null && memory.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: memory.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, _) => Container(
                          color: YanegiColors.surface,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, _, __) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Caption'),
            const SizedBox(height: 6),
            Text(
              memory.caption.isEmpty ? 'No caption' : memory.caption,
              style: const TextStyle(color: YanegiColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 14),
            _sectionTitle('Event'),
            const SizedBox(height: 6),
            Text(
              memory.eventTitle.isEmpty ? 'Unknown Event' : memory.eventTitle,
              style: const TextStyle(color: YanegiColors.textSecondary),
            ),
            const SizedBox(height: 14),
            _sectionTitle('Tagged Users'),
            const SizedBox(height: 6),
            Text(
              memory.taggedUsers.isEmpty
                  ? 'No tags'
                  : memory.taggedUsers.map((e) => e.startsWith('@') ? e : '@$e').join(', '),
              style: const TextStyle(color: YanegiColors.textSecondary),
            ),
            const SizedBox(height: 14),
            _sectionTitle('Date'),
            const SizedBox(height: 6),
            Text(
              date,
              style: const TextStyle(color: YanegiColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: YanegiColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: YanegiColors.surface,
      child: const Center(
        child: Icon(Icons.photo_outlined, color: YanegiColors.textSecondary, size: 40),
      ),
    );
  }
}
