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
  String get navGroups => 'Groups';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneHint => 'e.g. 9665xxxxxxxx (with country code)';

  @override
  String get passwordLabel => 'Password';

  @override
  String get phoneRequired => 'Phone number is required';

  @override
  String get phoneInvalid => 'Enter a valid phone number with country code';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get loginTitle => 'Log in';

  @override
  String get loginButton => 'Log in';

  @override
  String get loginFailed =>
      'Login failed. Check your phone number and password.';

  @override
  String get noAccountPrompt => 'No account? Create one';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerButton => 'Create account';

  @override
  String get registerFailed => 'Registration failed. Please try again.';

  @override
  String get phoneAlreadyUsed => 'This phone number is already registered.';

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
  String get welcomeMessage => 'Logged in successfully';

  @override
  String get groupsTitle => 'Groups';

  @override
  String get groupsEmpty =>
      'You are not in any group yet.\nCreate a group or join one with a code.';

  @override
  String get createGroupTitle => 'Create group';

  @override
  String get createGroupButton => 'Create group';

  @override
  String get joinGroupTitle => 'Join group';

  @override
  String get joinGroupButton => 'Join';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get groupNameRequired => 'Group name is required';

  @override
  String get groupDescriptionLabel => 'Description (optional)';

  @override
  String get privateGroupLabel => 'Private group';

  @override
  String get privateGroupHelp =>
      'Private groups can only be joined with the join code.';

  @override
  String get joinCodeLabel => 'Join code';

  @override
  String get joinCodeRequired => 'Join code is required';

  @override
  String get groupNotFound => 'No group found with this code.';

  @override
  String get alreadyMember => 'You are already a member of this group.';

  @override
  String get groupCreateFailed =>
      'Failed to create the group. Please try again.';

  @override
  String get groupJoinFailed => 'Failed to join the group. Please try again.';

  @override
  String get membersTitle => 'Members';

  @override
  String get ownerBadge => 'Owner';

  @override
  String get joinCodeCopied => 'Join code copied';

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
  String get maxPlayersLabel => 'Max players';

  @override
  String get maxPlayersInvalid => 'Enter a number between 2 and 30';

  @override
  String get matchCreateFailed =>
      'Failed to create the match. Please try again.';

  @override
  String get groupMatchesEmpty => 'No matches in this group yet.';

  @override
  String get upcomingMatchesTitle => 'Upcoming matches';

  @override
  String get upcomingMatchesEmpty =>
      'No upcoming matches.\nJoin a group and create a match to get started.';

  @override
  String get matchStatusOpen => 'Open';

  @override
  String get matchStatusCancelled => 'Cancelled';

  @override
  String get matchStatusCompleted => 'Completed';

  @override
  String get playersCountLabel => 'Players';

  @override
  String get cancelMatchButton => 'Cancel match';

  @override
  String get cancelMatchConfirmTitle => 'Cancel this match?';

  @override
  String get cancelMatchConfirmBody => 'This cannot be undone.';

  @override
  String get confirmYes => 'Yes, cancel';

  @override
  String get confirmNo => 'Back';

  @override
  String get matchCancelFailed =>
      'Failed to cancel the match. Please try again.';

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
  String get loadFailed => 'Failed to load data.';

  @override
  String get retryButton => 'Retry';

  @override
  String get genericError => 'Something went wrong. Please try again.';
}
