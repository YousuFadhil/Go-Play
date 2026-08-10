import 'package:flutter/material.dart';

import '../features/auth/auth_service.dart';
import '../features/notifications/push_service.dart';
import '../features/profile/current_user.dart';
import '../features/profile/profile_models.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import 'l10n.dart';

/// The application header.
///
/// One bar for every signed-in screen, so the signed-in player's name and
/// picture are in the same place throughout navigation rather than only on the
/// screen that happens to have been given them. It is an ordinary [AppBar]
/// underneath — the title and any actions a screen already had are passed
/// straight through — with the identity added at the end of the actions, where
/// it stays put as those actions differ from screen to screen.
///
/// Deliberately not shown before sign-in: the login, registration and invitation
/// landing screens have no player to name, and asking for one there would be a
/// read that cannot succeed.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    this.title,
    this.actions = const [],
    this.bottom,
    this.leading,
  });

  final Widget? title;

  /// The screen's own actions. The identity is appended after them.
  final List<Widget> actions;

  final PreferredSizeWidget? bottom;

  /// A screen's own back button, where it needs one that reports something on
  /// the way out.
  final Widget? leading;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      bottom: bottom,
      leading: leading,
      actions: [...actions, const CurrentUserMenu()],
    );
  }
}

/// The signed-in player, and what they can do about being signed in.
///
/// Their picture and first name, and a menu holding the actions that belong to
/// the person rather than to the screen: open the profile, open the settings,
/// and log out. The profile screen carries the same three, which is the second
/// place the Product Owner asked for logout to be.
class CurrentUserMenu extends StatefulWidget {
  const CurrentUserMenu({super.key});

  @override
  State<CurrentUserMenu> createState() => _CurrentUserMenuState();
}

class _CurrentUserMenuState extends State<CurrentUserMenu> {
  @override
  void initState() {
    super.initState();
    // Held for the session, so this is a read on the first header built and
    // nothing on every one after it.
    CurrentUser.instance.ensureLoaded();
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ValueListenableBuilder<PlayerProfile?>(
      valueListenable: CurrentUser.instance.profile,
      builder: (context, profile, _) {
        final name = firstNameOf(profile?.fullName ?? '');

        return PopupMenuButton<_UserAction>(
          tooltip: name.isEmpty ? l10n.profileTitle : name,
          position: PopupMenuPosition.under,
          onSelected: (action) => switch (action) {
            _UserAction.profile => _openProfile(),
            _UserAction.settings => _openSettings(),
            _UserAction.logout => logOut(context),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _UserAction.profile,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.profileTitle),
                // The full name here, where there is room for it; the bar shows
                // the first name because a header is not a place to wrap.
                subtitle: (profile?.fullName ?? '').trim().isEmpty
                    ? null
                    : Text(profile!.fullName),
              ),
            ),
            PopupMenuItem(
              value: _UserAction.settings,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.settingsTitle),
              ),
            ),
            PopupMenuItem(
              value: _UserAction.logout,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: Text(l10n.logoutLabel),
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(profile: profile, radius: 16),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // Bounded, so a long name shortens instead of pushing the
                  // title off the bar.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Signs the player out, forgets who they were, and leaves the screen they did
/// it from.
///
/// The order matters. Clearing the cache first would leave the header blank
/// while the sign-out is still in flight; clearing after means the cached
/// profile never outlives the session it belongs to, which is what stops the
/// next account to sign in on this device being greeted by the previous one's
/// name.
///
/// The unwind matters as much. The auth gate swaps the app's **root** route for
/// the login screen, and logging out is now reachable from any screen — so
/// without this, signing out from a pushed screen would sign the session out and
/// leave that screen sitting on top of the login form.
Future<void> logOut(BuildContext context) async {
  final navigator = Navigator.of(context);
  // Before the sign-out, not after: deregistering the device is a delete on the
  // player's own row, and there is no session left to authorise it once they are
  // out. Leaving it would send this account's notices to a phone somebody else
  // may now be signed in on.
  await PushService.instance.signOut();
  await AuthService().logout();
  CurrentUser.instance.clear();
  navigator.popUntil((route) => route.isFirst);
}

/// A player's picture, or their initials when they have not set one.
///
/// The initials are not a placeholder for a picture that failed to load — they
/// are what an account without one looks like. A picture that cannot be fetched
/// falls back to the same thing rather than to a broken image.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 20});

  final PlayerProfile? profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatarUrl;
    final initials = initialsOf(profile?.fullName ?? '');

    return CircleAvatar(
      radius: radius,
      foregroundImage: url == null ? null : NetworkImage(url),
      // Swallowed on purpose: an avatar that will not load is not worth an
      // error, and CircleAvatar shows the child underneath it instead.
      onForegroundImageError: url == null ? null : (_, __) {},
      child: initials.isEmpty
          ? Icon(Icons.person, size: radius)
          : Text(initials, style: TextStyle(fontSize: radius * 0.8)),
    );
  }
}

enum _UserAction { profile, settings, logout }
