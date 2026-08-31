import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/tokens.dart';
import '../communities/communities_screen.dart';
import '../discover/discover_screen.dart';
import 'home_tab.dart';

/// Root shell after login: bottom navigation between MVP sections.
///
/// Discover is first, and is what a signed-in player lands on. That is the
/// product decision this sprint closes: Go Play is a platform for football
/// communities rather than a dashboard of one's own fixtures, so the first thing
/// anyone sees — signed in or not — is what is being played and by whom. A
/// player's own matches have not been demoted; they are one tap away on Home,
/// which is where a dashboard belongs.
///
/// The same [DiscoverScreen] serves both audiences. It reads the public views
/// either way and asks who is looking only to decide what a tap does, so there
/// is no second Discover to keep in step with this one.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: Layout.navHeight + Layout.navInset * 2 + bottomInset,
            ),
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                DiscoverScreen(),
                HomeTab(),
                CommunitiesScreen(),
              ],
            ),
          ),
          PositionedDirectional(
            start: Layout.navInset,
            end: Layout.navInset,
            bottom: Layout.navInset + bottomInset,
            height: Layout.navHeight,
            child: _ClubFloatingNav(
              selectedIndex: _selectedIndex,
              onSelected: (index) => setState(() => _selectedIndex = index),
              labels: [l10n.navDiscover, l10n.navHome, l10n.navCommunities],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubFloatingNav extends StatelessWidget {
  const _ClubFloatingNav({
    required this.selectedIndex,
    required this.onSelected,
    required this.labels,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: GoColors.surfaceCard,
          borderRadius: BorderRadius.circular(Radii.control),
          boxShadow: Elevations.nav,
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            _ClubNavDestination(
              label: labels[0], icon: Icons.explore_outlined,
              selectedIcon: Icons.explore, selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _ClubNavDestination(
              label: labels[1], icon: Icons.home_outlined,
              selectedIcon: Icons.home, selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _ClubNavDestination(
              label: labels[2], icon: Icons.groups_outlined,
              selectedIcon: Icons.groups, selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
          ],
        ),
      );
}

class _ClubNavDestination extends StatelessWidget {
  const _ClubNavDestination({required this.label, required this.icon,
    required this.selectedIcon, required this.selected, required this.onTap});
  final String label; final IconData icon; final IconData selectedIcon;
  final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? GoColors.primaryDeep : GoColors.navUnselected;
    return Expanded(child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(Radii.control),
      child: Semantics(button: true, selected: selected, label: label,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 46, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: selected ? GoColors.statusOpenBg : Colors.transparent,
              borderRadius: BorderRadius.circular(13)),
            child: Icon(selected ? selectedIcon : icon, size: IconSize.nav, color: color)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, height: 1, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: color)),
        ]),
      ),
    ));
  }
}
