import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SendFeedbackScreen extends StatefulWidget {
  const SendFeedbackScreen({super.key});

  @override
  State<SendFeedbackScreen> createState() => _SendFeedbackScreenState();
}

class _SendFeedbackScreenState extends State<SendFeedbackScreen> {
  final TextEditingController _feedbackController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _currentUserMeta() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return const {
        'userId': '',
        'username': 'anonymous',
        'name': 'Anonymous',
      };
    }

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? const <String, dynamic>{};

    // Identity isolation: only read from the Yanegi user doc. Never fall
    // back to FirebaseAuth.displayName — that would attach the user's Google
    // account name to outgoing feedback metadata.
    final usernameRaw =
        (data['username'] ?? data['name'] ?? 'user').toString().trim();
    final username =
        usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw';
    final name = (data['name'] ?? 'User').toString().trim();

    return {
      'userId': uid,
      'username': username,
      'name': name.isEmpty ? 'User' : name,
    };
  }

  Future<void> _submitFeedback() async {
    final title = _titleController.text.trim();
    final message = _feedbackController.text.trim();

    if (message.isEmpty) {
      _showSnack('Please write your feedback before sending.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userMeta = await _currentUserMeta();
      final now = DateTime.now();
      final dateLabel = DateFormat('dd MMM yyyy').format(now);
      final timeLabel = DateFormat('hh:mm a').format(now);

      await FirebaseFirestore.instance.collection('feedback').add({
        'title': title,
        'message': message,
        'username': userMeta['username'],
        'name': userMeta['name'],
        'userId': userMeta['userId'],
        'date': dateLabel,
        'time': timeLabel,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtIso': now.toIso8601String(),
        'status': 'new',
        'source': 'settings_send_feedback',
      });

      if (!mounted) return;
      _showSnack('Thanks! Your feedback has been sent to Yanegi.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not send feedback right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'Send Feedback',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: textSecondary.withOpacity(0.22)),
            ),
            child: Text(
              'Tell us what you loved, what can be improved, or what you want next. We read every feedback.',
              style: TextStyle(
                color: textSecondary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            maxLength: 60,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Title (optional)',
              labelStyle: TextStyle(color: textSecondary),
              hintText: 'Quick summary',
              hintStyle: TextStyle(color: textSecondary.withOpacity(0.8)),
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _feedbackController,
            maxLength: 1000,
            minLines: 6,
            maxLines: 10,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Your feedback',
              labelStyle: TextStyle(color: textSecondary),
              hintText: 'Share your thoughts with Yanegi...',
              hintStyle: TextStyle(color: textSecondary.withOpacity(0.8)),
              alignLabelWithHint: true,
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitFeedback,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_isSubmitting ? 'Sending...' : 'Send to Yanegi'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
