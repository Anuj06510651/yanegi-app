import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/filter_controller.dart';
import '../theme/yanegi_theme.dart';

class FilterBottomSheet extends ConsumerWidget {
  const FilterBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(filterProvider);
    final ctrl = ref.read(filterProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(YanegiSpacing.lg),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(YanegiRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter map & explore',
                    style: TextStyle(
                      fontSize: YanegiTypeScale.h2,
                      fontWeight: FontWeight.w600,
                      color: YanegiColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ctrl.clearFilters();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFF5F8FD9),
                        fontSize: YanegiTypeScale.label,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: YanegiSpacing.md),

              // Categories
              const Text('Categories', style: TextStyle(color: YanegiColors.textSecondary, fontWeight: FontWeight.bold, fontSize: YanegiTypeScale.label)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Sports', 'Food', 'Music', 'Outdoors', 'Social', 'Gaming', 'Trips'].map((c) {
                  final isSelected = state.categories.contains(c);
                  return FilterChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : YanegiColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: isSelected
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                    onSelected: (selected) {
                      final newCats = List<String>.from(state.categories);
                      if (selected) {
                        newCats.add(c);
                      } else {
                        newCats.remove(c);
                      }
                      ctrl.updateFilters(categories: newCats);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: YanegiSpacing.md),

              // Vibes
              const Text('Vibes', style: TextStyle(color: YanegiColors.textSecondary, fontWeight: FontWeight.bold, fontSize: YanegiTypeScale.label)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Chill', 'Deep Talks', 'Party', 'Productive', 'Adventure'].map((v) {
                  final isSelected = state.vibes.contains(v);
                  return FilterChip(
                    label: Text(
                      v,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : YanegiColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: isSelected
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                    onSelected: (selected) {
                      final newVibes = List<String>.from(state.vibes);
                      if (selected) {
                        newVibes.add(v);
                      } else {
                        newVibes.remove(v);
                      }
                      ctrl.updateFilters(vibes: newVibes);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: YanegiSpacing.md),

              // Date Filter
              const Text('Date', style: TextStyle(color: YanegiColors.textSecondary, fontWeight: FontWeight.bold, fontSize: YanegiTypeScale.label)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Anytime', 'Today', 'Tomorrow', 'Weekend'].map((d) {
                  final isSelected = state.dateFilter == d.toLowerCase();
                  return ChoiceChip(
                    label: Text(
                      d,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : YanegiColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: isSelected
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                    onSelected: (_) =>
                        ctrl.updateFilters(dateFilter: d.toLowerCase()),
                  );
                }).toList(),
              ),
              const SizedBox(height: YanegiSpacing.md),

              // Radius
              Text('Radius: ${state.radiusKm} km', style: const TextStyle(color: YanegiColors.textSecondary, fontWeight: FontWeight.bold, fontSize: YanegiTypeScale.label)),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: YanegiColors.primary,
                  inactiveTrackColor: YanegiColors.surfaceElevated,
                  thumbColor: YanegiColors.primary,
                  overlayColor: YanegiColors.primary.withOpacity(0.22),
                ),
                child: Slider(
                  value: state.radiusKm.toDouble(),
                  min: 5,
                  max: 35,
                  divisions: 6, // 5, 10, 15, 20, 25, 30, 35
                  onChanged: (val) {
                    ctrl.updateFilters(radiusKm: val.toInt());
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5 km',
                        style: TextStyle(
                            color: YanegiColors.textTertiary, fontSize: YanegiTypeScale.meta)),
                    Text('35 km',
                        style: TextStyle(
                            color: YanegiColors.textTertiary, fontSize: YanegiTypeScale.meta)),
                  ],
                ),
              ),

              // Quick Toggles
              const Text('Quick filters', style: TextStyle(color: YanegiColors.textSecondary, fontWeight: FontWeight.bold, fontSize: YanegiTypeScale.label)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(
                      'Free only',
                      style: TextStyle(
                        color:
                            state.freeOnly ? Colors.white : YanegiColors.textSecondary,
                        fontWeight: state.freeOnly
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    selected: state.freeOnly,
                    onSelected: (val) => ctrl.updateFilters(freeOnly: val),
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: state.freeOnly
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                  ),
                  FilterChip(
                    label: Text(
                      'Public only',
                      style: TextStyle(
                        color: state.publicOnly
                            ? Colors.white
                            : YanegiColors.textSecondary,
                        fontWeight: state.publicOnly
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    selected: state.publicOnly,
                    onSelected: (val) => ctrl.updateFilters(publicOnly: val),
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: state.publicOnly
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                  ),
                  FilterChip(
                    label: Text(
                      'Small groups (<6)',
                      style: TextStyle(
                        color: state.smallGroups
                            ? Colors.white
                            : YanegiColors.textSecondary,
                        fontWeight: state.smallGroups
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    selected: state.smallGroups,
                    onSelected: (val) => ctrl.updateFilters(smallGroups: val),
                    showCheckmark: false,
                    selectedColor: YanegiColors.primary,
                    backgroundColor: YanegiColors.surface,
                    side: BorderSide(
                      color: state.smallGroups
                          ? YanegiColors.primary
                          : YanegiColors.textSecondary.withOpacity(0.22),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YanegiColors.accentPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Apply', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
