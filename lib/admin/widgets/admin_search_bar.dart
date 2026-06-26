import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/yanegi_theme.dart';

/// A debounced search input used on Users and Events screens.
/// Emits trimmed, lowercased queries 400 ms after the user stops typing —
/// matching the debounce convention used elsewhere in the codebase.
class AdminSearchBar extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final String initialValue;

  const AdminSearchBar({
    super.key,
    required this.hint,
    required this.onChanged,
    this.initialValue = '',
  });

  @override
  State<AdminSearchBar> createState() => _AdminSearchBarState();
}

class _AdminSearchBarState extends State<AdminSearchBar> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      widget.onChanged(value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      style: const TextStyle(
        color: YanegiColors.textPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(
          color: YanegiColors.textTertiary,
          fontSize: 14,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: YanegiColors.textTertiary,
          size: 20,
        ),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                color: YanegiColors.textTertiary,
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: YanegiColors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YanegiRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YanegiRadius.sm),
          borderSide:
              const BorderSide(color: YanegiColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
