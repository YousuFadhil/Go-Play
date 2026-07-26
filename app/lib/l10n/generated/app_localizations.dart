import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Go Play'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navCommunities.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get navCommunities;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get emailInvalid;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneLabel;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'8 digits, e.g. 9012 3456'**
  String get phoneHint;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @phoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phoneRequired;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an 8-digit phone number'**
  String get phoneInvalid;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordTooShort;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginTitle;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginButton;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Check your email and password.'**
  String get loginFailed;

  /// No description provided for @noAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'No account? Create one'**
  String get noAccountPrompt;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// No description provided for @registerButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Please try again.'**
  String get registerFailed;

  /// No description provided for @emailAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered.'**
  String get emailAlreadyUsed;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullNameLabel;

  /// No description provided for @fullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get fullNameRequired;

  /// No description provided for @positionLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary position'**
  String get positionLabel;

  /// No description provided for @positionRequired.
  ///
  /// In en, this message translates to:
  /// **'Primary position is required'**
  String get positionRequired;

  /// No description provided for @haveAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Have an account? Log in'**
  String get haveAccountPrompt;

  /// No description provided for @positionGk.
  ///
  /// In en, this message translates to:
  /// **'Goalkeeper'**
  String get positionGk;

  /// No description provided for @positionDef.
  ///
  /// In en, this message translates to:
  /// **'Defender'**
  String get positionDef;

  /// No description provided for @positionMid.
  ///
  /// In en, this message translates to:
  /// **'Midfielder'**
  String get positionMid;

  /// No description provided for @positionFwd.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get positionFwd;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @logoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutLabel;

  /// No description provided for @communitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get communitiesTitle;

  /// No description provided for @communitiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'You are not in any community yet.\nCreate one or join with a code.'**
  String get communitiesEmpty;

  /// No description provided for @createCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Create community'**
  String get createCommunityTitle;

  /// No description provided for @createCommunityButton.
  ///
  /// In en, this message translates to:
  /// **'Create community'**
  String get createCommunityButton;

  /// No description provided for @joinCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Join community'**
  String get joinCommunityTitle;

  /// No description provided for @joinCommunityButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinCommunityButton;

  /// No description provided for @communityNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Community name'**
  String get communityNameLabel;

  /// No description provided for @communityNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Community name is required'**
  String get communityNameRequired;

  /// No description provided for @communityDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get communityDescriptionLabel;

  /// No description provided for @privateCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Private community'**
  String get privateCommunityLabel;

  /// No description provided for @privateCommunityHelp.
  ///
  /// In en, this message translates to:
  /// **'Private communities can only be joined with the join code.'**
  String get privateCommunityHelp;

  /// No description provided for @joinCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Join code'**
  String get joinCodeLabel;

  /// No description provided for @joinCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Join code is required'**
  String get joinCodeRequired;

  /// No description provided for @communityNotFound.
  ///
  /// In en, this message translates to:
  /// **'No community found with this code.'**
  String get communityNotFound;

  /// No description provided for @alreadyMemberOfCommunity.
  ///
  /// In en, this message translates to:
  /// **'You are already a member of this community.'**
  String get alreadyMemberOfCommunity;

  /// No description provided for @communityCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the community. Please try again.'**
  String get communityCreateFailed;

  /// No description provided for @communityJoinFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to join the community. Please try again.'**
  String get communityJoinFailed;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTitle;

  /// No description provided for @joinCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Join code copied'**
  String get joinCodeCopied;

  /// No description provided for @myCommunitiesSection.
  ///
  /// In en, this message translates to:
  /// **'My communities'**
  String get myCommunitiesSection;

  /// No description provided for @publicCommunitiesSection.
  ///
  /// In en, this message translates to:
  /// **'Public communities'**
  String get publicCommunitiesSection;

  /// No description provided for @joinedCommunity.
  ///
  /// In en, this message translates to:
  /// **'You joined the community.'**
  String get joinedCommunity;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matchesTitle;

  /// No description provided for @createMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Create match'**
  String get createMatchTitle;

  /// No description provided for @createMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Create match'**
  String get createMatchButton;

  /// No description provided for @matchDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Match details'**
  String get matchDetailsTitle;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @locationRequired.
  ///
  /// In en, this message translates to:
  /// **'Location is required'**
  String get locationRequired;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @startTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get startTimeLabel;

  /// No description provided for @endTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get endTimeLabel;

  /// No description provided for @dateTimeRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick the date and times'**
  String get dateTimeRequired;

  /// No description provided for @endAfterStartError.
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time'**
  String get endAfterStartError;

  /// No description provided for @startInPastError.
  ///
  /// In en, this message translates to:
  /// **'Match must start in the future'**
  String get startInPastError;

  /// No description provided for @startingPlayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Starting players'**
  String get startingPlayersLabel;

  /// No description provided for @startingPlayersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a number between 2 and 30'**
  String get startingPlayersInvalid;

  /// No description provided for @capacityAutoNote.
  ///
  /// In en, this message translates to:
  /// **'Reserve players: {reserve} (automatic) — maximum registration: {max}'**
  String capacityAutoNote(int reserve, int max);

  /// No description provided for @matchCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the match. Please try again.'**
  String get matchCreateFailed;

  /// No description provided for @communityMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matches in this community yet.'**
  String get communityMatchesEmpty;

  /// No description provided for @upcomingMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming matches'**
  String get upcomingMatchesTitle;

  /// No description provided for @upcomingMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No upcoming matches.\nJoin a community to get started.'**
  String get upcomingMatchesEmpty;

  /// No description provided for @matchStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get matchStatusOpen;

  /// No description provided for @matchStatusFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get matchStatusFull;

  /// No description provided for @matchStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get matchStatusCompleted;

  /// No description provided for @confirmNo.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get confirmNo;

  /// No description provided for @joinMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Join match'**
  String get joinMatchButton;

  /// No description provided for @withdrawMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawMatchButton;

  /// No description provided for @joinedConfirmed.
  ///
  /// In en, this message translates to:
  /// **'You joined the match.'**
  String get joinedConfirmed;

  /// No description provided for @joinedReserve.
  ///
  /// In en, this message translates to:
  /// **'The match is full. You were added to the reserve list.'**
  String get joinedReserve;

  /// No description provided for @youAreConfirmed.
  ///
  /// In en, this message translates to:
  /// **'You are registered in this match.'**
  String get youAreConfirmed;

  /// No description provided for @youAreReserve.
  ///
  /// In en, this message translates to:
  /// **'You are on the reserve list.'**
  String get youAreReserve;

  /// No description provided for @reserveListTitle.
  ///
  /// In en, this message translates to:
  /// **'Reserve list'**
  String get reserveListTitle;

  /// No description provided for @matchFullNote.
  ///
  /// In en, this message translates to:
  /// **'The match is full. Joining now adds you to the reserve list.'**
  String get matchFullNote;

  /// No description provided for @withdrawConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw from this match?'**
  String get withdrawConfirmTitle;

  /// No description provided for @withdrawConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'If you have a confirmed seat, the first reserve will take your place.'**
  String get withdrawConfirmBody;

  /// No description provided for @errOverlappingMatch.
  ///
  /// In en, this message translates to:
  /// **'You are registered in another match at the same time.'**
  String get errOverlappingMatch;

  /// No description provided for @errMatchClosed.
  ///
  /// In en, this message translates to:
  /// **'Registration is closed for this match.'**
  String get errMatchClosed;

  /// No description provided for @errAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'You are already registered in this match.'**
  String get errAlreadyRegistered;

  /// No description provided for @errNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'You are not registered in this match.'**
  String get errNotRegistered;

  /// No description provided for @joinMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to join the match. Please try again.'**
  String get joinMatchFailed;

  /// No description provided for @withdrawMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to withdraw. Please try again.'**
  String get withdrawMatchFailed;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String homeGreeting(String name);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get notificationsEmpty;

  /// No description provided for @notifMatchUpdated.
  ///
  /// In en, this message translates to:
  /// **'Match details were updated.'**
  String get notifMatchUpdated;

  /// No description provided for @notifMovedToReserve.
  ///
  /// In en, this message translates to:
  /// **'You were moved to the reserve list because the player count changed.'**
  String get notifMovedToReserve;

  /// No description provided for @notifRemoved.
  ///
  /// In en, this message translates to:
  /// **'The organizer removed you from the match.'**
  String get notifRemoved;

  /// No description provided for @notifPromoted.
  ///
  /// In en, this message translates to:
  /// **'You were promoted from the reserve list to the starting players.'**
  String get notifPromoted;

  /// No description provided for @notifMatchDeleted.
  ///
  /// In en, this message translates to:
  /// **'The match was deleted.'**
  String get notifMatchDeleted;

  /// No description provided for @matchManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Match management'**
  String get matchManagementTitle;

  /// No description provided for @editMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit match'**
  String get editMatchTitle;

  /// No description provided for @managePlayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage players'**
  String get managePlayersTitle;

  /// No description provided for @manageReserveTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage reserve list'**
  String get manageReserveTitle;

  /// No description provided for @matchTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Match title (optional)'**
  String get matchTitleLabel;

  /// No description provided for @matchDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get matchDescriptionLabel;

  /// No description provided for @reducePlayersNote.
  ///
  /// In en, this message translates to:
  /// **'If you lower the starting-player count, the latest players move to the reserve list and are notified.'**
  String get reducePlayersNote;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @matchUpdatedSaved.
  ///
  /// In en, this message translates to:
  /// **'Match updated. Registered players were notified.'**
  String get matchUpdatedSaved;

  /// No description provided for @matchUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save the match. Please try again.'**
  String get matchUpdateFailed;

  /// No description provided for @deleteMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Delete match'**
  String get deleteMatchButton;

  /// No description provided for @deleteMatchHint.
  ///
  /// In en, this message translates to:
  /// **'Registered players are notified. Completed matches cannot be deleted.'**
  String get deleteMatchHint;

  /// No description provided for @deleteMatchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this match?'**
  String get deleteMatchConfirmTitle;

  /// No description provided for @deleteMatchConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All registrations will be removed and players notified. This cannot be undone.'**
  String get deleteMatchConfirmBody;

  /// No description provided for @removePlayerButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removePlayerButton;

  /// No description provided for @removePlayerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove player?'**
  String get removePlayerConfirmTitle;

  /// No description provided for @removePlayerConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from the match?'**
  String removePlayerConfirmBody(String name);

  /// No description provided for @rosterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No players here yet.'**
  String get rosterEmpty;

  /// No description provided for @errMatchCompleted.
  ///
  /// In en, this message translates to:
  /// **'This match is completed and can no longer be changed.'**
  String get errMatchCompleted;

  /// No description provided for @errNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do this.'**
  String get errNotAuthorized;

  /// No description provided for @errRegistrationClosed.
  ///
  /// In en, this message translates to:
  /// **'Registration is closed; the match reached its maximum.'**
  String get errRegistrationClosed;

  /// No description provided for @errMatchLocked.
  ///
  /// In en, this message translates to:
  /// **'The match has started and is locked until it finishes.'**
  String get errMatchLocked;

  /// No description provided for @matchLockedNote.
  ///
  /// In en, this message translates to:
  /// **'The match has started. Registration, withdrawals and roster changes are locked until it finishes.'**
  String get matchLockedNote;

  /// No description provided for @errMaxBelowRegistered.
  ///
  /// In en, this message translates to:
  /// **'Maximum registration cannot be lower than the number of registered players.'**
  String get errMaxBelowRegistered;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your internet connection.'**
  String get networkError;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data.'**
  String get loadFailed;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @rolePlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get rolePlayer;

  /// No description provided for @manageMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage members'**
  String get manageMembersTitle;

  /// No description provided for @myInvitationsTitle.
  ///
  /// In en, this message translates to:
  /// **'My invitations'**
  String get myInvitationsTitle;

  /// No description provided for @pendingInvitationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending invitations'**
  String get pendingInvitationsTitle;

  /// No description provided for @inviteMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite a player'**
  String get inviteMemberTitle;

  /// No description provided for @inviteButton.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get inviteButton;

  /// No description provided for @searchPlayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchPlayersLabel;

  /// No description provided for @searchPlayersHint.
  ///
  /// In en, this message translates to:
  /// **'Type at least two letters'**
  String get searchPlayersHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No players found.'**
  String get searchNoResults;

  /// No description provided for @inviteAsRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite as'**
  String get inviteAsRoleLabel;

  /// No description provided for @invitationSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent.'**
  String get invitationSent;

  /// No description provided for @invitationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending invitations.'**
  String get invitationsEmpty;

  /// No description provided for @myInvitationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no invitations.'**
  String get myInvitationsEmpty;

  /// No description provided for @invitationFrom.
  ///
  /// In en, this message translates to:
  /// **'Invitation to join {community}'**
  String invitationFrom(String community);

  /// No description provided for @acceptInvitationButton.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptInvitationButton;

  /// No description provided for @revokeInvitationButton.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revokeInvitationButton;

  /// No description provided for @invitationAccepted.
  ///
  /// In en, this message translates to:
  /// **'You joined the community.'**
  String get invitationAccepted;

  /// No description provided for @invitationRevoked.
  ///
  /// In en, this message translates to:
  /// **'Invitation revoked.'**
  String get invitationRevoked;

  /// No description provided for @promoteToAdminButton.
  ///
  /// In en, this message translates to:
  /// **'Make admin'**
  String get promoteToAdminButton;

  /// No description provided for @demoteToPlayerButton.
  ///
  /// In en, this message translates to:
  /// **'Make player'**
  String get demoteToPlayerButton;

  /// No description provided for @transferOwnershipButton.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get transferOwnershipButton;

  /// No description provided for @removeMemberButton.
  ///
  /// In en, this message translates to:
  /// **'Remove from community'**
  String get removeMemberButton;

  /// No description provided for @memberRoleChanged.
  ///
  /// In en, this message translates to:
  /// **'Member role updated.'**
  String get memberRoleChanged;

  /// No description provided for @ownershipTransferred.
  ///
  /// In en, this message translates to:
  /// **'Ownership transferred. You are now an admin.'**
  String get ownershipTransferred;

  /// No description provided for @memberRemoved.
  ///
  /// In en, this message translates to:
  /// **'Member removed from the community.'**
  String get memberRemoved;

  /// No description provided for @transferOwnershipConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership?'**
  String get transferOwnershipConfirmTitle;

  /// No description provided for @transferOwnershipConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} becomes the owner and you become an admin. Only the new owner can transfer it back.'**
  String transferOwnershipConfirmBody(String name);

  /// No description provided for @removeMemberConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this member?'**
  String get removeMemberConfirmTitle;

  /// No description provided for @removeMemberConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be removed from the community and withdrawn from every match in it.'**
  String removeMemberConfirmBody(String name);

  /// No description provided for @deleteCommunityButton.
  ///
  /// In en, this message translates to:
  /// **'Delete community'**
  String get deleteCommunityButton;

  /// No description provided for @deleteCommunityConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this community?'**
  String get deleteCommunityConfirmTitle;

  /// No description provided for @deleteCommunityConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All matches, registrations, members and invitations are deleted. This cannot be undone.'**
  String get deleteCommunityConfirmBody;

  /// No description provided for @communityDeleted.
  ///
  /// In en, this message translates to:
  /// **'Community deleted.'**
  String get communityDeleted;

  /// No description provided for @permissionOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the owner can do this.'**
  String get permissionOwnerOnly;

  /// No description provided for @permissionOrganizersOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the owner and admins can do this.'**
  String get permissionOrganizersOnly;

  /// No description provided for @matchCreateOrganizersOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the owner and admins can create matches in this community.'**
  String get matchCreateOrganizersOnly;

  /// No description provided for @matchManageOrganizersOnly.
  ///
  /// In en, this message translates to:
  /// **'Match management now follows community roles. Ask an owner or admin of this community.'**
  String get matchManageOrganizersOnly;

  /// No description provided for @errCannotChangeOwnRole.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your own role.'**
  String get errCannotChangeOwnRole;

  /// No description provided for @errCannotRemoveSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot remove yourself here. Leave the community instead.'**
  String get errCannotRemoveSelf;

  /// No description provided for @errCannotRemoveOwner.
  ///
  /// In en, this message translates to:
  /// **'The owner cannot be removed. Transfer ownership first.'**
  String get errCannotRemoveOwner;

  /// No description provided for @errAlreadyOwner.
  ///
  /// In en, this message translates to:
  /// **'That member is already the owner.'**
  String get errAlreadyOwner;

  /// No description provided for @errMemberNotFound.
  ///
  /// In en, this message translates to:
  /// **'That person is not a member of this community.'**
  String get errMemberNotFound;

  /// No description provided for @errInvitationExists.
  ///
  /// In en, this message translates to:
  /// **'There is already a pending invitation for this player.'**
  String get errInvitationExists;

  /// No description provided for @errInvitationNotFound.
  ///
  /// In en, this message translates to:
  /// **'This invitation no longer exists.'**
  String get errInvitationNotFound;

  /// No description provided for @errInvitationNotPending.
  ///
  /// In en, this message translates to:
  /// **'This invitation has already been used.'**
  String get errInvitationNotPending;

  /// No description provided for @errInvitationExpired.
  ///
  /// In en, this message translates to:
  /// **'This invitation has expired.'**
  String get errInvitationExpired;

  /// No description provided for @errInvalidRole.
  ///
  /// In en, this message translates to:
  /// **'That role cannot be assigned.'**
  String get errInvalidRole;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
