import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_environment.dart';
import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';

const double _sidebarWidth = 220;

class _SidebarItem {
  final IconData icon;
  final String label;
  final AdminRoute route;
  const _SidebarItem({required this.icon, required this.label, required this.route});
}

const _mainItems = [
  _SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard', route: AdminRoute.dashboard),
  _SidebarItem(icon: Icons.people_rounded, label: 'Users', route: AdminRoute.users),
  _SidebarItem(icon: Icons.event_rounded, label: 'Events', route: AdminRoute.events),
  _SidebarItem(icon: Icons.flag_rounded, label: 'Reports', route: AdminRoute.reports),
  _SidebarItem(icon: Icons.bar_chart_rounded, label: 'Analytics', route: AdminRoute.analytics),
];

const _operationsItems = [
  _SidebarItem(icon: Icons.search_rounded, label: 'Search', route: AdminRoute.search),
  _SidebarItem(icon: Icons.manage_history_rounded, label: 'Audit Log', route: AdminRoute.auditLog),
];

const _platformItems = [
  _SidebarItem(icon: Icons.map_outlined, label: 'Location', route: AdminRoute.locationAnalytics),
  _SidebarItem(icon: Icons.people_alt_rounded, label: 'Attendance', route: AdminRoute.attendance),
  _SidebarItem(icon: Icons.rocket_launch_rounded, label: 'Releases', route: AdminRoute.releases),
  _SidebarItem(icon: Icons.toggle_on_rounded, label: 'Feature Flags', route: AdminRoute.featureFlags),
];

class AdminSidebar extends ConsumerWidget {
  const AdminSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(adminRouteProvider);

    void navigate(AdminRoute r) =>
        ref.read(adminRouteProvider.notifier).state = r;

    return Container(
      width: _sidebarWidth,
      color: YanegiColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          ..._mainItems.map((item) => _NavTile(
                item: item,
                selected: current == item.route,
                onTap: () => navigate(item.route),
              )),
          _buildSectionLabel('OPERATIONS'),
          ..._operationsItems.map((item) => _NavTile(
                item: item,
                selected: current == item.route,
                onTap: () => navigate(item.route),
              )),
          _buildSectionLabel('PLATFORM'),
          ..._platformItems.map((item) => _NavTile(
                item: item,
                selected: current == item.route,
                onTap: () => navigate(item.route),
              )),
          const Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: YanegiColors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: YanegiColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            'Yanegi Admin',
            style: TextStyle(
              color: YanegiColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF1A1A1A), height: 1),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppEnvironment.isDev
                  ? const Color(0xFFFFC615).withAlpha(26)
                  : const Color(0xFF3B82F6).withAlpha(26),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              AppEnvironment.isDev ? 'DEV' : 'PROD',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppEnvironment.isDev
                    ? const Color(0xFFFFC615)
                    : const Color(0xFF3B82F6),
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nav tile using MouseRegion+GestureDetector (no InkWell/Material).
/// InkWell creates persistent hover regions that go stale on sidebar rebuild
/// (selected changes for every tile on each navigation), causing
/// mouse_tracker.dart:199 assertions. MouseRegion with local hover state
/// is safe because its lifecycle matches the tile widget exactly.
class _NavTile extends StatefulWidget {
  final _SidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? YanegiColors.primary.withAlpha(26)
        : _hovered
            ? YanegiColors.primary.withAlpha(12)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(YanegiRadius.sm),
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 18,
                  color: widget.selected
                      ? YanegiColors.primary
                      : YanegiColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: widget.selected
                          ? YanegiColors.textPrimary
                          : YanegiColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.selected)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: YanegiColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
