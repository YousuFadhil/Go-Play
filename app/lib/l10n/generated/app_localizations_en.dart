// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Go Play';

  @override
  String get navHome => 'Home';

  @override
  String get navCommunities => 'Communities';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Enter a valid email address';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneHint => '8 digits, e.g. 9012 3456';

  @override
  String get passwordLabel => 'Password';

  @override
  String get phoneRequired => 'Phone number is required';

  @override
  String get phoneInvalid => 'Enter an 8-digit phone number';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get loginTitle => 'Log in';

  @override
  String get loginButton => 'Log in';

  @override
  String get loginFailed => 'Login failed. Check your email and password.';

  @override
  String get noAccountPrompt => 'No account? Create one';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerButton => 'Create account';

  @override
  String get registerFailed => 'Registration failed. Please try again.';

  @override
  String get emailAlreadyUsed => 'This email is already registered.';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get fullNameRequired => 'Full name is required';

  @override
  String get positionLabel => 'Primary position';

  @override
  String get positionRequired => 'Primary position is required';

  @override
  String get haveAccountPrompt => 'Have an account? Log in';

  @override
  String get positionGk => 'Goalkeeper';

  @override
  String get positionDef => 'Defender';

  @override
  String get positionMid => 'Midfielder';

  @override
  String get positionFwd => 'Forward';

  @override
  String get homeTitle => 'Home';

  @override
  String get logoutLabel => 'Log out';

  @override
  String get communitiesTitle => 'Communities';

  @override
  String get communitiesEmpty =>
      'You are not in any community yet.\nCreate one or join with a code.';

  @override
  String get createCommunityTitle => 'Create community';

  @override
  String get createCommunityButton => 'Create community';

  @override
  String get joinCommunityTitle => 'Join community';

  @override
  String get joinCommunityButton => 'Join';

  @override
  String get communityNameLabel => 'Community name';

  @override
  String get communityNameRequired => 'Community name is required';

  @override
  String get communityDescriptionLabel => 'Description (optional)';

  @override
  String get joinCodeLabel => 'Join code';

  @override
  String get joinCodeRequired => 'Join code is required';

  @override
  String get communityNotFound => 'No community found with this code.';

  @override
  String get alreadyMemberOfCommunity =>
      'You are already a member of this community.';

  @override
  String get communityCreateFailed =>
      'Failed to create the community. Please try again.';

  @override
  String get communityJoinFailed =>
      'Failed to join the community. Please try again.';

  @override
  String get membersTitle => 'Members';

  @override
  String get joinCodeCopied => 'Join code copied';

  @override
  String get myCommunitiesSection => 'My communities';

  @override
  String get publicCommunitiesSection => 'Public communities';

  @override
  String get joinedCommunity => 'You joined the community.';

  @override
  String get matchesTitle => 'Matches';

  @override
  String get createMatchTitle => 'Create match';

  @override
  String get createMatchButton => 'Create match';

  @override
  String get matchDetailsTitle => 'Match details';

  @override
  String get locationLabel => 'Location';

  @override
  String get locationRequired => 'Location is required';

  @override
  String get dateLabel => 'Date';

  @override
  String get startTimeLabel => 'Start time';

  @override
  String get endTimeLabel => 'End time';

  @override
  String get dateTimeRequired => 'Pick the date and times';

  @override
  String get endAfterStartError => 'End time must be after start time';

  @override
  String get startInPastError => 'Match must start in the future';

  @override
  String get startingPlayersLabel => 'Starting players';

  @override
  String get startingPlayersInvalid => 'Enter a number between 2 and 30';

  @override
  String capacityAutoNote(int reserve, int max) {
    return 'Reserve players: $reserve (automatic) — maximum registration: $max';
  }

  @override
  String get matchCreateFailed =>
      'Failed to create the match. Please try again.';

  @override
  String get communityMatchesEmpty => 'No matches in this community yet.';

  @override
  String get upcomingMatchesTitle => 'Upcoming matches';

  @override
  String get upcomingMatchesEmpty =>
      'No upcoming matches.\nJoin a community to get started.';

  @override
  String get matchStatusOpen => 'Open';

  @override
  String get matchStatusFull => 'Full';

  @override
  String get matchStatusCompleted => 'Completed';

  @override
  String get confirmNo => 'Back';

  @override
  String get joinMatchButton => 'Join match';

  @override
  String get withdrawMatchButton => 'Withdraw';

  @override
  String get joinedConfirmed => 'You joined the match.';

  @override
  String get joinedReserve =>
      'The match is full. You were added to the reserve list.';

  @override
  String get youAreConfirmed => 'You are registered in this match.';

  @override
  String get youAreReserve => 'You are on the reserve list.';

  @override
  String get reserveListTitle => 'Reserve list';

  @override
  String get matchFullNote =>
      'The match is full. Joining now adds you to the reserve list.';

  @override
  String get withdrawConfirmTitle => 'Withdraw from this match?';

  @override
  String get withdrawConfirmBody =>
      'If you have a confirmed seat, the first reserve will take your place.';

  @override
  String get errOverlappingMatch =>
      'You are registered in another match at the same time.';

  @override
  String get errMatchClosed => 'Registration is closed for this match.';

  @override
  String get errAlreadyRegistered =>
      'You are already registered in this match.';

  @override
  String get errNotRegistered => 'You are not registered in this match.';

  @override
  String get joinMatchFailed => 'Failed to join the match. Please try again.';

  @override
  String get withdrawMatchFailed => 'Failed to withdraw. Please try again.';

  @override
  String homeGreeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'No notifications yet.';

  @override
  String get notifMatchUpdated => 'Match details were updated.';

  @override
  String get notifMovedToReserve =>
      'You were moved to the reserve list because the player count changed.';

  @override
  String get notifRemoved => 'The organizer removed you from the match.';

  @override
  String get notifPromoted =>
      'You were promoted from the reserve list to the starting players.';

  @override
  String get notifMatchDeleted => 'The match was deleted.';

  @override
  String get matchManagementTitle => 'Match management';

  @override
  String get editMatchTitle => 'Edit match';

  @override
  String get managePlayersTitle => 'Manage players';

  @override
  String get manageReserveTitle => 'Manage reserve list';

  @override
  String get matchTitleLabel => 'Match title';

  @override
  String get matchDescriptionLabel => 'Description';

  @override
  String get reducePlayersNote =>
      'If you lower the starting-player count, the latest players move to the reserve list and are notified.';

  @override
  String get saveButton => 'Save';

  @override
  String get matchUpdatedSaved =>
      'Match updated. Registered players were notified.';

  @override
  String get matchUpdateFailed => 'Failed to save the match. Please try again.';

  @override
  String get deleteMatchButton => 'Delete match';

  @override
  String get deleteMatchHint =>
      'Registered players are notified. Completed matches cannot be deleted.';

  @override
  String get deleteMatchConfirmTitle => 'Delete this match?';

  @override
  String get deleteMatchConfirmBody =>
      'All registrations will be removed and players notified. This cannot be undone.';

  @override
  String get removePlayerButton => 'Remove';

  @override
  String get removePlayerConfirmTitle => 'Remove player?';

  @override
  String removePlayerConfirmBody(String name) {
    return 'Remove $name from the match?';
  }

  @override
  String get rosterEmpty => 'No players here yet.';

  @override
  String get errMatchCompleted =>
      'This match is completed and can no longer be changed.';

  @override
  String get errNotAuthorized => 'You do not have permission to do this.';

  @override
  String get errRegistrationClosed =>
      'Registration is closed; the match reached its maximum.';

  @override
  String get errMatchLocked =>
      'The match has started and is locked until it finishes.';

  @override
  String get matchLockedNote =>
      'The match has started. Registration, withdrawals and roster changes are locked until it finishes.';

  @override
  String get errMaxBelowRegistered =>
      'Maximum registration cannot be lower than the number of registered players.';

  @override
  String get networkError =>
      'Could not reach the server. Check your internet connection.';

  @override
  String get loadFailed => 'Failed to load data.';

  @override
  String get retryButton => 'Retry';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get rolePlayer => 'Player';

  @override
  String get manageMembersTitle => 'Manage members';

  @override
  String get searchPlayersLabel => 'Search by name';

  @override
  String get searchPlayersHint => 'Type at least two letters';

  @override
  String get searchNoResults => 'No players found.';

  @override
  String get inviteAsRoleLabel => 'Invite as';

  @override
  String get invitationSent => 'Invitation sent.';

  @override
  String get myInvitationsEmpty => 'You have no invitations.';

  @override
  String get invitationAccepted => 'You joined the community.';

  @override
  String get invitationRevoked => 'Invitation revoked.';

  @override
  String get promoteToAdminButton => 'Make admin';

  @override
  String get demoteToPlayerButton => 'Make player';

  @override
  String get transferOwnershipButton => 'Transfer ownership';

  @override
  String get removeMemberButton => 'Remove from community';

  @override
  String get memberRoleChanged => 'Member role updated.';

  @override
  String get ownershipTransferred =>
      'Ownership transferred. You are now an admin.';

  @override
  String get memberRemoved => 'Member removed from the community.';

  @override
  String get transferOwnershipConfirmTitle => 'Transfer ownership?';

  @override
  String transferOwnershipConfirmBody(String name) {
    return '$name becomes the owner and you become an admin. Only the new owner can transfer it back.';
  }

  @override
  String get removeMemberConfirmTitle => 'Remove this member?';

  @override
  String removeMemberConfirmBody(String name) {
    return '$name will be removed from the community and withdrawn from every match in it.';
  }

  @override
  String get deleteCommunityButton => 'Delete community';

  @override
  String get deleteCommunityConfirmTitle => 'Delete this community?';

  @override
  String get deleteCommunityConfirmBody =>
      'All matches, registrations, members and invitations are deleted. This cannot be undone.';

  @override
  String get communityDeleted => 'Community deleted.';

  @override
  String get permissionOwnerOnly => 'Only the owner can do this.';

  @override
  String get permissionOrganizersOnly =>
      'Only the owner and admins can do this.';

  @override
  String get matchCreateOrganizersOnly =>
      'Only the owner and admins can create matches in this community.';

  @override
  String get matchManageOrganizersOnly =>
      'Match management now follows community roles. Ask an owner or admin of this community.';

  @override
  String get errCannotChangeOwnRole => 'You cannot change your own role.';

  @override
  String get errCannotRemoveSelf =>
      'You cannot remove yourself here. Leave the community instead.';

  @override
  String get errCannotRemoveOwner =>
      'The owner cannot be removed. Transfer ownership first.';

  @override
  String get errAlreadyOwner => 'That member is already the owner.';

  @override
  String get errMemberNotFound =>
      'That person is not a member of this community.';

  @override
  String get errInvalidRole => 'That role cannot be assigned.';

  @override
  String get inviteTitle => 'Invitation';

  @override
  String get inviteLoadError =>
      'We could not open this invitation. Check your connection and try again.';

  @override
  String get inviteNotFound =>
      'We could not find this invitation. The link may be incomplete.';

  @override
  String get inviteJoinCommunity => 'Join Community';

  @override
  String get inviteSignInFirst => 'Sign in or create an account to join.';

  @override
  String get inviteAlreadyMemberNote =>
      'You are already a member of this community.';

  @override
  String get shareInvitation => 'Share invitation';

  @override
  String get inviteLinkCopied =>
      'Invitation copied. Paste it wherever you share it.';

  @override
  String inviteShareCommunityBody(String community, String link) {
    return 'Join $community on Go Play:\n$link';
  }

  @override
  String get errNotCommunityMember => 'You are not a member of this community.';

  @override
  String get copyLinkButton => 'Copy';

  @override
  String matchCapacityLabel(int count) {
    return '👥 $count players';
  }

  @override
  String get matchTitleRequired => 'Match title is required';

  @override
  String get communityInvitationTitle => 'Invitation';

  @override
  String get communityInvitationHelp =>
      'Anyone with this link or code can join the community. Both carry the same code.';

  @override
  String get inviteLinkLabel => 'Invitation link';

  @override
  String get copyJoinCodeButton => 'Copy code';

  @override
  String get inviteOpenCommunity => 'Open community';

  @override
  String get inviteOpenAction => 'Open an invitation';

  @override
  String get invitePasteHint => 'Paste the invitation link or code';

  @override
  String get inviteInvalidInput => 'That is not an invitation link or code.';

  @override
  String get regenerateJoinCodeButton => 'Regenerate code';

  @override
  String get regenerateJoinCodeConfirmTitle => 'Regenerate the join code?';

  @override
  String get regenerateJoinCodeConfirmBody =>
      'The current link and code stop working immediately, so anyone still holding them cannot join. People already in the community stay members.';

  @override
  String get joinCodeRegenerated =>
      'New code issued. The old one no longer works.';

  @override
  String get joinPolicyLabel => 'Joining';

  @override
  String get joinPolicyOpen => 'Open join';

  @override
  String get joinPolicyOpenHelp => 'Anyone can join from the community list.';

  @override
  String get joinPolicyCodeRequired => 'Join by code';

  @override
  String get joinPolicyCodeRequiredHelp =>
      'People need the join code, or an invitation link that carries it.';

  @override
  String get joinPolicySaved => 'Join setting updated.';

  @override
  String get joinCodeRequiredPrompt => 'This community needs its join code.';

  @override
  String get adminTitle => 'Administration';

  @override
  String get adminUsersTab => 'Users';

  @override
  String get adminCommunitiesTab => 'Communities';

  @override
  String get adminMatchesTab => 'Matches';

  @override
  String get adminSearchLabel => 'Search';

  @override
  String get adminEmpty => 'Nothing found.';

  @override
  String get adminDeleteButton => 'Delete';

  @override
  String get adminDeleted => 'Deleted.';

  @override
  String adminDeleteConfirmTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get adminDeleteUserConfirmBody =>
      'The account and everything belonging to it are removed: communities they own, matches they created, memberships and registrations. This cannot be undone.';

  @override
  String get adminDeleteCommunityConfirmBody =>
      'The community and everything under it are removed: matches, memberships and registrations. This cannot be undone.';

  @override
  String get adminDeleteMatchConfirmBody =>
      'The match and its registrations are removed, and registered players are notified. This cannot be undone.';
}
