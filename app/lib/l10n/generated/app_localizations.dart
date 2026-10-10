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

  /// No description provided for @secondaryPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Secondary position (optional)'**
  String get secondaryPositionLabel;

  /// No description provided for @noSecondaryPosition.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noSecondaryPosition;

  /// No description provided for @secondaryPositionSameAsPrimary.
  ///
  /// In en, this message translates to:
  /// **'Secondary position must differ from the primary position'**
  String get secondaryPositionSameAsPrimary;

  /// No description provided for @dateOfBirthLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get dateOfBirthLabel;

  /// No description provided for @dateOfBirthRequired.
  ///
  /// In en, this message translates to:
  /// **'Date of birth is required'**
  String get dateOfBirthRequired;

  /// No description provided for @selectDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDateLabel;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get profileSaved;

  /// No description provided for @profileSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save your profile. Please try again.'**
  String get profileSaveFailed;

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

  /// No description provided for @historicalMatchToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Record a match already played'**
  String get historicalMatchToggleLabel;

  /// No description provided for @historicalMatchToggleNote.
  ///
  /// In en, this message translates to:
  /// **'Enter a fixture that has already happened. Nobody can register for it — you pick who played, then record the teams and the result.'**
  String get historicalMatchToggleNote;

  /// No description provided for @historicalMatchDateNote.
  ///
  /// In en, this message translates to:
  /// **'Pick the date and times the match was actually played.'**
  String get historicalMatchDateNote;

  /// No description provided for @historicalNotPastError.
  ///
  /// In en, this message translates to:
  /// **'A match already played must have finished before now'**
  String get historicalNotPastError;

  /// No description provided for @matchAlreadyEndedError.
  ///
  /// In en, this message translates to:
  /// **'This match has already ended. Record it as a match already played instead.'**
  String get matchAlreadyEndedError;

  /// No description provided for @recordHistoricalMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Record match'**
  String get recordHistoricalMatchButton;

  /// No description provided for @historicalMatchBadge.
  ///
  /// In en, this message translates to:
  /// **'Already played'**
  String get historicalMatchBadge;

  /// No description provided for @historicalMatchRecorded.
  ///
  /// In en, this message translates to:
  /// **'Match recorded. Add who played from the Teams screen, then record the result.'**
  String get historicalMatchRecorded;

  /// No description provided for @errMatchHistorical.
  ///
  /// In en, this message translates to:
  /// **'This match was recorded after it was played, so nobody can register for it.'**
  String get errMatchHistorical;

  /// No description provided for @startingPlayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Starting players'**
  String get startingPlayersLabel;

  /// No description provided for @startingPlayersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a number between 4 and 30'**
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

  /// No description provided for @errInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a match name of at least 2 characters.'**
  String get errInvalidTitle;

  /// No description provided for @errInvalidLocation.
  ///
  /// In en, this message translates to:
  /// **'Enter a location of at least 2 characters.'**
  String get errInvalidLocation;

  /// No description provided for @errCommunityInactive.
  ///
  /// In en, this message translates to:
  /// **'This community is no longer active, so no new match can be created in it.'**
  String get errCommunityInactive;

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
  /// **'The match was cancelled.'**
  String get notifMatchDeleted;

  /// No description provided for @notifMatchCreated.
  ///
  /// In en, this message translates to:
  /// **'A new match has been created.'**
  String get notifMatchCreated;

  /// No description provided for @notifRegistrationOpened.
  ///
  /// In en, this message translates to:
  /// **'Registration is now open.'**
  String get notifRegistrationOpened;

  /// No description provided for @notifMatchFull.
  ///
  /// In en, this message translates to:
  /// **'The match is now full.'**
  String get notifMatchFull;

  /// No description provided for @notifTeamsRegenerated.
  ///
  /// In en, this message translates to:
  /// **'The teams were regenerated.'**
  String get notifTeamsRegenerated;

  /// No description provided for @notifMatchStartingSoon.
  ///
  /// In en, this message translates to:
  /// **'Your match starts in less than an hour.'**
  String get notifMatchStartingSoon;

  /// No description provided for @notifMatchTimeChanged.
  ///
  /// In en, this message translates to:
  /// **'The match time has changed.'**
  String get notifMatchTimeChanged;

  /// No description provided for @notifCommunityInvitation.
  ///
  /// In en, this message translates to:
  /// **'You have been invited to a community.'**
  String get notifCommunityInvitation;

  /// No description provided for @notifCommunityJoinAccepted.
  ///
  /// In en, this message translates to:
  /// **'Your request to join was accepted.'**
  String get notifCommunityJoinAccepted;

  /// No description provided for @notifCommunityPictureUpdated.
  ///
  /// In en, this message translates to:
  /// **'The community picture was updated.'**
  String get notifCommunityPictureUpdated;

  /// No description provided for @notifCommunityDescriptionUpdated.
  ///
  /// In en, this message translates to:
  /// **'The community description was updated.'**
  String get notifCommunityDescriptionUpdated;

  /// No description provided for @notifCommunitySettingsUpdated.
  ///
  /// In en, this message translates to:
  /// **'The community settings were updated.'**
  String get notifCommunitySettingsUpdated;

  /// No description provided for @pushSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushSettingsTitle;

  /// No description provided for @pushSettingsIntro.
  ///
  /// In en, this message translates to:
  /// **'Every notification is kept in the app. These switches only decide what your phone alerts you about.'**
  String get pushSettingsIntro;

  /// No description provided for @pushMatchLabel.
  ///
  /// In en, this message translates to:
  /// **'Match notifications'**
  String get pushMatchLabel;

  /// No description provided for @pushMatchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Registration, player changes and reminders.'**
  String get pushMatchSubtitle;

  /// No description provided for @pushCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Community notifications'**
  String get pushCommunityLabel;

  /// No description provided for @pushCommunitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Invitations and membership.'**
  String get pushCommunitySubtitle;

  /// No description provided for @pushMuteAllLabel.
  ///
  /// In en, this message translates to:
  /// **'Mute all push notifications'**
  String get pushMuteAllLabel;

  /// No description provided for @pushMuteAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent to your phone. Your notification history is unchanged.'**
  String get pushMuteAllSubtitle;

  /// No description provided for @pushSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That setting could not be saved. Try again.'**
  String get pushSaveFailed;

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
  /// **'Match title'**
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
  /// **'Registered players are notified. Deleting a completed match also takes back every statistic and rating its result produced.'**
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

  /// No description provided for @addPlayerButton.
  ///
  /// In en, this message translates to:
  /// **'Add player'**
  String get addPlayerButton;

  /// No description provided for @addPlayerEmpty.
  ///
  /// In en, this message translates to:
  /// **'Every community member is already in this match.'**
  String get addPlayerEmpty;

  /// No description provided for @addPlayerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Add player?'**
  String get addPlayerConfirmTitle;

  /// No description provided for @addPlayerConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Add {name} to this match?'**
  String addPlayerConfirmBody(String name);

  /// No description provided for @playerAddedConfirmed.
  ///
  /// In en, this message translates to:
  /// **'{name} was added to the starting players.'**
  String playerAddedConfirmed(String name);

  /// No description provided for @playerAddedReserve.
  ///
  /// In en, this message translates to:
  /// **'{name} was added to the reserve list.'**
  String playerAddedReserve(String name);

  /// No description provided for @addSelectedPlayersButton.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add 1 player} other{Add {count} players}}'**
  String addSelectedPlayersButton(int count);

  /// No description provided for @playersAddedSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 player was added.} other{{count} players were added.}}'**
  String playersAddedSummary(int count);

  /// No description provided for @playersAddedPartial.
  ///
  /// In en, this message translates to:
  /// **'{added} added, {failed} could not be.'**
  String playersAddedPartial(int added, int failed);

  /// No description provided for @playersAddedNone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{That player could not be added.} other{None of the {count} players could be added.}}'**
  String playersAddedNone(int count);

  /// No description provided for @addPlayerFailed.
  ///
  /// In en, this message translates to:
  /// **'That player could not be added. Try again.'**
  String get addPlayerFailed;

  /// No description provided for @errPlayerAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'That player is already in this match.'**
  String get errPlayerAlreadyRegistered;

  /// No description provided for @errPlayerOverlappingMatch.
  ///
  /// In en, this message translates to:
  /// **'That player is registered in another match at the same time.'**
  String get errPlayerOverlappingMatch;

  /// No description provided for @errPlayerNotCommunityMember.
  ///
  /// In en, this message translates to:
  /// **'That player is not a member of this community.'**
  String get errPlayerNotCommunityMember;

  /// How a Professional Guest is named in a roster or a lineup. Arabic renders this as محترف (الاسم).
  ///
  /// In en, this message translates to:
  /// **'Professional ({name})'**
  String professionalGuestName(String name);

  /// No description provided for @professionalGuestLabel.
  ///
  /// In en, this message translates to:
  /// **'Professional guest'**
  String get professionalGuestLabel;

  /// No description provided for @addGuestButton.
  ///
  /// In en, this message translates to:
  /// **'Add professional guest'**
  String get addGuestButton;

  /// No description provided for @addGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a professional guest'**
  String get addGuestTitle;

  /// No description provided for @renameGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename professional guest'**
  String get renameGuestTitle;

  /// No description provided for @guestNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get guestNameLabel;

  /// No description provided for @guestNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a name between 2 and 60 characters.'**
  String get guestNameInvalid;

  /// No description provided for @guestAddedConfirmed.
  ///
  /// In en, this message translates to:
  /// **'{name} was added to the starting players.'**
  String guestAddedConfirmed(String name);

  /// No description provided for @guestAddedReserve.
  ///
  /// In en, this message translates to:
  /// **'{name} was added to the reserve list.'**
  String guestAddedReserve(String name);

  /// No description provided for @removeGuestButton.
  ///
  /// In en, this message translates to:
  /// **'Remove guest'**
  String get removeGuestButton;

  /// No description provided for @renameGuestButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameGuestButton;

  /// No description provided for @removeGuestConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this professional guest?'**
  String get removeGuestConfirmTitle;

  /// No description provided for @removeGuestConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} loses their place in this match. Anything they did in a match that was already played is kept.'**
  String removeGuestConfirmBody(String name);

  /// No description provided for @removePlayedGuestConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be taken out of the record of who played this match. If they scored, correct the result first.'**
  String removePlayedGuestConfirmBody(String name);

  /// No description provided for @guestActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be done. Try again.'**
  String get guestActionFailed;

  /// No description provided for @errInvalidGuestName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name between 2 and 60 characters.'**
  String get errInvalidGuestName;

  /// No description provided for @errGuestNotFound.
  ///
  /// In en, this message translates to:
  /// **'That guest is no longer in this match.'**
  String get errGuestNotFound;

  /// No description provided for @arrangeRosterTitle.
  ///
  /// In en, this message translates to:
  /// **'Arrange participants'**
  String get arrangeRosterTitle;

  /// No description provided for @arrangeRosterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder the starting and reserve lists, or swap a participant between them.'**
  String get arrangeRosterSubtitle;

  /// No description provided for @arrangeRosterHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the handle to reorder a list. Tap a participant, then tap another to swap their places.'**
  String get arrangeRosterHint;

  /// No description provided for @arrangeStartingSection.
  ///
  /// In en, this message translates to:
  /// **'Starting ({count}/{capacity})'**
  String arrangeStartingSection(int count, int capacity);

  /// No description provided for @arrangeReserveSection.
  ///
  /// In en, this message translates to:
  /// **'Reserve ({count})'**
  String arrangeReserveSection(int count);

  /// No description provided for @arrangeModeManual.
  ///
  /// In en, this message translates to:
  /// **'Arranged by an organizer'**
  String get arrangeModeManual;

  /// No description provided for @arrangeModeManualHelp.
  ///
  /// In en, this message translates to:
  /// **'This match follows the order you set. Registration order no longer decides who starts.'**
  String get arrangeModeManualHelp;

  /// No description provided for @arrangeModeRegistration.
  ///
  /// In en, this message translates to:
  /// **'Registration order'**
  String get arrangeModeRegistration;

  /// No description provided for @arrangeModeRegistrationHelp.
  ///
  /// In en, this message translates to:
  /// **'Players start in the order they joined, with professional guests after them. Your first change makes your own order the one that counts.'**
  String get arrangeModeRegistrationHelp;

  /// No description provided for @arrangeSelectedHint.
  ///
  /// In en, this message translates to:
  /// **'{name} selected. Tap another participant to swap their places.'**
  String arrangeSelectedHint(String name);

  /// No description provided for @arrangeClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get arrangeClearSelection;

  /// No description provided for @arrangeReorderHandle.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get arrangeReorderHandle;

  /// No description provided for @arrangeSwapAction.
  ///
  /// In en, this message translates to:
  /// **'Swap with the selected participant'**
  String get arrangeSwapAction;

  /// No description provided for @arrangeSelectAction.
  ///
  /// In en, this message translates to:
  /// **'Select for a swap'**
  String get arrangeSelectAction;

  /// No description provided for @arrangeSaved.
  ///
  /// In en, this message translates to:
  /// **'Order updated.'**
  String get arrangeSaved;

  /// No description provided for @arrangeStartingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No starting participants yet.'**
  String get arrangeStartingEmpty;

  /// No description provided for @arrangeReserveEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody is on the reserve list.'**
  String get arrangeReserveEmpty;

  /// No description provided for @arrangeCompletedNote.
  ///
  /// In en, this message translates to:
  /// **'This match has been played. The order is saved, and the starting list is kept as the record of who played.'**
  String get arrangeCompletedNote;

  /// No description provided for @errRosterChanged.
  ///
  /// In en, this message translates to:
  /// **'The roster changed while you were arranging it. It has been reloaded — try again.'**
  String get errRosterChanged;

  /// No description provided for @errInvalidSwap.
  ///
  /// In en, this message translates to:
  /// **'Those two participants cannot be swapped.'**
  String get errInvalidSwap;

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

  /// No description provided for @myInvitationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no invitations.'**
  String get myInvitationsEmpty;

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

  /// No description provided for @errInvalidRole.
  ///
  /// In en, this message translates to:
  /// **'That role cannot be assigned.'**
  String get errInvalidRole;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get inviteTitle;

  /// No description provided for @inviteLoadError.
  ///
  /// In en, this message translates to:
  /// **'We could not open this invitation. Check your connection and try again.'**
  String get inviteLoadError;

  /// No description provided for @inviteNotFound.
  ///
  /// In en, this message translates to:
  /// **'We could not find this invitation. The link may be incomplete.'**
  String get inviteNotFound;

  /// No description provided for @inviteJoinCommunity.
  ///
  /// In en, this message translates to:
  /// **'Join Community'**
  String get inviteJoinCommunity;

  /// No description provided for @inviteSignInFirst.
  ///
  /// In en, this message translates to:
  /// **'Sign in or create an account to join.'**
  String get inviteSignInFirst;

  /// No description provided for @inviteAlreadyMemberNote.
  ///
  /// In en, this message translates to:
  /// **'You are already a member of this community.'**
  String get inviteAlreadyMemberNote;

  /// No description provided for @shareInvitation.
  ///
  /// In en, this message translates to:
  /// **'Share invitation'**
  String get shareInvitation;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invitation copied. Paste it wherever you share it.'**
  String get inviteLinkCopied;

  /// No description provided for @inviteShareCommunityBody.
  ///
  /// In en, this message translates to:
  /// **'Join {community} on Go Play:\n{link}'**
  String inviteShareCommunityBody(String community, String link);

  /// No description provided for @errNotCommunityMember.
  ///
  /// In en, this message translates to:
  /// **'You are not a member of this community.'**
  String get errNotCommunityMember;

  /// No description provided for @copyLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyLinkButton;

  /// No description provided for @matchCapacityLabel.
  ///
  /// In en, this message translates to:
  /// **'👥 {count} players'**
  String matchCapacityLabel(int count);

  /// No description provided for @matchTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Match title is required'**
  String get matchTitleRequired;

  /// No description provided for @communityInvitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get communityInvitationTitle;

  /// No description provided for @communityInvitationHelp.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this link or code can join the community. Both carry the same code.'**
  String get communityInvitationHelp;

  /// No description provided for @inviteLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Invitation link'**
  String get inviteLinkLabel;

  /// No description provided for @copyJoinCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyJoinCodeButton;

  /// No description provided for @inviteOpenCommunity.
  ///
  /// In en, this message translates to:
  /// **'Open community'**
  String get inviteOpenCommunity;

  /// No description provided for @inviteOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open an invitation'**
  String get inviteOpenAction;

  /// No description provided for @invitePasteHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the invitation link or code'**
  String get invitePasteHint;

  /// No description provided for @inviteInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'That is not an invitation link or code.'**
  String get inviteInvalidInput;

  /// No description provided for @regenerateJoinCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Regenerate code'**
  String get regenerateJoinCodeButton;

  /// No description provided for @regenerateJoinCodeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Regenerate the join code?'**
  String get regenerateJoinCodeConfirmTitle;

  /// No description provided for @regenerateJoinCodeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The current link and code stop working immediately, so anyone still holding them cannot join. People already in the community stay members.'**
  String get regenerateJoinCodeConfirmBody;

  /// No description provided for @joinCodeRegenerated.
  ///
  /// In en, this message translates to:
  /// **'New code issued. The old one no longer works.'**
  String get joinCodeRegenerated;

  /// No description provided for @joinPolicyLabel.
  ///
  /// In en, this message translates to:
  /// **'Joining'**
  String get joinPolicyLabel;

  /// No description provided for @joinPolicyOpen.
  ///
  /// In en, this message translates to:
  /// **'Open join'**
  String get joinPolicyOpen;

  /// No description provided for @joinPolicyOpenHelp.
  ///
  /// In en, this message translates to:
  /// **'Anyone can join from the community list.'**
  String get joinPolicyOpenHelp;

  /// No description provided for @joinPolicyCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Join by code'**
  String get joinPolicyCodeRequired;

  /// No description provided for @joinPolicyCodeRequiredHelp.
  ///
  /// In en, this message translates to:
  /// **'People need the join code, or an invitation link that carries it.'**
  String get joinPolicyCodeRequiredHelp;

  /// No description provided for @joinPolicySaved.
  ///
  /// In en, this message translates to:
  /// **'Join setting updated.'**
  String get joinPolicySaved;

  /// No description provided for @joinCodeRequiredPrompt.
  ///
  /// In en, this message translates to:
  /// **'This community needs its join code.'**
  String get joinCodeRequiredPrompt;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get adminTitle;

  /// No description provided for @adminUsersTab.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsersTab;

  /// No description provided for @adminCommunitiesTab.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get adminCommunitiesTab;

  /// No description provided for @adminMatchesTab.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get adminMatchesTab;

  /// No description provided for @adminSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get adminSearchLabel;

  /// No description provided for @adminEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing found.'**
  String get adminEmpty;

  /// No description provided for @adminDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get adminDeleteButton;

  /// No description provided for @adminDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted.'**
  String get adminDeleted;

  /// No description provided for @adminDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String adminDeleteConfirmTitle(String name);

  /// No description provided for @adminDeleteUserConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The account and everything belonging to it are removed: communities they own, matches they created, memberships and registrations. This cannot be undone.'**
  String get adminDeleteUserConfirmBody;

  /// No description provided for @adminDeleteCommunityConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The community and everything under it are removed: matches, memberships and registrations. This cannot be undone.'**
  String get adminDeleteCommunityConfirmBody;

  /// No description provided for @adminDeleteMatchConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The match and its registrations are removed, and registered players are notified. This cannot be undone.'**
  String get adminDeleteMatchConfirmBody;

  /// Admin list badge for an account or community that is not suspended
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminStatusActive;

  /// Admin list badge for a suspended account or community
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get adminStatusSuspended;

  /// Admin list badge for a protected System Admin account
  ///
  /// In en, this message translates to:
  /// **'System Admin'**
  String get adminStatusSystemAdmin;

  /// No description provided for @adminSuspendButton.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get adminSuspendButton;

  /// No description provided for @adminReactivateButton.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get adminReactivateButton;

  /// No description provided for @adminSuspendUserConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}?'**
  String adminSuspendUserConfirmTitle(String name);

  /// No description provided for @adminSuspendUserConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They keep their account and their football history, and stop being able to use Go Play until they are reactivated.'**
  String get adminSuspendUserConfirmBody;

  /// No description provided for @adminSuspendCommunityConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}?'**
  String adminSuspendCommunityConfirmTitle(String name);

  /// No description provided for @adminSuspendCommunityConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It disappears from discovery and admits nobody new. Its matches, results and history are kept.'**
  String get adminSuspendCommunityConfirmBody;

  /// No description provided for @adminReactivateUserConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {name}?'**
  String adminReactivateUserConfirmTitle(String name);

  /// No description provided for @adminReactivateUserConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They can use Go Play again straight away.'**
  String get adminReactivateUserConfirmBody;

  /// No description provided for @adminReactivateCommunityConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {name}?'**
  String adminReactivateCommunityConfirmTitle(String name);

  /// No description provided for @adminReactivateCommunityConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It becomes discoverable and usable again straight away.'**
  String get adminReactivateCommunityConfirmBody;

  /// No description provided for @adminSuspensionReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get adminSuspensionReasonLabel;

  /// No description provided for @adminSuspensionReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Please give a reason.'**
  String get adminSuspensionReasonRequired;

  /// No description provided for @adminSuspendedFeedback.
  ///
  /// In en, this message translates to:
  /// **'Suspended.'**
  String get adminSuspendedFeedback;

  /// No description provided for @adminReactivatedFeedback.
  ///
  /// In en, this message translates to:
  /// **'Reactivated.'**
  String get adminReactivatedFeedback;

  /// No description provided for @accountSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account suspended'**
  String get accountSuspendedTitle;

  /// No description provided for @accountSuspendedBody.
  ///
  /// In en, this message translates to:
  /// **'This account has been suspended, so Go Play is unavailable for now. Your profile, matches and football history are kept.'**
  String get accountSuspendedBody;

  /// No description provided for @accountSuspendedSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSuspendedSignOut;

  /// No description provided for @accountStatusRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get accountStatusRetry;

  /// No description provided for @accountStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'We could not check your account right now.'**
  String get accountStatusUnavailable;

  /// No description provided for @teamsTitle.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get teamsTitle;

  /// No description provided for @teamsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Teams have not been generated for this match yet.'**
  String get teamsEmpty;

  /// No description provided for @generateTeamsButton.
  ///
  /// In en, this message translates to:
  /// **'Generate teams'**
  String get generateTeamsButton;

  /// No description provided for @regenerateTeamsButton.
  ///
  /// In en, this message translates to:
  /// **'Regenerate teams'**
  String get regenerateTeamsButton;

  /// No description provided for @regenerateTeamsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate the teams again?'**
  String get regenerateTeamsConfirmTitle;

  /// No description provided for @regenerateTeamsConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The current teams are replaced by a new split of the confirmed players.'**
  String get regenerateTeamsConfirmBody;

  /// No description provided for @teamsGenerated.
  ///
  /// In en, this message translates to:
  /// **'Teams generated.'**
  String get teamsGenerated;

  /// No description provided for @teamAName.
  ///
  /// In en, this message translates to:
  /// **'Team A'**
  String get teamAName;

  /// No description provided for @teamBName.
  ///
  /// In en, this message translates to:
  /// **'Team B'**
  String get teamBName;

  /// No description provided for @teamsOutOfPosition.
  ///
  /// In en, this message translates to:
  /// **'Out of position'**
  String get teamsOutOfPosition;

  /// No description provided for @teamsPlayerRangeNote.
  ///
  /// In en, this message translates to:
  /// **'Generating teams needs between {min} and {max} confirmed players. This match has {count}.'**
  String teamsPlayerRangeNote(int min, int max, int count);

  /// No description provided for @errMissingPlayerInputs.
  ///
  /// In en, this message translates to:
  /// **'Some confirmed players have an incomplete profile. Each of them needs a date of birth before teams can be generated.'**
  String get errMissingPlayerInputs;

  /// No description provided for @errTeamsNotGenerated.
  ///
  /// In en, this message translates to:
  /// **'Teams could not be generated from this roster.'**
  String get errTeamsNotGenerated;

  /// No description provided for @editPlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {player}'**
  String editPlayerTitle(String player);

  /// No description provided for @movePlayerAction.
  ///
  /// In en, this message translates to:
  /// **'Move to the other team'**
  String get movePlayerAction;

  /// No description provided for @swapPlayerAction.
  ///
  /// In en, this message translates to:
  /// **'Swap with a player'**
  String get swapPlayerAction;

  /// No description provided for @swapPositionsAction.
  ///
  /// In en, this message translates to:
  /// **'Swap positions'**
  String get swapPositionsAction;

  /// No description provided for @changePositionAction.
  ///
  /// In en, this message translates to:
  /// **'Change position'**
  String get changePositionAction;

  /// No description provided for @swapPlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Swap with'**
  String get swapPlayerTitle;

  /// No description provided for @swapPositionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Swap positions with'**
  String get swapPositionsTitle;

  /// No description provided for @swapNobodyAvailable.
  ///
  /// In en, this message translates to:
  /// **'The other team has nobody to swap with.'**
  String get swapNobodyAvailable;

  /// No description provided for @changePositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Assigned position'**
  String get changePositionTitle;

  /// No description provided for @lineupUpdated.
  ///
  /// In en, this message translates to:
  /// **'Lineup updated.'**
  String get lineupUpdated;

  /// No description provided for @errLineupRefused.
  ///
  /// In en, this message translates to:
  /// **'That change was refused. A team cannot have two goalkeepers.'**
  String get errLineupRefused;

  /// No description provided for @errLineupNotChanged.
  ///
  /// In en, this message translates to:
  /// **'That change no longer applies to this lineup. It has been reloaded.'**
  String get errLineupNotChanged;

  /// No description provided for @matchResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Match result'**
  String get matchResultTitle;

  /// No description provided for @saveResultButton.
  ///
  /// In en, this message translates to:
  /// **'Save result'**
  String get saveResultButton;

  /// No description provided for @resultParticipationConfirmation.
  ///
  /// In en, this message translates to:
  /// **'I confirm that this lineup represents the players who actually participated in this match.'**
  String get resultParticipationConfirmation;

  /// No description provided for @resultParticipationConfirmationHint.
  ///
  /// In en, this message translates to:
  /// **'Required before saving the result.'**
  String get resultParticipationConfirmationHint;

  /// No description provided for @resultSaved.
  ///
  /// In en, this message translates to:
  /// **'Match result saved successfully'**
  String get resultSaved;

  /// No description provided for @resultOrganizersOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the community owner and admins can record a match result.'**
  String get resultOrganizersOnly;

  /// No description provided for @mvpLabel.
  ///
  /// In en, this message translates to:
  /// **'MVP'**
  String get mvpLabel;

  /// No description provided for @addGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a goal'**
  String get addGoalLabel;

  /// No description provided for @removeGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove a goal'**
  String get removeGoalLabel;

  /// No description provided for @goalsScoredLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No goals} =1{1 goal} other{{count} goals}}'**
  String goalsScoredLabel(int count);

  /// No description provided for @goalsRecordedNote.
  ///
  /// In en, this message translates to:
  /// **'{recorded} of {total} goals assigned to a scorer.'**
  String goalsRecordedNote(int recorded, int total);

  /// No description provided for @editResultConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the recorded result?'**
  String get editResultConfirmTitle;

  /// No description provided for @editResultConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The ratings and statistics the previous result produced are reversed, and the new result is applied instead.'**
  String get editResultConfirmBody;

  /// No description provided for @errGoalsDoNotMatchScore.
  ///
  /// In en, this message translates to:
  /// **'The goals assigned to scorers must add up to the final score.'**
  String get errGoalsDoNotMatchScore;

  /// No description provided for @errMvpNotParticipant.
  ///
  /// In en, this message translates to:
  /// **'The best player must be one of the players in this match.'**
  String get errMvpNotParticipant;

  /// No description provided for @errScorerNotParticipant.
  ///
  /// In en, this message translates to:
  /// **'A goal can only be credited to a player in this match.'**
  String get errScorerNotParticipant;

  /// No description provided for @errResultNeedsLineup.
  ///
  /// In en, this message translates to:
  /// **'Teams have not been generated for this match yet. The result needs to know which side each player was on.'**
  String get errResultNeedsLineup;

  /// No description provided for @errInvalidResultNumbers.
  ///
  /// In en, this message translates to:
  /// **'The result could not be saved. Check the scores and the goals.'**
  String get errInvalidResultNumbers;

  /// No description provided for @dashboardTab.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTab;

  /// No description provided for @statisticsTab.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTab;

  /// No description provided for @communityStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Community statistics'**
  String get communityStatisticsTitle;

  /// No description provided for @statTotalMatches.
  ///
  /// In en, this message translates to:
  /// **'Total matches'**
  String get statTotalMatches;

  /// No description provided for @statTotalPlayers.
  ///
  /// In en, this message translates to:
  /// **'Total players'**
  String get statTotalPlayers;

  /// No description provided for @statTotalGoals.
  ///
  /// In en, this message translates to:
  /// **'Total goals'**
  String get statTotalGoals;

  /// No description provided for @statLeadersTitle.
  ///
  /// In en, this message translates to:
  /// **'Leaders'**
  String get statLeadersTitle;

  /// No description provided for @statTopScorer.
  ///
  /// In en, this message translates to:
  /// **'Top scorer'**
  String get statTopScorer;

  /// No description provided for @statMostActivePlayer.
  ///
  /// In en, this message translates to:
  /// **'Most active player'**
  String get statMostActivePlayer;

  /// No description provided for @statMostMvp.
  ///
  /// In en, this message translates to:
  /// **'Most valuable player'**
  String get statMostMvp;

  /// No description provided for @statNoneYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get statNoneYet;

  /// No description provided for @statFormerPlayer.
  ///
  /// In en, this message translates to:
  /// **'Former player'**
  String get statFormerPlayer;

  /// No description provided for @statMatchesPlayedValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matches} =1{1 match} other{{count} matches}}'**
  String statMatchesPlayedValue(int count);

  /// No description provided for @statMvpValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Never} =1{1 time} other{{count} times}}'**
  String statMvpValue(int count);

  /// No description provided for @statScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Every figure here counts completed matches only — a match still open or full contributes nothing. Player figures count matches whose result has been recorded.'**
  String get statScopeNote;

  /// No description provided for @statEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No results have been recorded in this community yet. Statistics appear once a match result is saved.'**
  String get statEmptyBody;

  /// No description provided for @playerStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'My statistics'**
  String get playerStatisticsTitle;

  /// No description provided for @statCurrentRating.
  ///
  /// In en, this message translates to:
  /// **'Current rating'**
  String get statCurrentRating;

  /// No description provided for @statWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win rate'**
  String get statWinRate;

  /// No description provided for @statGoalsPerMatch.
  ///
  /// In en, this message translates to:
  /// **'Goals per match'**
  String get statGoalsPerMatch;

  /// No description provided for @statRatingTrend.
  ///
  /// In en, this message translates to:
  /// **'Recent rating change'**
  String get statRatingTrend;

  /// No description provided for @statMatchesPlayed.
  ///
  /// In en, this message translates to:
  /// **'Matches played'**
  String get statMatchesPlayed;

  /// No description provided for @statWins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get statWins;

  /// No description provided for @statDraws.
  ///
  /// In en, this message translates to:
  /// **'Draws'**
  String get statDraws;

  /// No description provided for @statLosses.
  ///
  /// In en, this message translates to:
  /// **'Losses'**
  String get statLosses;

  /// No description provided for @statGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get statGoals;

  /// No description provided for @statMvpCount.
  ///
  /// In en, this message translates to:
  /// **'Best player awards'**
  String get statMvpCount;

  /// No description provided for @statCareerNote.
  ///
  /// In en, this message translates to:
  /// **'Your record across every community you play in. These figures are set by the app when a match result is recorded, and count matches whose result has been saved.'**
  String get statCareerNote;

  /// No description provided for @statNoMatchesYet.
  ///
  /// In en, this message translates to:
  /// **'You have not played a recorded match yet. Your figures start at zero and the rating is the starting rating every player is given.'**
  String get statNoMatchesYet;

  /// No description provided for @leaderboardsTab.
  ///
  /// In en, this message translates to:
  /// **'Leaderboards'**
  String get leaderboardsTab;

  /// No description provided for @leaderboardHighestRated.
  ///
  /// In en, this message translates to:
  /// **'Highest rated'**
  String get leaderboardHighestRated;

  /// No description provided for @leaderboardTopScorer.
  ///
  /// In en, this message translates to:
  /// **'Top scorer'**
  String get leaderboardTopScorer;

  /// No description provided for @leaderboardMostMvp.
  ///
  /// In en, this message translates to:
  /// **'Most valuable player'**
  String get leaderboardMostMvp;

  /// No description provided for @leaderboardMostActive.
  ///
  /// In en, this message translates to:
  /// **'Most active'**
  String get leaderboardMostActive;

  /// No description provided for @leaderboardMostWins.
  ///
  /// In en, this message translates to:
  /// **'Most wins'**
  String get leaderboardMostWins;

  /// No description provided for @leaderboardWinsValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No wins} =1{1 win} other{{count} wins}}'**
  String leaderboardWinsValue(num count);

  /// No description provided for @leaderboardsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No leaderboards yet. Once a match result is recorded, this is where the community sees who is leading.'**
  String get leaderboardsEmpty;

  /// No description provided for @leaderboardRatingNote.
  ///
  /// In en, this message translates to:
  /// **'Rating boards rank the player\'s rating in this community for the selected period, from a 5.00 start.'**
  String get leaderboardRatingNote;

  /// No description provided for @shareCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Share card'**
  String get shareCardTitle;

  /// No description provided for @shareCardShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareCardShareAction;

  /// No description provided for @shareCardCloseAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get shareCardCloseAction;

  /// No description provided for @shareCardPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing your card…'**
  String get shareCardPreparing;

  /// No description provided for @errShareCardRender.
  ///
  /// In en, this message translates to:
  /// **'The card could not be created. Please try again.'**
  String get errShareCardRender;

  /// No description provided for @errShareCardShare.
  ///
  /// In en, this message translates to:
  /// **'Sharing is not available right now.'**
  String get errShareCardShare;

  /// No description provided for @shareCardStatMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get shareCardStatMatches;

  /// No description provided for @shareCardPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get shareCardPositionLabel;

  /// No description provided for @shareCardStatWins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get shareCardStatWins;

  /// No description provided for @shareCardPeriodAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get shareCardPeriodAllTime;

  /// No description provided for @shareCardStatDraws.
  ///
  /// In en, this message translates to:
  /// **'Draws'**
  String get shareCardStatDraws;

  /// No description provided for @shareCardStatLosses.
  ///
  /// In en, this message translates to:
  /// **'Losses'**
  String get shareCardStatLosses;

  /// No description provided for @shareCardPeriodBadge.
  ///
  /// In en, this message translates to:
  /// **'Period · {period}'**
  String shareCardPeriodBadge(String period);

  /// No description provided for @shareLeaderboardsAction.
  ///
  /// In en, this message translates to:
  /// **'Share leaderboards'**
  String get shareLeaderboardsAction;

  /// No description provided for @showPreviousResults.
  ///
  /// In en, this message translates to:
  /// **'Show previous results ({count})'**
  String showPreviousResults(int count);

  /// No description provided for @hidePreviousResults.
  ///
  /// In en, this message translates to:
  /// **'Hide previous results'**
  String get hidePreviousResults;

  /// No description provided for @viewAllResults.
  ///
  /// In en, this message translates to:
  /// **'View all results'**
  String get viewAllResults;

  /// No description provided for @showFewerResults.
  ///
  /// In en, this message translates to:
  /// **'Show fewer'**
  String get showFewerResults;

  /// No description provided for @shareCardStatGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get shareCardStatGoals;

  /// No description provided for @shareCardStatMvp.
  ///
  /// In en, this message translates to:
  /// **'MVP'**
  String get shareCardStatMvp;

  /// No description provided for @shareMyStatisticsAction.
  ///
  /// In en, this message translates to:
  /// **'Share my statistics'**
  String get shareMyStatisticsAction;

  /// No description provided for @shareCardStatPlayers.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get shareCardStatPlayers;

  /// No description provided for @shareCommunityStatisticsAction.
  ///
  /// In en, this message translates to:
  /// **'Share community statistics'**
  String get shareCommunityStatisticsAction;

  /// No description provided for @shareTeamLineupAction.
  ///
  /// In en, this message translates to:
  /// **'Share the lineup'**
  String get shareTeamLineupAction;

  /// No description provided for @shareMatchResultAction.
  ///
  /// In en, this message translates to:
  /// **'Share the result'**
  String get shareMatchResultAction;

  /// No description provided for @shareCardDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Image saved to your downloads.'**
  String get shareCardDownloaded;

  /// No description provided for @sharePlayerProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Share profile'**
  String get sharePlayerProfileAction;

  /// No description provided for @shareMyProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Share my profile'**
  String get shareMyProfileAction;

  /// No description provided for @shareTextMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My player profile on Go Play.'**
  String get shareTextMyProfile;

  /// No description provided for @shareTextPlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'{name} — player profile on Go Play.'**
  String shareTextPlayerProfile(String name);

  /// No description provided for @shareTextMyStatistics.
  ///
  /// In en, this message translates to:
  /// **'My statistics on Go Play.'**
  String get shareTextMyStatistics;

  /// No description provided for @shareTextCommunityStatistics.
  ///
  /// In en, this message translates to:
  /// **'{community} — statistics on Go Play.'**
  String shareTextCommunityStatistics(String community);

  /// No description provided for @shareTextTeamOfPeriod.
  ///
  /// In en, this message translates to:
  /// **'{community} — Team of the Period on Go Play.'**
  String shareTextTeamOfPeriod(String community);

  /// No description provided for @shareTextMatchLineup.
  ///
  /// In en, this message translates to:
  /// **'{match} — the lineup on Go Play.'**
  String shareTextMatchLineup(String match);

  /// No description provided for @shareTextMatchResult.
  ///
  /// In en, this message translates to:
  /// **'{match} — the result on Go Play.'**
  String shareTextMatchResult(String match);

  /// No description provided for @recentFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent form'**
  String get recentFormTitle;

  /// No description provided for @recentFormNote.
  ///
  /// In en, this message translates to:
  /// **'The player\'s last {count} completed matches, most recent first.'**
  String recentFormNote(int count);

  /// No description provided for @recentFormEmpty.
  ///
  /// In en, this message translates to:
  /// **'No completed matches yet. Once a result is saved, the last five appear here.'**
  String get recentFormEmpty;

  /// No description provided for @recentFormWin.
  ///
  /// In en, this message translates to:
  /// **'Win'**
  String get recentFormWin;

  /// No description provided for @recentFormDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get recentFormDraw;

  /// No description provided for @recentFormLoss.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get recentFormLoss;

  /// No description provided for @recentFormWinShort.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get recentFormWinShort;

  /// No description provided for @recentFormDrawShort.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get recentFormDrawShort;

  /// No description provided for @recentFormLossShort.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get recentFormLossShort;

  /// No description provided for @recentFormViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get recentFormViewAll;

  /// No description provided for @viewAsPublicAction.
  ///
  /// In en, this message translates to:
  /// **'View as public'**
  String get viewAsPublicAction;

  /// No description provided for @publicProfileGuestPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to join communities, play matches and build a record of your own.'**
  String get publicProfileGuestPrompt;

  /// No description provided for @publicMatchLineupTitle.
  ///
  /// In en, this message translates to:
  /// **'Line-up'**
  String get publicMatchLineupTitle;

  /// No description provided for @publicMatchGuestPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to join a community and play in matches like this one.'**
  String get publicMatchGuestPrompt;

  /// No description provided for @recentHighlightTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent highlight'**
  String get recentHighlightTitle;

  /// No description provided for @recentAchievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent achievements'**
  String get recentAchievementsTitle;

  /// The ISO week a Team of the Week award covers, from the stored period key.
  ///
  /// In en, this message translates to:
  /// **'Week {week}'**
  String highlightWeekNumber(int week);

  /// No description provided for @highlightMvpTitle.
  ///
  /// In en, this message translates to:
  /// **'Player of the match'**
  String get highlightMvpTitle;

  /// No description provided for @highlightTeamOfPeriodTitle.
  ///
  /// In en, this message translates to:
  /// **'Team of the period'**
  String get highlightTeamOfPeriodTitle;

  /// No description provided for @highlightInCommunity.
  ///
  /// In en, this message translates to:
  /// **'In {community}'**
  String highlightInCommunity(String community);

  /// No description provided for @shareCardFormLabel.
  ///
  /// In en, this message translates to:
  /// **'Recent form'**
  String get shareCardFormLabel;

  /// No description provided for @publicContentUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get publicContentUnavailableTitle;

  /// No description provided for @publicContentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This link is no longer available, or it points to something that needs an account.'**
  String get publicContentUnavailable;

  /// No description provided for @matchResultScorersLabel.
  ///
  /// In en, this message translates to:
  /// **'Scorers'**
  String get matchResultScorersLabel;

  /// No description provided for @matchResultDrawLabel.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get matchResultDrawLabel;

  /// No description provided for @matchResultWinnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get matchResultWinnerLabel;

  /// No description provided for @matchResultNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'No result has been recorded for this match yet.'**
  String get matchResultNotRecorded;

  /// No description provided for @statPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get statPeriodLabel;

  /// No description provided for @statPeriodWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get statPeriodWeekly;

  /// No description provided for @statPeriodMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get statPeriodMonthly;

  /// No description provided for @statPeriodAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get statPeriodAllTime;

  /// No description provided for @statPeriodWeeklyNote.
  ///
  /// In en, this message translates to:
  /// **'This week\'s figures. Weeks run Monday to Sunday, Oman time.'**
  String get statPeriodWeeklyNote;

  /// No description provided for @statPeriodMonthlyNote.
  ///
  /// In en, this message translates to:
  /// **'This calendar month\'s figures, Oman time.'**
  String get statPeriodMonthlyNote;

  /// No description provided for @statPeriodRatingNote.
  ///
  /// In en, this message translates to:
  /// **'The rating and recent rating change are global across every community. They are not figures for this period.'**
  String get statPeriodRatingNote;

  /// No description provided for @statPeriodNoMatches.
  ///
  /// In en, this message translates to:
  /// **'You have not played a recorded match in this period.'**
  String get statPeriodNoMatches;

  /// No description provided for @statPeriodEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No results have been recorded in this community in this period.'**
  String get statPeriodEmptyBody;

  /// No description provided for @leaderboardsPeriodEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results have been recorded in this period, so there is nothing to rank yet.'**
  String get leaderboardsPeriodEmpty;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @changeAction.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAction;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileTitle;

  /// No description provided for @editProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileAction;

  /// No description provided for @profilePersonalSection.
  ///
  /// In en, this message translates to:
  /// **'Personal information'**
  String get profilePersonalSection;

  /// No description provided for @profileAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccountSection;

  /// No description provided for @profilePlayingSection.
  ///
  /// In en, this message translates to:
  /// **'Playing profile'**
  String get profilePlayingSection;

  /// No description provided for @passwordHiddenNote.
  ///
  /// In en, this message translates to:
  /// **'Hidden for your security'**
  String get passwordHiddenNote;

  /// No description provided for @changeEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmailTitle;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed.'**
  String get passwordChanged;

  /// No description provided for @emailChangeRequested.
  ///
  /// In en, this message translates to:
  /// **'Check your new address for the confirmation link.'**
  String get emailChangeRequested;

  /// No description provided for @avatarChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get avatarChangeAction;

  /// No description provided for @avatarSourceCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get avatarSourceCamera;

  /// No description provided for @avatarSourceGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get avatarSourceGallery;

  /// No description provided for @ageLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// No description provided for @avatarRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get avatarRemoveAction;

  /// No description provided for @communityLogoChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Change community photo'**
  String get communityLogoChangeAction;

  /// No description provided for @communityLogoRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove community photo'**
  String get communityLogoRemoveAction;

  /// No description provided for @communityLogoFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the community photo. Please try again.'**
  String get communityLogoFailed;

  /// No description provided for @avatarUpdated.
  ///
  /// In en, this message translates to:
  /// **'Photo updated.'**
  String get avatarUpdated;

  /// No description provided for @avatarRemoved.
  ///
  /// In en, this message translates to:
  /// **'Photo removed.'**
  String get avatarRemoved;

  /// No description provided for @avatarUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the photo. Please try again.'**
  String get avatarUploadFailed;

  /// No description provided for @ageYears.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 year old} other{{count} years old}}'**
  String ageYears(int count);

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to use Go Play.'**
  String get logoutConfirmBody;

  /// No description provided for @completedMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed matches'**
  String get completedMatchesTitle;

  /// No description provided for @addPlayedPlayerAction.
  ///
  /// In en, this message translates to:
  /// **'Add a player who played'**
  String get addPlayedPlayerAction;

  /// No description provided for @addPlayedPlayerNobodyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Every community member is already in this lineup.'**
  String get addPlayedPlayerNobodyAvailable;

  /// No description provided for @removePlayedPlayerAction.
  ///
  /// In en, this message translates to:
  /// **'Remove from the match'**
  String get removePlayedPlayerAction;

  /// No description provided for @removePlayedPlayerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this player?'**
  String get removePlayedPlayerConfirmTitle;

  /// No description provided for @removePlayedPlayerConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be taken out of the lineup, and every statistic and rating this match gave them will be taken back.'**
  String removePlayedPlayerConfirmBody(String name);

  /// No description provided for @editPlayedMatchNote.
  ///
  /// In en, this message translates to:
  /// **'Changes to a completed match recalculate statistics, ratings and leaderboards.'**
  String get editPlayedMatchNote;

  /// No description provided for @chooseTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Which team?'**
  String get chooseTeamTitle;

  /// No description provided for @choosePositionTitle.
  ///
  /// In en, this message translates to:
  /// **'Which position?'**
  String get choosePositionTitle;

  /// No description provided for @errResultParticipantRemoved.
  ///
  /// In en, this message translates to:
  /// **'This player is the best player or a scorer in the recorded result. Edit the result first.'**
  String get errResultParticipantRemoved;

  /// No description provided for @errMatchNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Only a completed match\'s players can be corrected this way.'**
  String get errMatchNotCompleted;

  /// No description provided for @editPlayedParticipantsAction.
  ///
  /// In en, this message translates to:
  /// **'Edit played participants'**
  String get editPlayedParticipantsAction;

  /// No description provided for @playedParticipantsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose who played, then say which side and position each of them played in.'**
  String get playedParticipantsHint;

  /// No description provided for @savePlayedParticipantsButton.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Save corrections} =1{Save 1 participant} other{Save {count} participants}}'**
  String savePlayedParticipantsButton(int count);

  /// No description provided for @errInvalidChanges.
  ///
  /// In en, this message translates to:
  /// **'The participant corrections are invalid.'**
  String get errInvalidChanges;

  /// No description provided for @communityTitle.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get communityTitle;

  /// No description provided for @discoverHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Football, with your people.'**
  String get discoverHeroTitle;

  /// No description provided for @discoverHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Find a community near you, see what is being played this week, and take your place on the pitch.'**
  String get discoverHeroBody;

  /// No description provided for @discoverAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get discoverAlreadyHaveAccount;

  /// No description provided for @discoverSeatsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 place left} other{{count} places left}}'**
  String discoverSeatsLeft(int count);

  /// No description provided for @discoverMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No members} =1{1 member} other{{count} members}}'**
  String discoverMemberCount(int count);

  /// No description provided for @discoverUpcomingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 upcoming match} other{{count} upcoming matches}}'**
  String discoverUpcomingCount(int count);

  /// No description provided for @discoverNoUpcomingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing is scheduled just yet. Check back soon.'**
  String get discoverNoUpcomingMatches;

  /// No description provided for @discoverNoCommunities.
  ///
  /// In en, this message translates to:
  /// **'No communities yet. Be the first to start one.'**
  String get discoverNoCommunities;

  /// No description provided for @discoverCtaTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to play?'**
  String get discoverCtaTitle;

  /// No description provided for @discoverCtaBody.
  ///
  /// In en, this message translates to:
  /// **'Create an account to join a community, register for matches, and start your own.'**
  String get discoverCtaBody;

  /// No description provided for @authRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Account needed'**
  String get authRequiredTitle;

  /// No description provided for @authRequiredJoinCommunity.
  ///
  /// In en, this message translates to:
  /// **'Create an account to join this community.'**
  String get authRequiredJoinCommunity;

  /// No description provided for @authRequiredRegisterMatch.
  ///
  /// In en, this message translates to:
  /// **'Create an account to register for this match.'**
  String get authRequiredRegisterMatch;

  /// No description provided for @authRequiredCreateCommunity.
  ///
  /// In en, this message translates to:
  /// **'Create an account to start your own community.'**
  String get authRequiredCreateCommunity;

  /// No description provided for @mvpOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Tap a star to name the best player. This is optional — the result saves without one.'**
  String get mvpOptionalNote;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @viewCommunityAction.
  ///
  /// In en, this message translates to:
  /// **'View community'**
  String get viewCommunityAction;

  /// No description provided for @viewMatchAction.
  ///
  /// In en, this message translates to:
  /// **'View match'**
  String get viewMatchAction;

  /// No description provided for @discoverWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}'**
  String discoverWelcomeBack(String name);

  /// No description provided for @discoverHeroBodySignedIn.
  ///
  /// In en, this message translates to:
  /// **'See what your communities are playing this week, and find new ones to join.'**
  String get discoverHeroBodySignedIn;

  /// No description provided for @discoverCommunityCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No communities} =1{1 community} other{{count} communities}}'**
  String discoverCommunityCount(int count);

  /// No description provided for @discoverCtaTitleSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Start something of your own'**
  String get discoverCtaTitleSignedIn;

  /// No description provided for @discoverCtaBodySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Create a community and bring your regular game together in one place.'**
  String get discoverCtaBodySignedIn;

  /// No description provided for @discoverMatchesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Games with places still open'**
  String get discoverMatchesSubtitle;

  /// No description provided for @discoverCommunitiesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clubs you can join'**
  String get discoverCommunitiesSubtitle;

  /// No description provided for @homeUpcomingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Across your communities'**
  String get homeUpcomingSubtitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsNotificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsSection;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageLabel;

  /// No description provided for @languageSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get languageSystemDefault;

  /// No description provided for @languageSystemDefaultHelp.
  ///
  /// In en, this message translates to:
  /// **'Go Play follows the language your phone is set to.'**
  String get languageSystemDefaultHelp;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @showMoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMoreLabel;

  /// No description provided for @showLessLabel.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLessLabel;

  /// No description provided for @communityActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Community actions'**
  String get communityActionsTitle;

  /// No description provided for @communityInsightsAction.
  ///
  /// In en, this message translates to:
  /// **'Community insights'**
  String get communityInsightsAction;

  /// No description provided for @communityInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Community insights'**
  String get communityInsightsTitle;

  /// No description provided for @communityInsightsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get communityInsightsPeriod;

  /// No description provided for @communityInsightsActiveMembers.
  ///
  /// In en, this message translates to:
  /// **'Active members'**
  String get communityInsightsActiveMembers;

  /// No description provided for @communityInsightsParticipationRate.
  ///
  /// In en, this message translates to:
  /// **'Participation rate'**
  String get communityInsightsParticipationRate;

  /// No description provided for @communityInsightsMatchFrequency.
  ///
  /// In en, this message translates to:
  /// **'Match frequency'**
  String get communityInsightsMatchFrequency;

  /// No description provided for @communityInsightsPerWeek.
  ///
  /// In en, this message translates to:
  /// **'per week'**
  String get communityInsightsPerWeek;

  /// No description provided for @communityInsightsCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity utilization'**
  String get communityInsightsCapacity;

  /// No description provided for @communityInsightsGuestDependency.
  ///
  /// In en, this message translates to:
  /// **'Guest dependency'**
  String get communityInsightsGuestDependency;

  /// No description provided for @communityInsightsProvisionalNote.
  ///
  /// In en, this message translates to:
  /// **'Participation, capacity and guest dependency currently use saved match line-ups as evidence of who played. They will become participation-confirmed once participation confirmation is introduced.'**
  String get communityInsightsProvisionalNote;

  /// No description provided for @moreActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsLabel;

  /// No description provided for @joinCodeOrganizersOnly.
  ///
  /// In en, this message translates to:
  /// **'The join code is shown to the owner and admins only.'**
  String get joinCodeOrganizersOnly;

  /// No description provided for @membersEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has joined this community yet.'**
  String get membersEmpty;

  /// No description provided for @matchRosterEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has joined this match yet.'**
  String get matchRosterEmpty;

  /// No description provided for @matchManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit the match, manage the roster, or delete it.'**
  String get matchManagementSubtitle;

  /// No description provided for @statCompletedMatches.
  ///
  /// In en, this message translates to:
  /// **'Completed matches'**
  String get statCompletedMatches;

  /// No description provided for @leaderboardTopPlayer.
  ///
  /// In en, this message translates to:
  /// **'Leader'**
  String get leaderboardTopPlayer;

  /// No description provided for @matchMembershipRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Join the community first'**
  String get matchMembershipRequiredTitle;

  /// No description provided for @matchMembershipRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This match belongs to {community}. Join the community to see the match and register for it.'**
  String matchMembershipRequiredBody(String community);

  /// No description provided for @matchMembershipRequiredBodyUnnamed.
  ///
  /// In en, this message translates to:
  /// **'This match belongs to a community you have not joined. Join the community to see the match and register for it.'**
  String get matchMembershipRequiredBodyUnnamed;

  /// No description provided for @playerProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Player profile'**
  String get playerProfileTitle;

  /// No description provided for @openPlayerProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Open player profile'**
  String get openPlayerProfileAction;

  /// No description provided for @profileNotVisibleTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile not available'**
  String get profileNotVisibleTitle;

  /// No description provided for @errProfileNotVisible.
  ///
  /// In en, this message translates to:
  /// **'This player shares their profile with their community members only.'**
  String get errProfileNotVisible;

  /// No description provided for @settingsPrivacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacySection;

  /// No description provided for @profileVisibilityEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get profileVisibilityEveryone;

  /// No description provided for @profileVisibilityEveryoneHelp.
  ///
  /// In en, this message translates to:
  /// **'Any Go Play player can open your profile.'**
  String get profileVisibilityEveryoneHelp;

  /// No description provided for @profileVisibilityCommunityMembers.
  ///
  /// In en, this message translates to:
  /// **'Community members only'**
  String get profileVisibilityCommunityMembers;

  /// No description provided for @profileVisibilityCommunityMembersHelp.
  ///
  /// In en, this message translates to:
  /// **'Only players who share a community with you can open your profile.'**
  String get profileVisibilityCommunityMembersHelp;

  /// No description provided for @teamsShownOutOfLine.
  ///
  /// In en, this message translates to:
  /// **'Drawn in another line. Position: {position}.'**
  String teamsShownOutOfLine(String position);

  /// No description provided for @profileAgeVisibleLabel.
  ///
  /// In en, this message translates to:
  /// **'Show my age'**
  String get profileAgeVisibleLabel;

  /// No description provided for @profileAgeVisibleHelp.
  ///
  /// In en, this message translates to:
  /// **'Your age is worked out from your date of birth. Turn this off and other players will not see it.'**
  String get profileAgeVisibleHelp;

  /// No description provided for @latestResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Latest results'**
  String get latestResultsTitle;

  /// No description provided for @latestResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What has just been played'**
  String get latestResultsSubtitle;

  /// No description provided for @latestResultsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results yet. Once a match is played it shows up here.'**
  String get latestResultsEmpty;

  /// No description provided for @latestResultsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load recent football.'**
  String get latestResultsFailed;

  /// No description provided for @resultPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Result pending'**
  String get resultPendingLabel;

  /// No description provided for @footballRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Football record'**
  String get footballRecordTitle;

  /// No description provided for @footballMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get footballMatchTitle;

  /// No description provided for @topPlayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Top players'**
  String get topPlayersTitle;

  /// No description provided for @topPlayersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ranked by rating, then goals'**
  String get topPlayersSubtitle;

  /// No description provided for @topPlayersEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has a record here yet.'**
  String get topPlayersEmpty;

  /// No description provided for @recentResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent results'**
  String get recentResultsTitle;

  /// No description provided for @statPlayersWithRecord.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get statPlayersWithRecord;

  /// No description provided for @statMvps.
  ///
  /// In en, this message translates to:
  /// **'MVPs'**
  String get statMvps;

  /// No description provided for @lineupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No lineup was saved for this match. This is who took part.'**
  String get lineupUnavailable;

  /// No description provided for @rosterTitle.
  ///
  /// In en, this message translates to:
  /// **'Who played'**
  String get rosterTitle;

  /// No description provided for @goalsShort.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} goal} other{{count} goals}}'**
  String goalsShort(int count);

  /// No description provided for @communityFootballTitle.
  ///
  /// In en, this message translates to:
  /// **'Football'**
  String get communityFootballTitle;

  /// No description provided for @adminOverviewTab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get adminOverviewTab;

  /// No description provided for @adminProductHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Product health'**
  String get adminProductHealthTitle;

  /// No description provided for @adminUserGrowthTitle.
  ///
  /// In en, this message translates to:
  /// **'User growth'**
  String get adminUserGrowthTitle;

  /// No description provided for @adminEngagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Engagement'**
  String get adminEngagementTitle;

  /// No description provided for @adminFootballActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Football activity'**
  String get adminFootballActivityTitle;

  /// No description provided for @adminMetricWau.
  ///
  /// In en, this message translates to:
  /// **'Weekly active users'**
  String get adminMetricWau;

  /// No description provided for @adminMetricActiveCommunities.
  ///
  /// In en, this message translates to:
  /// **'Weekly active communities'**
  String get adminMetricActiveCommunities;

  /// No description provided for @adminMetricTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total users'**
  String get adminMetricTotalUsers;

  /// No description provided for @adminMetricNewToday.
  ///
  /// In en, this message translates to:
  /// **'New today'**
  String get adminMetricNewToday;

  /// No description provided for @adminMetricDau.
  ///
  /// In en, this message translates to:
  /// **'Daily active users'**
  String get adminMetricDau;

  /// No description provided for @adminMetricMau.
  ///
  /// In en, this message translates to:
  /// **'Monthly active users'**
  String get adminMetricMau;

  /// No description provided for @adminMetricWeeklyRetention.
  ///
  /// In en, this message translates to:
  /// **'Weekly retention'**
  String get adminMetricWeeklyRetention;

  /// No description provided for @adminMetricMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get adminMetricMatches;

  /// No description provided for @adminMetricRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Registrations'**
  String get adminMetricRegistrations;

  /// No description provided for @adminMetricTrackedRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Tracked registrations'**
  String get adminMetricTrackedRegistrations;

  /// No description provided for @adminMetricResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get adminMetricResults;

  /// No description provided for @adminPeriod7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get adminPeriod7d;

  /// No description provided for @adminPeriod30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get adminPeriod30d;

  /// No description provided for @adminMetricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get adminMetricUnavailable;

  /// What the weekly retention percentage is made of: how many of the previous week's people came back.
  ///
  /// In en, this message translates to:
  /// **'{returning} of {previous} from last week'**
  String adminRetentionBasis(int returning, int previous);

  /// No description provided for @adminAnalyticsNotice.
  ///
  /// In en, this message translates to:
  /// **'Activity metrics start from this release for sessions, registrations and withdrawals. Earlier events were not invented. Activity events are kept for 12 months, so tracked counts describe retained activity, not lifetime history; Last seen is kept beyond that window. Accounts and recorded football history still come from the business records; imported historical matches are excluded from Product Overview activity windows.'**
  String get adminAnalyticsNotice;

  /// No description provided for @adminAuditTab.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get adminAuditTab;

  /// No description provided for @adminAuditEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded yet.'**
  String get adminAuditEmpty;

  /// No description provided for @adminAuditUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No longer available'**
  String get adminAuditUnavailable;

  /// No description provided for @adminActionUserSuspended.
  ///
  /// In en, this message translates to:
  /// **'User suspended'**
  String get adminActionUserSuspended;

  /// No description provided for @adminActionUserReactivated.
  ///
  /// In en, this message translates to:
  /// **'User reactivated'**
  String get adminActionUserReactivated;

  /// No description provided for @adminActionCommunitySuspended.
  ///
  /// In en, this message translates to:
  /// **'Community suspended'**
  String get adminActionCommunitySuspended;

  /// No description provided for @adminActionCommunityReactivated.
  ///
  /// In en, this message translates to:
  /// **'Community reactivated'**
  String get adminActionCommunityReactivated;

  /// No description provided for @adminUserActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'User activity'**
  String get adminUserActivityTitle;

  /// No description provided for @adminActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get adminActivityTitle;

  /// No description provided for @adminRecentActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get adminRecentActivityTitle;

  /// No description provided for @adminActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded for this account yet.'**
  String get adminActivityEmpty;

  /// No description provided for @adminMetricJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get adminMetricJoined;

  /// No description provided for @adminMetricLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get adminMetricLastSeen;

  /// No description provided for @adminMetricActiveDays.
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get adminMetricActiveDays;

  /// No description provided for @adminMetricSessions.
  ///
  /// In en, this message translates to:
  /// **'Tracked sessions'**
  String get adminMetricSessions;

  /// No description provided for @adminMetricPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Platforms'**
  String get adminMetricPlatforms;

  /// No description provided for @adminMetricAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get adminMetricAppVersion;

  /// No description provided for @adminMetricMatchesPlayed.
  ///
  /// In en, this message translates to:
  /// **'Matches played'**
  String get adminMetricMatchesPlayed;

  /// No description provided for @adminMetricWithdrawals.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals'**
  String get adminMetricWithdrawals;

  /// No description provided for @adminMetricTrackedWithdrawals.
  ///
  /// In en, this message translates to:
  /// **'Tracked withdrawals'**
  String get adminMetricTrackedWithdrawals;

  /// No description provided for @adminPlatformWeb.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get adminPlatformWeb;

  /// No description provided for @adminPlatformAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get adminPlatformAndroid;

  /// No description provided for @adminEventSessionStarted.
  ///
  /// In en, this message translates to:
  /// **'Session started'**
  String get adminEventSessionStarted;

  /// No description provided for @adminEventCommunityViewed.
  ///
  /// In en, this message translates to:
  /// **'Community viewed'**
  String get adminEventCommunityViewed;

  /// No description provided for @adminEventCommunityCreated.
  ///
  /// In en, this message translates to:
  /// **'Community created'**
  String get adminEventCommunityCreated;

  /// No description provided for @adminEventCommunityJoined.
  ///
  /// In en, this message translates to:
  /// **'Community joined'**
  String get adminEventCommunityJoined;

  /// No description provided for @adminEventMatchViewed.
  ///
  /// In en, this message translates to:
  /// **'Match viewed'**
  String get adminEventMatchViewed;

  /// No description provided for @adminEventMatchRegistered.
  ///
  /// In en, this message translates to:
  /// **'Match registered'**
  String get adminEventMatchRegistered;

  /// No description provided for @adminEventMatchWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Match withdrawn'**
  String get adminEventMatchWithdrawn;

  /// No description provided for @adminEventTeamsViewed.
  ///
  /// In en, this message translates to:
  /// **'Teams viewed'**
  String get adminEventTeamsViewed;

  /// No description provided for @adminEventResultViewed.
  ///
  /// In en, this message translates to:
  /// **'Result viewed'**
  String get adminEventResultViewed;

  /// No description provided for @adminEventShareUsed.
  ///
  /// In en, this message translates to:
  /// **'Share used'**
  String get adminEventShareUsed;

  /// No description provided for @adminEventPublicLinkOpened.
  ///
  /// In en, this message translates to:
  /// **'Public link opened'**
  String get adminEventPublicLinkOpened;

  /// No description provided for @adminEventViewedOwnProfile.
  ///
  /// In en, this message translates to:
  /// **'Viewed own profile'**
  String get adminEventViewedOwnProfile;

  /// No description provided for @adminEventViewedPlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'Viewed player profile — {player}'**
  String adminEventViewedPlayerProfile(String player);

  /// No description provided for @adminEventViewedPlayerStatistics.
  ///
  /// In en, this message translates to:
  /// **'Viewed player statistics'**
  String get adminEventViewedPlayerStatistics;

  /// No description provided for @adminEventViewedPlayerStatisticsOf.
  ///
  /// In en, this message translates to:
  /// **'Viewed player statistics — {player}'**
  String adminEventViewedPlayerStatisticsOf(String player);

  /// No description provided for @adminEventSharedPlayerProfile.
  ///
  /// In en, this message translates to:
  /// **'Shared player profile'**
  String get adminEventSharedPlayerProfile;

  /// No description provided for @adminEventSharedPlayerStatistics.
  ///
  /// In en, this message translates to:
  /// **'Shared player statistics'**
  String get adminEventSharedPlayerStatistics;

  /// No description provided for @adminEventSharedCommunity.
  ///
  /// In en, this message translates to:
  /// **'Shared community'**
  String get adminEventSharedCommunity;

  /// No description provided for @adminEventSharedMatch.
  ///
  /// In en, this message translates to:
  /// **'Shared match'**
  String get adminEventSharedMatch;

  /// No description provided for @adminEventSharedLineup.
  ///
  /// In en, this message translates to:
  /// **'Shared lineup'**
  String get adminEventSharedLineup;

  /// No description provided for @adminEventSharedResult.
  ///
  /// In en, this message translates to:
  /// **'Shared result'**
  String get adminEventSharedResult;

  /// No description provided for @adminDrilldownEmpty.
  ///
  /// In en, this message translates to:
  /// **'No records for this metric.'**
  String get adminDrilldownEmpty;

  /// No description provided for @adminDrilldownLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get adminDrilldownLoadMore;

  /// No description provided for @adminReturned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get adminReturned;

  /// No description provided for @adminDidNotReturn.
  ///
  /// In en, this message translates to:
  /// **'Did not return'**
  String get adminDidNotReturn;

  /// No description provided for @adminCommunityInspectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Community inspection'**
  String get adminCommunityInspectionTitle;

  /// No description provided for @adminMatchInspectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Match inspection'**
  String get adminMatchInspectionTitle;

  /// No description provided for @adminOpenMatch.
  ///
  /// In en, this message translates to:
  /// **'Open match'**
  String get adminOpenMatch;

  /// No description provided for @adminMetricCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get adminMetricCreated;

  /// No description provided for @adminMetricOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get adminMetricOwner;

  /// No description provided for @adminMetricStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminMetricStatus;

  /// No description provided for @adminMetricJoinPolicy.
  ///
  /// In en, this message translates to:
  /// **'Join policy'**
  String get adminMetricJoinPolicy;

  /// No description provided for @adminMetricMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get adminMetricMembers;

  /// No description provided for @adminMetricLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get adminMetricLocation;

  /// No description provided for @adminMetricKickOff.
  ///
  /// In en, this message translates to:
  /// **'Kick-off'**
  String get adminMetricKickOff;

  /// No description provided for @adminMetricCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get adminMetricCreatedBy;

  /// No description provided for @adminMetricRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get adminMetricRegistered;

  /// No description provided for @adminMetricStartingPlayers.
  ///
  /// In en, this message translates to:
  /// **'Starting players'**
  String get adminMetricStartingPlayers;

  /// No description provided for @adminMetricScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get adminMetricScore;

  /// No description provided for @adminMetricResultRecorded.
  ///
  /// In en, this message translates to:
  /// **'Result recorded'**
  String get adminMetricResultRecorded;

  /// No description provided for @adminMetricLastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get adminMetricLastActivity;

  /// No description provided for @teamOfPeriodTitle.
  ///
  /// In en, this message translates to:
  /// **'Team of the Period'**
  String get teamOfPeriodTitle;

  /// No description provided for @teamOfPeriodCtaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The best players of this week, or of the last completed month'**
  String get teamOfPeriodCtaSubtitle;

  /// No description provided for @teamOfPeriodCtaAction.
  ///
  /// In en, this message translates to:
  /// **'View the team'**
  String get teamOfPeriodCtaAction;

  /// No description provided for @teamOfPeriodWeekTab.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get teamOfPeriodWeekTab;

  /// No description provided for @teamOfPeriodMonthTab.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get teamOfPeriodMonthTab;

  /// No description provided for @teamOfPeriodWeekHeading.
  ///
  /// In en, this message translates to:
  /// **'Team of the Week'**
  String get teamOfPeriodWeekHeading;

  /// No description provided for @teamOfPeriodMonthHeading.
  ///
  /// In en, this message translates to:
  /// **'Team of the Month'**
  String get teamOfPeriodMonthHeading;

  /// No description provided for @teamOfPeriodNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No qualifying matches were completed in this period.'**
  String get teamOfPeriodNoMatches;

  /// No description provided for @teamOfPeriodNoEligible.
  ///
  /// In en, this message translates to:
  /// **'Matches were played, but nobody played the {matches} needed to qualify.'**
  String teamOfPeriodNoEligible(int matches);

  /// No description provided for @teamOfPeriodPlayerFallback.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get teamOfPeriodPlayerFallback;

  /// No description provided for @teamOfPeriodAwardedPosition.
  ///
  /// In en, this message translates to:
  /// **'Awarded position'**
  String get teamOfPeriodAwardedPosition;

  /// No description provided for @teamOfPeriodCurrentRating.
  ///
  /// In en, this message translates to:
  /// **'Current rating'**
  String get teamOfPeriodCurrentRating;

  /// No description provided for @teamOfPeriodMatchesPlayed.
  ///
  /// In en, this message translates to:
  /// **'Matches played'**
  String get teamOfPeriodMatchesPlayed;

  /// No description provided for @teamOfPeriodParticipation.
  ///
  /// In en, this message translates to:
  /// **'Participation'**
  String get teamOfPeriodParticipation;

  /// No description provided for @teamOfPeriodGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get teamOfPeriodGoals;

  /// No description provided for @teamOfPeriodGoalsPerMatch.
  ///
  /// In en, this message translates to:
  /// **'Goals per match'**
  String get teamOfPeriodGoalsPerMatch;

  /// No description provided for @teamOfPeriodRecord.
  ///
  /// In en, this message translates to:
  /// **'Won / Drawn / Lost'**
  String get teamOfPeriodRecord;

  /// No description provided for @teamOfPeriodWinRate.
  ///
  /// In en, this message translates to:
  /// **'Win rate'**
  String get teamOfPeriodWinRate;

  /// No description provided for @teamOfPeriodPointsPerGame.
  ///
  /// In en, this message translates to:
  /// **'Points per game'**
  String get teamOfPeriodPointsPerGame;

  /// No description provided for @teamOfPeriodMvpCount.
  ///
  /// In en, this message translates to:
  /// **'Best player awards'**
  String get teamOfPeriodMvpCount;

  /// No description provided for @teamOfPeriodCurrentRatingNote.
  ///
  /// In en, this message translates to:
  /// **'The rating shown is the player\'s rating today, not their rating during this period.'**
  String get teamOfPeriodCurrentRatingNote;

  /// No description provided for @teamOfPeriodMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matches} =1{1 match} other{{count} matches}}'**
  String teamOfPeriodMatchCount(int count);

  /// No description provided for @teamOfPeriodMatchesOf.
  ///
  /// In en, this message translates to:
  /// **'{played} of {total}'**
  String teamOfPeriodMatchesOf(int played, int total);

  /// No description provided for @leaderboardLowestRated.
  ///
  /// In en, this message translates to:
  /// **'Lowest Rated'**
  String get leaderboardLowestRated;

  /// No description provided for @leaderboardLeastActive.
  ///
  /// In en, this message translates to:
  /// **'Least Active'**
  String get leaderboardLeastActive;

  /// No description provided for @leaderboardFewestWins.
  ///
  /// In en, this message translates to:
  /// **'Fewest Wins'**
  String get leaderboardFewestWins;

  /// No description provided for @reverseStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse Statistics'**
  String get reverseStatisticsTitle;

  /// No description provided for @leaderboardGoalsPerMatch.
  ///
  /// In en, this message translates to:
  /// **'{value} per match'**
  String leaderboardGoalsPerMatch(String value);

  /// No description provided for @leaderboardPointsPerGame.
  ///
  /// In en, this message translates to:
  /// **'{value} PPG'**
  String leaderboardPointsPerGame(String value);

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @authOrDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start Google sign-in. Please try again.'**
  String get googleSignInFailed;

  /// No description provided for @forgotPasswordLink.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordLink;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the email you signed up with. If it belongs to an account, we will send a code to choose a new password.'**
  String get forgotPasswordBody;

  /// No description provided for @forgotPasswordSend.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get forgotPasswordSend;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to log in'**
  String get backToLogin;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes and try again.'**
  String get tooManyRequests;

  /// No description provided for @emailCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get emailCodeTitle;

  /// No description provided for @emailCodeRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the code we sent to your email.'**
  String get emailCodeRecoveryBody;

  /// No description provided for @emailCodeSignupBody.
  ///
  /// In en, this message translates to:
  /// **'Verify your email to complete registration.'**
  String get emailCodeSignupBody;

  /// No description provided for @emailCodeSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}.'**
  String emailCodeSentTo(String email);

  /// No description provided for @emailCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get emailCodeLabel;

  /// No description provided for @emailCodeIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Enter all 6 digits.'**
  String get emailCodeIncomplete;

  /// No description provided for @emailCodeVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get emailCodeVerify;

  /// No description provided for @emailCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is incorrect or has expired. Check it, or ask for a new one.'**
  String get emailCodeInvalid;

  /// No description provided for @emailCodeResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get emailCodeResend;

  /// No description provided for @emailCodeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get emailCodeResent;

  /// No description provided for @emailCodeResendWait.
  ///
  /// In en, this message translates to:
  /// **'Did not arrive? You can ask for a new code in a minute.'**
  String get emailCodeResendWait;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get resetPasswordTitle;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordLabel;

  /// No description provided for @resetPasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get resetPasswordSubmit;

  /// No description provided for @resetPasswordLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'This reset link is no longer valid. Request a new one.'**
  String get resetPasswordLinkExpired;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed. Log in with your new password.'**
  String get passwordResetSuccess;

  /// No description provided for @completeProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your player profile'**
  String get completeProfileTitle;

  /// No description provided for @completeProfileBody.
  ///
  /// In en, this message translates to:
  /// **'One last step before you play: tell us a little about yourself.'**
  String get completeProfileBody;

  /// No description provided for @completeProfileSubmit.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get completeProfileSubmit;

  /// No description provided for @profileDetailsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please check your details and try again.'**
  String get profileDetailsInvalid;

  /// No description provided for @nearChipLabel.
  ///
  /// In en, this message translates to:
  /// **'Near: {wilayat}'**
  String nearChipLabel(String wilayat);

  /// No description provided for @nearChipChoose.
  ///
  /// In en, this message translates to:
  /// **'Near: choose Wilayat'**
  String get nearChipChoose;

  /// No description provided for @wilayatPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a Wilayat'**
  String get wilayatPickerTitle;

  /// No description provided for @wilayatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by Wilayat or village'**
  String get wilayatSearchHint;

  /// No description provided for @wilayatSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Wilayat matches your search.'**
  String get wilayatSearchEmpty;

  /// No description provided for @wilayatRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a Wilayat'**
  String get wilayatRequired;

  /// No description provided for @wilayatNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get wilayatNotSet;

  /// No description provided for @communityWilayatLabel.
  ///
  /// In en, this message translates to:
  /// **'Wilayat'**
  String get communityWilayatLabel;

  /// No description provided for @communityWilayatSaved.
  ///
  /// In en, this message translates to:
  /// **'Community Wilayat updated.'**
  String get communityWilayatSaved;

  /// No description provided for @defaultLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Default location'**
  String get defaultLocationLabel;

  /// No description provided for @defaultLocationHelp.
  ///
  /// In en, this message translates to:
  /// **'Used for Near in Discover. Only you can see it.'**
  String get defaultLocationHelp;

  /// No description provided for @defaultLocationSaved.
  ///
  /// In en, this message translates to:
  /// **'Default location updated.'**
  String get defaultLocationSaved;

  /// No description provided for @defaultLocationClear.
  ///
  /// In en, this message translates to:
  /// **'Clear default location'**
  String get defaultLocationClear;

  /// No description provided for @matchLiveBadge.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get matchLiveBadge;

  /// No description provided for @adminAccountDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Account data'**
  String get adminAccountDataTitle;

  /// No description provided for @adminAccountEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get adminAccountEditAction;

  /// No description provided for @adminAccountActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Account active'**
  String get adminAccountActiveLabel;

  /// No description provided for @adminAccountNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get adminAccountNotSet;

  /// No description provided for @adminAccountYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get adminAccountYes;

  /// No description provided for @adminAccountNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get adminAccountNo;

  /// No description provided for @adminAccountOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get adminAccountOn;

  /// No description provided for @adminAccountOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get adminAccountOff;

  /// No description provided for @adminAccountAgeVisibleLabel.
  ///
  /// In en, this message translates to:
  /// **'Age visible to others'**
  String get adminAccountAgeVisibleLabel;

  /// No description provided for @adminAccountProfileVisibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile visibility'**
  String get adminAccountProfileVisibilityLabel;

  /// No description provided for @adminAccountSignInMethodsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method'**
  String get adminAccountSignInMethodsLabel;

  /// No description provided for @adminProviderGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get adminProviderGoogle;

  /// No description provided for @adminAccountEmailConfirmedLabel.
  ///
  /// In en, this message translates to:
  /// **'Email confirmed'**
  String get adminAccountEmailConfirmedLabel;

  /// No description provided for @adminAccountEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed'**
  String get adminAccountEmailNotConfirmed;

  /// No description provided for @adminAccountLastSignInLabel.
  ///
  /// In en, this message translates to:
  /// **'Last sign-in'**
  String get adminAccountLastSignInLabel;

  /// No description provided for @adminAccountNeverSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Never signed in'**
  String get adminAccountNeverSignedIn;

  /// No description provided for @adminEditUnavailableSelf.
  ///
  /// In en, this message translates to:
  /// **'You can\'t edit your own account here.'**
  String get adminEditUnavailableSelf;

  /// No description provided for @adminEditUnavailableSystemAdmin.
  ///
  /// In en, this message translates to:
  /// **'System Admin accounts are managed outside the app.'**
  String get adminEditUnavailableSystemAdmin;

  /// No description provided for @adminEditGroupAccount.
  ///
  /// In en, this message translates to:
  /// **'Name and phone'**
  String get adminEditGroupAccount;

  /// No description provided for @adminEditGroupPlayer.
  ///
  /// In en, this message translates to:
  /// **'Date of birth and positions'**
  String get adminEditGroupPlayer;

  /// No description provided for @adminEditReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get adminEditReasonLabel;

  /// No description provided for @adminEditReasonHelp.
  ///
  /// In en, this message translates to:
  /// **'Recorded in the audit log.'**
  String get adminEditReasonHelp;

  /// No description provided for @adminEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get adminEditSaved;

  /// No description provided for @adminEditClearDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Clear date of birth'**
  String get adminEditClearDateOfBirth;

  /// No description provided for @adminEditNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'You can\'t edit this account.'**
  String get adminEditNotAllowed;

  /// No description provided for @adminEditInvalid.
  ///
  /// In en, this message translates to:
  /// **'One of the values isn\'t valid. Check them and try again.'**
  String get adminEditInvalid;

  /// No description provided for @adminEditUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'This account no longer exists.'**
  String get adminEditUserNotFound;

  /// No description provided for @adminActionUserProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Account updated'**
  String get adminActionUserProfileUpdated;

  /// No description provided for @adminAccountCreatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get adminAccountCreatedLabel;

  /// No description provided for @adminPreviewMergeAction.
  ///
  /// In en, this message translates to:
  /// **'Preview merge'**
  String get adminPreviewMergeAction;

  /// No description provided for @adminPreviewDeletionAction.
  ///
  /// In en, this message translates to:
  /// **'Preview deletion'**
  String get adminPreviewDeletionAction;

  /// No description provided for @adminPreviewMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge accounts'**
  String get adminPreviewMergeTitle;

  /// No description provided for @adminPreviewDeletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Deletion preview'**
  String get adminPreviewDeletionTitle;

  /// No description provided for @adminPreviewReadOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Read only. Nothing is merged, deleted or changed from this screen, and this preview does not make a merge or deletion available or authorised.'**
  String get adminPreviewReadOnlyNote;

  /// No description provided for @adminMergeRetainedLabel.
  ///
  /// In en, this message translates to:
  /// **'Account to keep'**
  String get adminMergeRetainedLabel;

  /// No description provided for @adminMergeSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Account to merge in'**
  String get adminMergeSourceLabel;

  /// No description provided for @adminMergeChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose an account'**
  String get adminMergeChoose;

  /// No description provided for @adminMergeSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap accounts'**
  String get adminMergeSwap;

  /// No description provided for @adminMergeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email'**
  String get adminMergeSearchHint;

  /// No description provided for @adminMergePreviewButton.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get adminMergePreviewButton;

  /// No description provided for @adminMergeNeedTwo.
  ///
  /// In en, this message translates to:
  /// **'Choose two different accounts to preview.'**
  String get adminMergeNeedTwo;

  /// No description provided for @adminPickerNoResults.
  ///
  /// In en, this message translates to:
  /// **'No accounts found.'**
  String get adminPickerNoResults;

  /// No description provided for @adminPreviewVerdictClear.
  ///
  /// In en, this message translates to:
  /// **'No blockers found in this preview.'**
  String get adminPreviewVerdictClear;

  /// No description provided for @adminPreviewVerdictBlocked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 blocker found.} other{{count} blockers found.}}'**
  String adminPreviewVerdictBlocked(int count);

  /// No description provided for @adminPreviewFindingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get adminPreviewFindingsTitle;

  /// No description provided for @adminPreviewNothingInTheWay.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the way.'**
  String get adminPreviewNothingInTheWay;

  /// No description provided for @adminSeverityBlocker.
  ///
  /// In en, this message translates to:
  /// **'Blocker'**
  String get adminSeverityBlocker;

  /// No description provided for @adminSeverityConflict.
  ///
  /// In en, this message translates to:
  /// **'Needs a rule'**
  String get adminSeverityConflict;

  /// No description provided for @adminSeverityConstraint.
  ///
  /// In en, this message translates to:
  /// **'Cannot be changed'**
  String get adminSeverityConstraint;

  /// No description provided for @adminPreviewAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get adminPreviewAccountsTitle;

  /// No description provided for @adminPreviewActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'What names the accounts'**
  String get adminPreviewActivityTitle;

  /// No description provided for @adminPreviewRetainedColumn.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get adminPreviewRetainedColumn;

  /// No description provided for @adminPreviewSourceColumn.
  ///
  /// In en, this message translates to:
  /// **'Merge in'**
  String get adminPreviewSourceColumn;

  /// No description provided for @adminPreviewOverlapTitle.
  ///
  /// In en, this message translates to:
  /// **'Communities both belong to'**
  String get adminPreviewOverlapTitle;

  /// No description provided for @adminPreviewSourceOwnedTitle.
  ///
  /// In en, this message translates to:
  /// **'Communities the merged-in account owns'**
  String get adminPreviewSourceOwnedTitle;

  /// No description provided for @adminPreviewSharedMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Matches both appear in'**
  String get adminPreviewSharedMatchesTitle;

  /// No description provided for @adminPreviewStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics that would collide'**
  String get adminPreviewStatisticsTitle;

  /// No description provided for @adminPreviewPersonalTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal data held'**
  String get adminPreviewPersonalTitle;

  /// No description provided for @adminPreviewOwnedTitle.
  ///
  /// In en, this message translates to:
  /// **'Communities owned'**
  String get adminPreviewOwnedTitle;

  /// No description provided for @adminPreviewCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Matches created'**
  String get adminPreviewCreatedTitle;

  /// No description provided for @adminPreviewHistoricalTitle.
  ///
  /// In en, this message translates to:
  /// **'Football history'**
  String get adminPreviewHistoricalTitle;

  /// No description provided for @adminPreviewPreservedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot be changed by anyone'**
  String get adminPreviewPreservedTitle;

  /// No description provided for @adminPreviewCoverageTitle.
  ///
  /// In en, this message translates to:
  /// **'Not covered by this preview'**
  String get adminPreviewCoverageTitle;

  /// No description provided for @adminPreviewShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String adminPreviewShowing(int shown, int total);

  /// No description provided for @adminPreviewOwnedRow.
  ///
  /// In en, this message translates to:
  /// **'{members} members · {admins} other admins · {matches} matches'**
  String adminPreviewOwnedRow(int members, int admins, int matches);

  /// No description provided for @adminPreviewTagRoleConflict.
  ///
  /// In en, this message translates to:
  /// **'Different roles'**
  String get adminPreviewTagRoleConflict;

  /// No description provided for @adminPreviewTagSourceOwns.
  ///
  /// In en, this message translates to:
  /// **'Merged-in account owns it'**
  String get adminPreviewTagSourceOwns;

  /// No description provided for @adminPreviewTagRetainedOwns.
  ///
  /// In en, this message translates to:
  /// **'Kept account owns it'**
  String get adminPreviewTagRetainedOwns;

  /// No description provided for @adminPreviewRetainedNotMember.
  ///
  /// In en, this message translates to:
  /// **'Kept account is not a member'**
  String get adminPreviewRetainedNotMember;

  /// No description provided for @adminPreviewCollision.
  ///
  /// In en, this message translates to:
  /// **'Collision'**
  String get adminPreviewCollision;

  /// No description provided for @adminPreviewHasResult.
  ///
  /// In en, this message translates to:
  /// **'Has a recorded result'**
  String get adminPreviewHasResult;

  /// No description provided for @adminPreviewRating.
  ///
  /// In en, this message translates to:
  /// **'Overall rating'**
  String get adminPreviewRating;

  /// No description provided for @adminEvidenceRegistration.
  ///
  /// In en, this message translates to:
  /// **'Registration'**
  String get adminEvidenceRegistration;

  /// No description provided for @adminEvidenceLineup.
  ///
  /// In en, this message translates to:
  /// **'Lineup'**
  String get adminEvidenceLineup;

  /// No description provided for @adminEvidenceGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get adminEvidenceGoals;

  /// No description provided for @adminEvidenceMvp.
  ///
  /// In en, this message translates to:
  /// **'MVP'**
  String get adminEvidenceMvp;

  /// No description provided for @adminEvidenceRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get adminEvidenceRating;

  /// No description provided for @adminTreatmentCascadeDelete.
  ///
  /// In en, this message translates to:
  /// **'Erased with the account'**
  String get adminTreatmentCascadeDelete;

  /// No description provided for @adminTreatmentDetach.
  ///
  /// In en, this message translates to:
  /// **'Link removed, record kept'**
  String get adminTreatmentDetach;

  /// No description provided for @adminTreatmentRetainedId.
  ///
  /// In en, this message translates to:
  /// **'Kept, pointing at no account'**
  String get adminTreatmentRetainedId;

  /// No description provided for @adminCountMemberships.
  ///
  /// In en, this message translates to:
  /// **'Community memberships'**
  String get adminCountMemberships;

  /// No description provided for @adminCountOwned.
  ///
  /// In en, this message translates to:
  /// **'Communities owned'**
  String get adminCountOwned;

  /// No description provided for @adminCountCreated.
  ///
  /// In en, this message translates to:
  /// **'Matches created'**
  String get adminCountCreated;

  /// No description provided for @adminCountRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Match registrations'**
  String get adminCountRegistrations;

  /// No description provided for @adminCountUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming registrations'**
  String get adminCountUpcoming;

  /// No description provided for @adminCountLineup.
  ///
  /// In en, this message translates to:
  /// **'Lineup places'**
  String get adminCountLineup;

  /// No description provided for @adminCountGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals scored'**
  String get adminCountGoals;

  /// No description provided for @adminCountGoalRows.
  ///
  /// In en, this message translates to:
  /// **'Goal records'**
  String get adminCountGoalRows;

  /// No description provided for @adminCountMvp.
  ///
  /// In en, this message translates to:
  /// **'MVP awards'**
  String get adminCountMvp;

  /// No description provided for @adminCountCareerStats.
  ///
  /// In en, this message translates to:
  /// **'Matches played (career)'**
  String get adminCountCareerStats;

  /// No description provided for @adminCountRatingEntries.
  ///
  /// In en, this message translates to:
  /// **'Rating entries'**
  String get adminCountRatingEntries;

  /// No description provided for @adminCountRatingArchive.
  ///
  /// In en, this message translates to:
  /// **'Rating archive rows'**
  String get adminCountRatingArchive;

  /// No description provided for @adminCountCommunityStatistics.
  ///
  /// In en, this message translates to:
  /// **'Community statistics rows'**
  String get adminCountCommunityStatistics;

  /// No description provided for @adminCountTeamAwards.
  ///
  /// In en, this message translates to:
  /// **'Team of the period awards'**
  String get adminCountTeamAwards;

  /// No description provided for @adminCountNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get adminCountNotifications;

  /// No description provided for @adminCountPushTokens.
  ///
  /// In en, this message translates to:
  /// **'Push tokens'**
  String get adminCountPushTokens;

  /// No description provided for @adminCountActivityEvents.
  ///
  /// In en, this message translates to:
  /// **'Activity events'**
  String get adminCountActivityEvents;

  /// No description provided for @adminCountAuditEntries.
  ///
  /// In en, this message translates to:
  /// **'Audit log entries'**
  String get adminCountAuditEntries;

  /// No description provided for @adminPersonalProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get adminPersonalProfile;

  /// No description provided for @adminPersonalIdentities.
  ///
  /// In en, this message translates to:
  /// **'Sign-in identities'**
  String get adminPersonalIdentities;

  /// No description provided for @adminPersonalAvatar.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get adminPersonalAvatar;

  /// No description provided for @adminPersonalPushPreferences.
  ///
  /// In en, this message translates to:
  /// **'Push preferences'**
  String get adminPersonalPushPreferences;

  /// No description provided for @adminHistRecordedResults.
  ///
  /// In en, this message translates to:
  /// **'Results recorded'**
  String get adminHistRecordedResults;

  /// No description provided for @adminHistGuestsAdded.
  ///
  /// In en, this message translates to:
  /// **'Professional guests added'**
  String get adminHistGuestsAdded;

  /// No description provided for @adminHistRegistrationEvents.
  ///
  /// In en, this message translates to:
  /// **'Registration events'**
  String get adminHistRegistrationEvents;

  /// No description provided for @adminHistMembershipEvents.
  ///
  /// In en, this message translates to:
  /// **'Membership events'**
  String get adminHistMembershipEvents;

  /// No description provided for @adminHistGenerationRuns.
  ///
  /// In en, this message translates to:
  /// **'Lineup generation runs'**
  String get adminHistGenerationRuns;

  /// No description provided for @adminHistConfirmedLineups.
  ///
  /// In en, this message translates to:
  /// **'Lineups confirmed'**
  String get adminHistConfirmedLineups;

  /// No description provided for @adminHistRatingHistoryArchive.
  ///
  /// In en, this message translates to:
  /// **'Rating history archive'**
  String get adminHistRatingHistoryArchive;

  /// No description provided for @adminHistUserRatingArchive.
  ///
  /// In en, this message translates to:
  /// **'Rating archive (per account)'**
  String get adminHistUserRatingArchive;

  /// No description provided for @adminCoverageGenerationEvidence.
  ///
  /// In en, this message translates to:
  /// **'Player ids embedded inside saved lineup-generation data are not scanned.'**
  String get adminCoverageGenerationEvidence;

  /// No description provided for @adminCoverageStorage.
  ///
  /// In en, this message translates to:
  /// **'The profile picture file in storage is not inspected.'**
  String get adminCoverageStorage;

  /// No description provided for @adminCoverageSessions.
  ///
  /// In en, this message translates to:
  /// **'Sign-in sessions and tokens are not inspected.'**
  String get adminCoverageSessions;

  /// No description provided for @adminFindingSourceIsCaller.
  ///
  /// In en, this message translates to:
  /// **'The account to merge in is your own'**
  String get adminFindingSourceIsCaller;

  /// No description provided for @adminFindingRetainedIsCaller.
  ///
  /// In en, this message translates to:
  /// **'The account to keep is your own'**
  String get adminFindingRetainedIsCaller;

  /// No description provided for @adminFindingSourceIsSystemAdmin.
  ///
  /// In en, this message translates to:
  /// **'The account to merge in is a System Admin'**
  String get adminFindingSourceIsSystemAdmin;

  /// No description provided for @adminFindingRetainedIsSystemAdmin.
  ///
  /// In en, this message translates to:
  /// **'The account to keep is a System Admin'**
  String get adminFindingRetainedIsSystemAdmin;

  /// No description provided for @adminFindingOwnershipConflict.
  ///
  /// In en, this message translates to:
  /// **'Communities owned by the merged-in account that the kept account already belongs to'**
  String get adminFindingOwnershipConflict;

  /// No description provided for @adminFindingSharedMatchCollision.
  ///
  /// In en, this message translates to:
  /// **'Matches where both accounts hold the same kind of record'**
  String get adminFindingSharedMatchCollision;

  /// No description provided for @adminFindingSourceOwnsCommunities.
  ///
  /// In en, this message translates to:
  /// **'Communities owned by the merged-in account need a new owner'**
  String get adminFindingSourceOwnsCommunities;

  /// No description provided for @adminFindingRoleConflict.
  ///
  /// In en, this message translates to:
  /// **'Communities where the two accounts have different roles'**
  String get adminFindingRoleConflict;

  /// No description provided for @adminFindingSharedMatchParticipation.
  ///
  /// In en, this message translates to:
  /// **'Matches both accounts appear in, without the same kind of record'**
  String get adminFindingSharedMatchParticipation;

  /// No description provided for @adminFindingSourceCreatedMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches created by the merged-in account'**
  String get adminFindingSourceCreatedMatches;

  /// No description provided for @adminFindingCommunityStatisticsCollision.
  ///
  /// In en, this message translates to:
  /// **'Community statistics rows both accounts hold'**
  String get adminFindingCommunityStatisticsCollision;

  /// No description provided for @adminFindingTeamAwardCollision.
  ///
  /// In en, this message translates to:
  /// **'Both accounts hold an award in the same team of the period; none is discarded, so the merge is blocked'**
  String get adminFindingTeamAwardCollision;

  /// No description provided for @adminFindingPlayerStatisticsRecompute.
  ///
  /// In en, this message translates to:
  /// **'Career statistics would have to be recomputed (matches played)'**
  String get adminFindingPlayerStatisticsRecompute;

  /// No description provided for @adminFindingRatingReplayRequired.
  ///
  /// In en, this message translates to:
  /// **'Rating history would have to be replayed (entries)'**
  String get adminFindingRatingReplayRequired;

  /// No description provided for @adminFindingRatingArchiveImmutable.
  ///
  /// In en, this message translates to:
  /// **'Rating archive rows name this account and cannot be moved or deleted, so retiring it safely is not demonstrated'**
  String get adminFindingRatingArchiveImmutable;

  /// No description provided for @adminFindingEventLogsNameSource.
  ///
  /// In en, this message translates to:
  /// **'Event logs that name the merged-in account stay as they are'**
  String get adminFindingEventLogsNameSource;

  /// No description provided for @adminFindingAuditLogNamesSource.
  ///
  /// In en, this message translates to:
  /// **'Audit log entries carry this account\'s name or email and cannot be erased by a merge, so it is blocked'**
  String get adminFindingAuditLogNamesSource;

  /// No description provided for @adminFindingTargetIsCaller.
  ///
  /// In en, this message translates to:
  /// **'This is your own account'**
  String get adminFindingTargetIsCaller;

  /// No description provided for @adminFindingTargetIsSystemAdmin.
  ///
  /// In en, this message translates to:
  /// **'This account is a System Admin'**
  String get adminFindingTargetIsSystemAdmin;

  /// No description provided for @adminFindingOwnsCommunities.
  ///
  /// In en, this message translates to:
  /// **'Owns communities: ownership must be transferred first'**
  String get adminFindingOwnsCommunities;

  /// No description provided for @adminFindingCreatedMatches.
  ///
  /// In en, this message translates to:
  /// **'Created matches: they must be reassigned first'**
  String get adminFindingCreatedMatches;

  /// No description provided for @adminFindingMvpResultsWouldCascade.
  ///
  /// In en, this message translates to:
  /// **'Deleting would erase the results of matches where this player is the MVP'**
  String get adminFindingMvpResultsWouldCascade;

  /// No description provided for @adminFindingHistoryWouldCascade.
  ///
  /// In en, this message translates to:
  /// **'Football history that would be erased with the account'**
  String get adminFindingHistoryWouldCascade;

  /// No description provided for @adminFindingUpcomingRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Registered for upcoming matches'**
  String get adminFindingUpcomingRegistrations;

  /// No description provided for @adminFindingRatingHistoryImmutable.
  ///
  /// In en, this message translates to:
  /// **'Rating entries cannot be edited (updates are rejected), so they cannot be anonymised in place; deleting the account deletes them'**
  String get adminFindingRatingHistoryImmutable;

  /// No description provided for @adminFindingAuditLogAppendOnly.
  ///
  /// In en, this message translates to:
  /// **'Audit log entries naming this account are not erased by a deletion, so its name or email address would stay identifiable in them'**
  String get adminFindingAuditLogAppendOnly;

  /// No description provided for @adminFindingEventLogsNameAccount.
  ///
  /// In en, this message translates to:
  /// **'Event logs that name this account stay as they are'**
  String get adminFindingEventLogsNameAccount;

  /// No description provided for @adminHistCareerStatistics.
  ///
  /// In en, this message translates to:
  /// **'Career statistics'**
  String get adminHistCareerStatistics;

  /// No description provided for @adminMergeNotice.
  ///
  /// In en, this message translates to:
  /// **'Merging is permanent. The account to merge in is deleted for good, including its sign-in, and its football record is added to the account to keep. Nothing happens until you confirm.'**
  String get adminMergeNotice;

  /// No description provided for @adminMergePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'What the merge will do'**
  String get adminMergePlanTitle;

  /// No description provided for @adminMergePlanCommunitiesTransferred.
  ///
  /// In en, this message translates to:
  /// **'Communities passed to the account to keep'**
  String get adminMergePlanCommunitiesTransferred;

  /// No description provided for @adminMergePlanMembershipsMoved.
  ///
  /// In en, this message translates to:
  /// **'Memberships moved'**
  String get adminMergePlanMembershipsMoved;

  /// No description provided for @adminMergePlanMembershipsMerged.
  ///
  /// In en, this message translates to:
  /// **'Duplicate memberships merged (the higher role stays)'**
  String get adminMergePlanMembershipsMerged;

  /// No description provided for @adminMergePlanRolesUpgraded.
  ///
  /// In en, this message translates to:
  /// **'Roles raised to the higher one'**
  String get adminMergePlanRolesUpgraded;

  /// No description provided for @adminMergePlanRegistrationsMoved.
  ///
  /// In en, this message translates to:
  /// **'Match registrations moved'**
  String get adminMergePlanRegistrationsMoved;

  /// No description provided for @adminMergePlanLineupPlacesMoved.
  ///
  /// In en, this message translates to:
  /// **'Lineup places moved'**
  String get adminMergePlanLineupPlacesMoved;

  /// No description provided for @adminMergePlanGoalRowsMoved.
  ///
  /// In en, this message translates to:
  /// **'Goal records moved'**
  String get adminMergePlanGoalRowsMoved;

  /// No description provided for @adminMergePlanMvpAwardsMoved.
  ///
  /// In en, this message translates to:
  /// **'MVP awards moved'**
  String get adminMergePlanMvpAwardsMoved;

  /// No description provided for @adminMergePlanTeamAwardsMoved.
  ///
  /// In en, this message translates to:
  /// **'Team of the period awards moved'**
  String get adminMergePlanTeamAwardsMoved;

  /// No description provided for @adminMergePlanCreatedMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches the merged-in account created, re-attributed'**
  String get adminMergePlanCreatedMatches;

  /// No description provided for @adminMergePlanFootnote.
  ///
  /// In en, this message translates to:
  /// **'The kept account\'s rating is recalculated match by match in date order, and its statistics are rebuilt from the records. Nobody else\'s rating or statistics change.'**
  String get adminMergePlanFootnote;

  /// No description provided for @adminMergeChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose which participation to keep'**
  String get adminMergeChoiceTitle;

  /// No description provided for @adminMergeChoiceHelp.
  ///
  /// In en, this message translates to:
  /// **'A player has one place in a match. For each match below, choose whose participation stays; the other is removed. Goals, MVP awards, results and confirmed lineups are never removed.'**
  String get adminMergeChoiceHelp;

  /// No description provided for @adminMergeKeepRetained.
  ///
  /// In en, this message translates to:
  /// **'Keep {name}'**
  String adminMergeKeepRetained(String name);

  /// No description provided for @adminMergeKeepSource.
  ///
  /// In en, this message translates to:
  /// **'Keep {name}'**
  String adminMergeKeepSource(String name);

  /// No description provided for @adminMergeHeldBy.
  ///
  /// In en, this message translates to:
  /// **'{name} can\'t be removed here: {reasons}'**
  String adminMergeHeldBy(String name, String reasons);

  /// No description provided for @adminMergeBlockerGoals.
  ///
  /// In en, this message translates to:
  /// **'scored goals'**
  String get adminMergeBlockerGoals;

  /// No description provided for @adminMergeBlockerMvp.
  ///
  /// In en, this message translates to:
  /// **'is the match\'s MVP'**
  String get adminMergeBlockerMvp;

  /// No description provided for @adminMergeBlockerLineupInResult.
  ///
  /// In en, this message translates to:
  /// **'is in the lineup a result was recorded from'**
  String get adminMergeBlockerLineupInResult;

  /// No description provided for @adminMergeBlockerConfirmedLineup.
  ///
  /// In en, this message translates to:
  /// **'is in a confirmed lineup'**
  String get adminMergeBlockerConfirmedLineup;

  /// No description provided for @adminMergeBlockerRating.
  ///
  /// In en, this message translates to:
  /// **'has a rating in effect from this match'**
  String get adminMergeBlockerRating;

  /// No description provided for @adminMergeNeedChoices.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Choose which participation to keep in 1 match.} other{Choose which participation to keep in {count} matches.}}'**
  String adminMergeNeedChoices(int count);

  /// No description provided for @adminMergeResolveBlockersFirst.
  ///
  /// In en, this message translates to:
  /// **'Resolve the blockers above first.'**
  String get adminMergeResolveBlockersFirst;

  /// No description provided for @adminMergeExecuteButton.
  ///
  /// In en, this message translates to:
  /// **'Merge accounts…'**
  String get adminMergeExecuteButton;

  /// No description provided for @adminMergeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge permanently?'**
  String get adminMergeConfirmTitle;

  /// No description provided for @adminMergeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{source} will be deleted for good, including their sign-in. Their football record will be added to {retained}. This cannot be undone.'**
  String adminMergeConfirmBody(String source, String retained);

  /// No description provided for @adminMergeConfirmTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type the name of the account to delete: {name}'**
  String adminMergeConfirmTypeLabel(String name);

  /// No description provided for @adminMergeConfirmField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminMergeConfirmField;

  /// No description provided for @adminMergeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Merge permanently'**
  String get adminMergeConfirmAction;

  /// No description provided for @adminMergeRunning.
  ///
  /// In en, this message translates to:
  /// **'Merging…'**
  String get adminMergeRunning;

  /// No description provided for @adminMergeDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts merged'**
  String get adminMergeDoneTitle;

  /// No description provided for @adminMergeDoneBody.
  ///
  /// In en, this message translates to:
  /// **'{source} was deleted. Their football record now belongs to {retained}.'**
  String adminMergeDoneBody(String source, String retained);

  /// No description provided for @adminMergeDoneRating.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s rating was recalculated: {before} → {after}.'**
  String adminMergeDoneRating(String name, String before, String after);

  /// No description provided for @adminMergeDoneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get adminMergeDoneButton;

  /// No description provided for @adminMergeFailedConflict.
  ///
  /// In en, this message translates to:
  /// **'The merge was not performed. Something changed or is in the way. Review the preview again.'**
  String get adminMergeFailedConflict;

  /// No description provided for @adminMergeFailedNotFound.
  ///
  /// In en, this message translates to:
  /// **'One of the accounts no longer exists. If a merge just ran, the account to merge in is already gone.'**
  String get adminMergeFailedNotFound;

  /// No description provided for @adminMergeFailedAuthorization.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to merge these accounts.'**
  String get adminMergeFailedAuthorization;

  /// No description provided for @adminMergeFailedValidation.
  ///
  /// In en, this message translates to:
  /// **'The request was not accepted. Nothing was changed.'**
  String get adminMergeFailedValidation;

  /// No description provided for @adminMergeFailedUncertain.
  ///
  /// In en, this message translates to:
  /// **'The merge may or may not have been performed. Check the preview before trying again: if it went through, the account to merge in no longer exists.'**
  String get adminMergeFailedUncertain;

  /// No description provided for @adminMergeCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get adminMergeCheckAgain;

  /// No description provided for @adminFindingSharedMatchNotResolvable.
  ///
  /// In en, this message translates to:
  /// **'Matches where neither account\'s participation can be removed (goals, MVP awards, recorded lineups): correct them first'**
  String get adminFindingSharedMatchNotResolvable;

  /// No description provided for @adminFindingSharedMatchLimitExceeded.
  ///
  /// In en, this message translates to:
  /// **'More shared matches than one merge can resolve (100)'**
  String get adminFindingSharedMatchLimitExceeded;

  /// No description provided for @adminFindingSharedMatchChoiceRequired.
  ///
  /// In en, this message translates to:
  /// **'Matches both accounts took part in: choose which participation to keep'**
  String get adminFindingSharedMatchChoiceRequired;

  /// No description provided for @adminFindingSourceHasStoredFiles.
  ///
  /// In en, this message translates to:
  /// **'The account to merge in still has a profile picture in storage. A merge cannot delete it and it is public, so it must be removed first'**
  String get adminFindingSourceHasStoredFiles;

  /// No description provided for @adminFindingRetainedRatingInconsistent.
  ///
  /// In en, this message translates to:
  /// **'The rating of the account to keep does not follow from its rating history, so it cannot be recalculated safely'**
  String get adminFindingRetainedRatingInconsistent;

  /// No description provided for @adminFindingRatingArchiveMapped.
  ///
  /// In en, this message translates to:
  /// **'Rating archive rows keep the old account id; the merge records which account it became'**
  String get adminFindingRatingArchiveMapped;
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
