import 'package:flutter/material.dart';

import '../../theme/yanegi_theme.dart';

/// Bottom sheet for composing a new poll.
/// Calls [onCreate] with question + option strings when submitted.
void showCreatePollSheet({
  required BuildContext context,
  required void Function(String question, List<String> options, bool allowMultiple) onCreate,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreatePollSheet(onCreate: onCreate),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _CreatePollSheet extends StatefulWidget {
  const _CreatePollSheet({required this.onCreate});
  final void Function(String question, List<String> options, bool allowMultiple) onCreate;

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _submitting = false;

  static const int _maxOptions = 6;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  bool get _isValid {
    final q = _questionCtrl.text.trim();
    final opts = _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return q.isNotEmpty && opts.length >= 2;
  }

  void _addOption() {
    if (_optionCtrls.length >= _maxOptions) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    final q = _questionCtrl.text.trim();
    final opts = _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() => _submitting = true);
    Navigator.of(context).pop();
    widget.onCreate(q, opts, _allowMultiple);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart_rounded,
                      color: Color(0xFF7C7AFF), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Create Poll',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withAlpha(150)),
                  ),
                ],
              ),
            ),

            // Scrollable body
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question field
                    _label('Question'),
                    const SizedBox(height: 6),
                    _TextField(
                      controller: _questionCtrl,
                      hint: 'Ask something...',
                      maxLength: 300,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 18),

                    // Options
                    _label('Options'),
                    const SizedBox(height: 6),
                    for (int i = 0; i < _optionCtrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _TextField(
                                controller: _optionCtrls[i],
                                hint: 'Option ${i + 1}',
                                maxLength: 100,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            if (_optionCtrls.length > 2)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: GestureDetector(
                                  onTap: () => _removeOption(i),
                                  child: Icon(Icons.remove_circle_outline,
                                      color: Colors.white.withAlpha(120),
                                      size: 22),
                                ),
                              ),
                          ],
                        ),
                      ),

                    if (_optionCtrls.length < _maxOptions)
                      GestureDetector(
                        onTap: _addOption,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline,
                                  color: YanegiColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Add option',
                                style: TextStyle(
                                  color: YanegiColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Multiple votes toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Allow multiple votes',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              Text(
                                'Members can pick more than one option',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(120),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _allowMultiple,
                          onChanged: (v) => setState(() => _allowMultiple = v),
                          activeColor: YanegiColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Submit button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isValid && !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YanegiColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white.withAlpha(25),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Create Poll',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withAlpha(160),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    required this.maxLength,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withAlpha(90)),
        counterText: '',
        filled: true,
        fillColor: const Color(0xFF1E2636),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF7C7AFF), width: 1.5),
        ),
      ),
    );
  }
}
