import 'package:flutter/material.dart';

import '../../core/l10n.dart';
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

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          DiscoverScreen(),
          HomeTab(),
          CommunitiesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: l10n.navDiscover,
          ),
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: l10n.navCommunities,
          ),
        ],
      ),
    );
  }
}
