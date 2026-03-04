import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../di/injection.dart';
import '../services/tts_service.dart';

class ShellPage extends StatelessWidget {
  final Widget child;
  const ShellPage({super.key, required this.child});

  static const _routes = ['/home', '/journal', '/chat', '/insights', '/profile'];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    // Map /calendar to profile tab so the nav still highlights something
    if (location.startsWith('/calendar')) return 4;
    final idx = _routes.indexWhere((r) => location.startsWith(r));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_outlined,       activeIcon: Icons.home_rounded,        label: 'Home',     index: 0, current: currentIndex),
                _NavItem(icon: Icons.book_outlined,       activeIcon: Icons.book_rounded,        label: 'Journal',  index: 1, current: currentIndex),
                _NavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble_rounded, label: 'Chat',     index: 2, current: currentIndex),
                _NavItem(icon: Icons.lightbulb_outline,   activeIcon: Icons.lightbulb_rounded,   label: 'Insights', index: 3, current: currentIndex),
                _NavItem(icon: Icons.person_outline,      activeIcon: Icons.person_rounded,      label: 'Profile',  index: 4, current: currentIndex),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final int      index;
  final int      current;

  static const _routes = ['/home', '/journal', '/chat', '/insights', '/profile'];

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Stop TTS when navigating away from Chat tab
          if (current == 2 && index != 2) {
            getIt<TtsService>().stop();
          }
          context.go(_routes[index]);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryPurple.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppTheme.primaryPurple : const Color(0xFF9CA3AF),
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppTheme.primaryPurple : const Color(0xFF9CA3AF),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ]),
        ),
      ),
    );
  }
}
