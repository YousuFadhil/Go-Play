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
  String get secondaryPositionLabel => 'Secondary position (optional)';

  @override
  String get noSecondaryPosition => 'None';

  @override
  String get secondaryPositionSameAsPrimary =>
      'Secondary position must differ from the primary position';

  @override
  String get dateOfBirthLabel => 'Date of birth';

  @override
  String get dateOfBirthRequired => 'Date of birth is required';

  @override
  String get selectDateLabel => 'Select date';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileSaved => 'Profile updated.';

  @override
  String get profileSaveFailed =>
      'Failed to save your profile. Please try again.';

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
  String get historicalMatchToggleLabel => 'Record a match already played';

  @override
  String get historicalMatchToggleNote =>
      'Enter a fixture that has already happened. Nobody can register for it — you pick who played, then record the teams and the result.';

  @override
  String get historicalMatchDateNote =>
      'Pick the date and times the match was actually played.';

  @override
  String get historicalNotPastError =>
      'A match already played must have finished before now';

  @override
  String get recordHistoricalMatchButton => 'Record match';

  @override
  String get historicalMatchBadge => 'Already played';

  @override
  String get historicalMatchRecorded =>
      'Match recorded. Add who played from the Teams screen, then record the result.';

  @override
  String get errMatchHistorical =>
      'This match was recorded after it was played, so nobody can register for it.';

  @override
  String get startingPlayersLabel => 'Starting players';

  @override
  String get startingPlayersInvalid => 'Enter a number between 4 and 30';

  @override
  String capacityAutoNote(int reserve, int max) {
    return 'Reserve players: $reserve (automatic) — maximum registration: $max';
  }

  @override
  String get matchCreateFailed =>
      'Failed to create the match. Please try again.';

  @override
  String get errInvalidTitle => 'Enter a match name of at least 2 characters.';

  @override
  String get errInvalidLocation => 'Enter a location of at least 2 characters.';

  @override
  String get errCommunityInactive =>
      'This community is no longer active, so no new match can be created in it.';

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
  String get notifMatchDeleted => 'The match was cancelled.';

  @override
  String get notifMatchCreated => 'A new match has been created.';

  @override
  String get notifRegistrationOpened => 'Registration is now open.';

  @override
  String get notifMatchFull => 'The match is now full.';

  @override
  String get notifTeamsRegenerated => 'The teams were regenerated.';

  @override
  String get notifMatchStartingSoon =>
      'Your match starts in less than an hour.';

  @override
  String get notifMatchTimeChanged => 'The match time has changed.';

  @override
  String get notifCommunityInvitation =>
      'You have been invited to a community.';

  @override
  String get notifCommunityJoinAccepted => 'Your request to join was accepted.';

  @override
  String get notifCommunityPictureUpdated =>
      'The community picture was updated.';

  @override
  String get notifCommunityDescriptionUpdated =>
      'The community description was updated.';

  @override
  String get notifCommunitySettingsUpdated =>
      'The community settings were updated.';

  @override
  String get pushSettingsTitle => 'Push notifications';

  @override
  String get pushSettingsIntro =>
      'Every notification is kept in the app. These switches only decide what your phone alerts you about.';

  @override
  String get pushMatchLabel => 'Match notifications';

  @override
  String get pushMatchSubtitle => 'Registration, player changes and reminders.';

  @override
  String get pushCommunityLabel => 'Community notifications';

  @override
  String get pushCommunitySubtitle => 'Invitations and membership.';

  @override
  String get pushMuteAllLabel => 'Mute all push notifications';

  @override
  String get pushMuteAllSubtitle =>
      'Nothing is sent to your phone. Your notification history is unchanged.';

  @override
  String get pushSaveFailed => 'That setting could not be saved. Try again.';

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
      'Registered players are notified. Deleting a completed match also takes back every statistic and rating its result produced.';

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
  String get addPlayerButton => 'Add player';

  @override
  String get addPlayerEmpty =>
      'Every community member is already in this match.';

  @override
  String get addPlayerConfirmTitle => 'Add player?';

  @override
  String addPlayerConfirmBody(String name) {
    return 'Add $name to this match?';
  }

  @override
  String playerAddedConfirmed(String name) {
    return '$name was added to the starting players.';
  }

  @override
  String playerAddedReserve(String name) {
    return '$name was added to the reserve list.';
  }

  @override
  String addSelectedPlayersButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count players',
      one: 'Add 1 player',
    );
    return '$_temp0';
  }

  @override
  String playersAddedSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count players were added.',
      one: '1 player was added.',
    );
    return '$_temp0';
  }

  @override
  String playersAddedPartial(int added, int failed) {
    return '$added added, $failed could not be.';
  }

  @override
  String playersAddedNone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'None of the $count players could be added.',
      one: 'That player could not be added.',
    );
    return '$_temp0';
  }

  @override
  String get addPlayerFailed => 'That player could not be added. Try again.';

  @override
  String get errPlayerAlreadyRegistered =>
      'That player is already in this match.';

  @override
  String get errPlayerOverlappingMatch =>
      'That player is registered in another match at the same time.';

  @override
  String get errPlayerNotCommunityMember =>
      'That player is not a member of this community.';

  @override
  String professionalGuestName(String name) {
    return 'Professional ($name)';
  }

  @override
  String get professionalGuestLabel => 'Professional guest';

  @override
  String get addGuestButton => 'Add professional guest';

  @override
  String get addGuestTitle => 'Add a professional guest';

  @override
  String get renameGuestTitle => 'Rename professional guest';

  @override
  String get guestNameLabel => 'Name';

  @override
  String get guestNameInvalid => 'Enter a name between 2 and 60 characters.';

  @override
  String guestAddedConfirmed(String name) {
    return '$name was added to the starting players.';
  }

  @override
  String guestAddedReserve(String name) {
    return '$name was added to the reserve list.';
  }

  @override
  String get removeGuestButton => 'Remove guest';

  @override
  String get renameGuestButton => 'Rename';

  @override
  String get removeGuestConfirmTitle => 'Remove this professional guest?';

  @override
  String removeGuestConfirmBody(String name) {
    return '$name loses their place in this match. Anything they did in a match that was already played is kept.';
  }

  @override
  String removePlayedGuestConfirmBody(String name) {
    return '$name will be taken out of the record of who played this match. If they scored, correct the result first.';
  }

  @override
  String get guestActionFailed => 'That could not be done. Try again.';

  @override
  String get errInvalidGuestName => 'Enter a name between 2 and 60 characters.';

  @override
  String get errGuestNotFound => 'That guest is no longer in this match.';

  @override
  String get arrangeRosterTitle => 'Arrange participants';

  @override
  String get arrangeRosterSubtitle =>
      'Reorder the starting and reserve lists, or swap a participant between them.';

  @override
  String get arrangeRosterHint =>
      'Drag the handle to reorder a list. Tap a participant, then tap another to swap their places.';

  @override
  String arrangeStartingSection(int count, int capacity) {
    return 'Starting ($count/$capacity)';
  }

  @override
  String arrangeReserveSection(int count) {
    return 'Reserve ($count)';
  }

  @override
  String get arrangeModeManual => 'Arranged by an organizer';

  @override
  String get arrangeModeManualHelp =>
      'This match follows the order you set. Registration order no longer decides who starts.';

  @override
  String get arrangeModeRegistration => 'Registration order';

  @override
  String get arrangeModeRegistrationHelp =>
      'Players start in the order they joined, with professional guests after them. Your first change makes your own order the one that counts.';

  @override
  String arrangeSelectedHint(String name) {
    return '$name selected. Tap another participant to swap their places.';
  }

  @override
  String get arrangeClearSelection => 'Cancel';

  @override
  String get arrangeReorderHandle => 'Drag to reorder';

  @override
  String get arrangeSwapAction => 'Swap with the selected participant';

  @override
  String get arrangeSelectAction => 'Select for a swap';

  @override
  String get arrangeSaved => 'Order updated.';

  @override
  String get arrangeStartingEmpty => 'No starting participants yet.';

  @override
  String get arrangeReserveEmpty => 'Nobody is on the reserve list.';

  @override
  String get arrangeCompletedNote =>
      'This match has been played. The order is saved, and the starting list is kept as the record of who played.';

  @override
  String get errRosterChanged =>
      'The roster changed while you were arranging it. It has been reloaded — try again.';

  @override
  String get errInvalidSwap => 'Those two participants cannot be swapped.';

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

  @override
  String get teamsTitle => 'Teams';

  @override
  String get teamsEmpty => 'Teams have not been generated for this match yet.';

  @override
  String get generateTeamsButton => 'Generate teams';

  @override
  String get regenerateTeamsButton => 'Regenerate teams';

  @override
  String get regenerateTeamsConfirmTitle => 'Generate the teams again?';

  @override
  String get regenerateTeamsConfirmBody =>
      'The current teams are replaced by a new split of the confirmed players.';

  @override
  String get teamsGenerated => 'Teams generated.';

  @override
  String get teamAName => 'Team A';

  @override
  String get teamBName => 'Team B';

  @override
  String get teamsOutOfPosition => 'Out of position';

  @override
  String teamsPlayerRangeNote(int min, int max, int count) {
    return 'Generating teams needs between $min and $max confirmed players. This match has $count.';
  }

  @override
  String get errMissingPlayerInputs =>
      'Some confirmed players have an incomplete profile. Each of them needs a date of birth before teams can be generated.';

  @override
  String get errTeamsNotGenerated =>
      'Teams could not be generated from this roster.';

  @override
  String editPlayerTitle(String player) {
    return 'Edit $player';
  }

  @override
  String get movePlayerAction => 'Move to the other team';

  @override
  String get swapPlayerAction => 'Swap with a player';

  @override
  String get changePositionAction => 'Change position';

  @override
  String get swapPlayerTitle => 'Swap with';

  @override
  String get swapNobodyAvailable => 'The other team has nobody to swap with.';

  @override
  String get changePositionTitle => 'Assigned position';

  @override
  String get lineupUpdated => 'Lineup updated.';

  @override
  String get errLineupRefused =>
      'That change was refused. A team cannot have two goalkeepers.';

  @override
  String get errLineupNotChanged =>
      'That change no longer applies to this lineup. It has been reloaded.';

  @override
  String get matchResultTitle => 'Match result';

  @override
  String get saveResultButton => 'Save result';

  @override
  String get resultSaved => 'Match result saved successfully';

  @override
  String get resultOrganizersOnly =>
      'Only the community owner and admins can record a match result.';

  @override
  String get mvpLabel => 'MVP';

  @override
  String get addGoalLabel => 'Add a goal';

  @override
  String get removeGoalLabel => 'Remove a goal';

  @override
  String goalsScoredLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count goals',
      one: '1 goal',
      zero: 'No goals',
    );
    return '$_temp0';
  }

  @override
  String goalsRecordedNote(int recorded, int total) {
    return '$recorded of $total goals assigned to a scorer.';
  }

  @override
  String get editResultConfirmTitle => 'Replace the recorded result?';

  @override
  String get editResultConfirmBody =>
      'The ratings and statistics the previous result produced are reversed, and the new result is applied instead.';

  @override
  String get errGoalsDoNotMatchScore =>
      'The goals assigned to scorers must add up to the final score.';

  @override
  String get errMvpNotParticipant =>
      'The best player must be one of the players in this match.';

  @override
  String get errScorerNotParticipant =>
      'A goal can only be credited to a player in this match.';

  @override
  String get errResultNeedsLineup =>
      'Teams have not been generated for this match yet. The result needs to know which side each player was on.';

  @override
  String get errInvalidResultNumbers =>
      'The result could not be saved. Check the scores and the goals.';

  @override
  String get dashboardTab => 'Dashboard';

  @override
  String get statisticsTab => 'Statistics';

  @override
  String get communityStatisticsTitle => 'Community statistics';

  @override
  String get statTotalMatches => 'Total matches';

  @override
  String get statTotalPlayers => 'Total players';

  @override
  String get statTotalGoals => 'Total goals';

  @override
  String get statLeadersTitle => 'Leaders';

  @override
  String get statTopScorer => 'Top scorer';

  @override
  String get statMostActivePlayer => 'Most active player';

  @override
  String get statMostMvp => 'Most valuable player';

  @override
  String get statNoneYet => 'Not yet';

  @override
  String get statFormerPlayer => 'Former player';

  @override
  String statMatchesPlayedValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
      zero: 'No matches',
    );
    return '$_temp0';
  }

  @override
  String statMvpValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '1 time',
      zero: 'Never',
    );
    return '$_temp0';
  }

  @override
  String get statScopeNote =>
      'Every figure here counts completed matches only — a match still open or full contributes nothing. Player figures count matches whose result has been recorded.';

  @override
  String get statEmptyBody =>
      'No results have been recorded in this community yet. Statistics appear once a match result is saved.';

  @override
  String get playerStatisticsTitle => 'My statistics';

  @override
  String get statCurrentRating => 'Current rating';

  @override
  String get statMatchesPlayed => 'Matches played';

  @override
  String get statWins => 'Wins';

  @override
  String get statDraws => 'Draws';

  @override
  String get statLosses => 'Losses';

  @override
  String get statGoals => 'Goals';

  @override
  String get statMvpCount => 'Best player awards';

  @override
  String get statCareerNote =>
      'Your record across every community you play in. These figures are set by the app when a match result is recorded, and count matches whose result has been saved.';

  @override
  String get statNoMatchesYet =>
      'You have not played a recorded match yet. Your figures start at zero and the rating is the starting rating every player is given.';

  @override
  String get leaderboardsTab => 'Leaderboards';

  @override
  String get leaderboardHighestRated => 'Highest rated';

  @override
  String get leaderboardTopScorer => 'Top scorer';

  @override
  String get leaderboardMostMvp => 'Most valuable player';

  @override
  String get leaderboardMostActive => 'Most active';

  @override
  String get leaderboardMostWins => 'Most wins';

  @override
  String leaderboardWinsValue(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wins',
      one: '1 win',
      zero: 'No wins',
    );
    return '$_temp0';
  }

  @override
  String get leaderboardsEmpty =>
      'No leaderboards yet. Once a match result is recorded, this is where the community sees who is leading.';

  @override
  String get leaderboardRatingNote =>
      'Highest rated ranks by the player\'s overall rating across every community.';

  @override
  String get shareCardTitle => 'Share card';

  @override
  String get shareCardShareAction => 'Share';

  @override
  String get shareCardCloseAction => 'Close';

  @override
  String get shareCardPreparing => 'Preparing your card…';

  @override
  String get errShareCardRender =>
      'The card could not be created. Please try again.';

  @override
  String get errShareCardShare => 'Sharing is not available right now.';

  @override
  String get shareCardStatMatches => 'Matches';

  @override
  String get shareCardStatWins => 'Wins';

  @override
  String get shareCardPeriodAllTime => 'All time';

  @override
  String get shareCardStatDraws => 'Draws';

  @override
  String get shareCardStatLosses => 'Losses';

  @override
  String shareCardPeriodBadge(String period) {
    return 'Period · $period';
  }

  @override
  String get shareLeaderboardsAction => 'Share leaderboards';

  @override
  String showPreviousResults(int count) {
    return 'Show previous results ($count)';
  }

  @override
  String get hidePreviousResults => 'Hide previous results';

  @override
  String get shareCardStatGoals => 'Goals';

  @override
  String get shareCardStatMvp => 'MVP';

  @override
  String get shareMyStatisticsAction => 'Share my statistics';

  @override
  String get shareCardStatPlayers => 'Players';

  @override
  String get shareCommunityStatisticsAction => 'Share community statistics';

  @override
  String get shareTeamLineupAction => 'Share the lineup';

  @override
  String get shareMatchResultAction => 'Share the result';

  @override
  String get shareCardDownloaded => 'Image saved to your downloads.';

  @override
  String get matchResultScorersLabel => 'Scorers';

  @override
  String get matchResultDrawLabel => 'Draw';

  @override
  String get matchResultWinnerLabel => 'Winner';

  @override
  String get matchResultNotRecorded =>
      'No result has been recorded for this match yet.';

  @override
  String get statPeriodLabel => 'Period';

  @override
  String get statPeriodWeekly => 'Weekly';

  @override
  String get statPeriodMonthly => 'Monthly';

  @override
  String get statPeriodAllTime => 'All time';

  @override
  String get statPeriodWeeklyNote =>
      'This week\'s figures. Weeks run Monday to Sunday, Oman time.';

  @override
  String get statPeriodMonthlyNote =>
      'This calendar month\'s figures, Oman time.';

  @override
  String get statPeriodRatingNote =>
      'The rating is your current rating across every community. It is not a figure for this period.';

  @override
  String get statPeriodNoMatches =>
      'You have not played a recorded match in this period.';

  @override
  String get statPeriodEmptyBody =>
      'No results have been recorded in this community in this period.';

  @override
  String get leaderboardsPeriodEmpty =>
      'No results have been recorded in this period, so there is nothing to rank yet.';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get changeAction => 'Change';

  @override
  String get editProfileTitle => 'Edit profile';

  @override
  String get editProfileAction => 'Edit profile';

  @override
  String get profilePersonalSection => 'Personal information';

  @override
  String get profileAccountSection => 'Account';

  @override
  String get profilePlayingSection => 'Playing profile';

  @override
  String get passwordHiddenNote => 'Hidden for your security';

  @override
  String get changeEmailTitle => 'Change email';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get passwordsDoNotMatch => 'The two passwords do not match';

  @override
  String get passwordChanged => 'Password changed.';

  @override
  String get emailChangeRequested =>
      'Check your new address for the confirmation link.';

  @override
  String get avatarChangeAction => 'Change photo';

  @override
  String get avatarSourceCamera => 'Take a photo';

  @override
  String get avatarSourceGallery => 'Choose from gallery';

  @override
  String get ageLabel => 'Age';

  @override
  String get avatarRemoveAction => 'Remove photo';

  @override
  String get avatarUpdated => 'Photo updated.';

  @override
  String get avatarRemoved => 'Photo removed.';

  @override
  String get avatarUploadFailed =>
      'Could not update the photo. Please try again.';

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years old',
      one: '1 year old',
    );
    return '$_temp0';
  }

  @override
  String get logoutConfirmTitle => 'Log out?';

  @override
  String get logoutConfirmBody =>
      'You will need to sign in again to use Go Play.';

  @override
  String get completedMatchesTitle => 'Completed matches';

  @override
  String get addPlayedPlayerAction => 'Add a player who played';

  @override
  String get addPlayedPlayerNobodyAvailable =>
      'Every community member is already in this lineup.';

  @override
  String get removePlayedPlayerAction => 'Remove from the match';

  @override
  String get removePlayedPlayerConfirmTitle => 'Remove this player?';

  @override
  String removePlayedPlayerConfirmBody(String name) {
    return '$name will be taken out of the lineup, and every statistic and rating this match gave them will be taken back.';
  }

  @override
  String get editPlayedMatchNote =>
      'Changes to a completed match recalculate statistics, ratings and leaderboards.';

  @override
  String get chooseTeamTitle => 'Which team?';

  @override
  String get choosePositionTitle => 'Which position?';

  @override
  String get errResultParticipantRemoved =>
      'This player is the best player or a scorer in the recorded result. Edit the result first.';

  @override
  String get errMatchNotCompleted =>
      'Only a completed match\'s players can be corrected this way.';

  @override
  String get communityTitle => 'Community';

  @override
  String get discoverHeroTitle => 'Football, with your people.';

  @override
  String get discoverHeroBody =>
      'Find a community near you, see what is being played this week, and take your place on the pitch.';

  @override
  String get discoverAlreadyHaveAccount => 'Already have an account? Log in';

  @override
  String discoverSeatsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places left',
      one: '1 place left',
    );
    return '$_temp0';
  }

  @override
  String discoverMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No members',
    );
    return '$_temp0';
  }

  @override
  String discoverUpcomingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count upcoming matches',
      one: '1 upcoming match',
    );
    return '$_temp0';
  }

  @override
  String get discoverNoUpcomingMatches =>
      'Nothing is scheduled just yet. Check back soon.';

  @override
  String get discoverNoCommunities =>
      'No communities yet. Be the first to start one.';

  @override
  String get discoverCtaTitle => 'Ready to play?';

  @override
  String get discoverCtaBody =>
      'Create an account to join a community, register for matches, and start your own.';

  @override
  String get authRequiredTitle => 'Account needed';

  @override
  String get authRequiredJoinCommunity =>
      'Create an account to join this community.';

  @override
  String get authRequiredRegisterMatch =>
      'Create an account to register for this match.';

  @override
  String get authRequiredCreateCommunity =>
      'Create an account to start your own community.';

  @override
  String get mvpOptionalNote =>
      'Tap a star to name the best player. This is optional — the result saves without one.';

  @override
  String get navDiscover => 'Discover';

  @override
  String get viewCommunityAction => 'View community';

  @override
  String get viewMatchAction => 'View match';

  @override
  String discoverWelcomeBack(String name) {
    return 'Welcome back, $name';
  }

  @override
  String get discoverHeroBodySignedIn =>
      'See what your communities are playing this week, and find new ones to join.';

  @override
  String discoverCommunityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count communities',
      one: '1 community',
      zero: 'No communities',
    );
    return '$_temp0';
  }

  @override
  String get discoverCtaTitleSignedIn => 'Start something of your own';

  @override
  String get discoverCtaBodySignedIn =>
      'Create a community and bring your regular game together in one place.';

  @override
  String get discoverMatchesSubtitle => 'Games with places still open';

  @override
  String get discoverCommunitiesSubtitle => 'Clubs you can join';

  @override
  String get homeUpcomingSubtitle => 'Across your communities';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsNotificationsSection => 'Notifications';

  @override
  String get languageLabel => 'App language';

  @override
  String get languageSystemDefault => 'Device language';

  @override
  String get languageSystemDefaultHelp =>
      'Go Play follows the language your phone is set to.';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get showMoreLabel => 'Show more';

  @override
  String get showLessLabel => 'Show less';

  @override
  String get communityActionsTitle => 'Community actions';

  @override
  String get moreActionsLabel => 'More actions';

  @override
  String get joinCodeOrganizersOnly =>
      'The join code is shown to the owner and admins only.';

  @override
  String get membersEmpty => 'Nobody has joined this community yet.';

  @override
  String get matchRosterEmpty => 'Nobody has joined this match yet.';

  @override
  String get matchManagementSubtitle =>
      'Edit the match, manage the roster, or delete it.';

  @override
  String get statCompletedMatches => 'Completed matches';

  @override
  String get leaderboardTopPlayer => 'Leader';

  @override
  String get matchMembershipRequiredTitle => 'Join the community first';

  @override
  String matchMembershipRequiredBody(String community) {
    return 'This match belongs to $community. Join the community to see the match and register for it.';
  }

  @override
  String get matchMembershipRequiredBodyUnnamed =>
      'This match belongs to a community you have not joined. Join the community to see the match and register for it.';

  @override
  String get playerProfileTitle => 'Player profile';

  @override
  String get openPlayerProfileAction => 'Open player profile';

  @override
  String get profileNotVisibleTitle => 'Profile not available';

  @override
  String get errProfileNotVisible =>
      'This player shares their profile with their community members only.';

  @override
  String get settingsPrivacySection => 'Privacy';

  @override
  String get profileVisibilityEveryone => 'Everyone';

  @override
  String get profileVisibilityEveryoneHelp =>
      'Any Go Play player can open your profile.';

  @override
  String get profileVisibilityCommunityMembers => 'Community members only';

  @override
  String get profileVisibilityCommunityMembersHelp =>
      'Only players who share a community with you can open your profile.';

  @override
  String teamsShownOutOfLine(String position) {
    return 'Drawn in another line. Position: $position.';
  }

  @override
  String get profileAgeVisibleLabel => 'Show my age';

  @override
  String get profileAgeVisibleHelp =>
      'Your age is worked out from your date of birth. Turn this off and other players will not see it.';

  @override
  String get latestResultsTitle => 'Latest results';

  @override
  String get latestResultsSubtitle => 'What has just been played';

  @override
  String get latestResultsEmpty =>
      'No results yet. Once a match is played it shows up here.';

  @override
  String get latestResultsFailed => 'Could not load recent football.';

  @override
  String get resultPendingLabel => 'Result pending';

  @override
  String get footballRecordTitle => 'Football record';

  @override
  String get footballMatchTitle => 'Match';

  @override
  String get topPlayersTitle => 'Top players';

  @override
  String get topPlayersSubtitle => 'Ranked by rating, then goals';

  @override
  String get topPlayersEmpty => 'Nobody has a record here yet.';

  @override
  String get recentResultsTitle => 'Recent results';

  @override
  String get statPlayersWithRecord => 'Players';

  @override
  String get statMvps => 'MVPs';

  @override
  String get lineupUnavailable =>
      'No lineup was saved for this match. This is who took part.';

  @override
  String get rosterTitle => 'Who played';

  @override
  String goalsShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count goals',
      one: '$count goal',
    );
    return '$_temp0';
  }

  @override
  String get communityFootballTitle => 'Football';
}
