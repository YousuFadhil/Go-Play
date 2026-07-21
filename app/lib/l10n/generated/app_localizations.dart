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

  /// No description provided for @navGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get navGroups;

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
  /// **'e.g. 9665xxxxxxxx (with country code)'**
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
  /// **'Enter a valid phone number with country code'**
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

  /// No description provided for @welcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Logged in successfully'**
  String get welcomeMessage;

  /// No description provided for @groupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsTitle;

  /// No description provided for @groupsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You are not in any group yet.\nCreate a group or join one with a code.'**
  String get groupsEmpty;

  /// No description provided for @createGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroupTitle;

  /// No description provided for @createGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroupButton;

  /// No description provided for @joinGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get joinGroupTitle;

  /// No description provided for @joinGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinGroupButton;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Group name is required'**
  String get groupNameRequired;

  /// No description provided for @groupDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get groupDescriptionLabel;

  /// No description provided for @privateGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Private group'**
  String get privateGroupLabel;

  /// No description provided for @privateGroupHelp.
  ///
  /// In en, this message translates to:
  /// **'Private groups can only be joined with the join code.'**
  String get privateGroupHelp;

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

  /// No description provided for @groupNotFound.
  ///
  /// In en, this message translates to:
  /// **'No group found with this code.'**
  String get groupNotFound;

  /// No description provided for @alreadyMember.
  ///
  /// In en, this message translates to:
  /// **'You are already a member of this group.'**
  String get alreadyMember;

  /// No description provided for @groupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the group. Please try again.'**
  String get groupCreateFailed;

  /// No description provided for @groupJoinFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to join the group. Please try again.'**
  String get groupJoinFailed;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTitle;

  /// No description provided for @ownerBadge.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get ownerBadge;

  /// No description provided for @joinCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Join code copied'**
  String get joinCodeCopied;

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

  /// No description provided for @maxPlayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Max players'**
  String get maxPlayersLabel;

  /// No description provided for @maxPlayersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a number between 2 and 30'**
  String get maxPlayersInvalid;

  /// No description provided for @matchCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the match. Please try again.'**
  String get matchCreateFailed;

  /// No description provided for @groupMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matches in this group yet.'**
  String get groupMatchesEmpty;

  /// No description provided for @upcomingMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming matches'**
  String get upcomingMatchesTitle;

  /// No description provided for @upcomingMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No upcoming matches.\nJoin a group and create a match to get started.'**
  String get upcomingMatchesEmpty;

  /// No description provided for @matchStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get matchStatusOpen;

  /// No description provided for @matchStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get matchStatusCancelled;

  /// No description provided for @matchStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get matchStatusCompleted;

  /// No description provided for @playersCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get playersCountLabel;

  /// No description provided for @cancelMatchButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel match'**
  String get cancelMatchButton;

  /// No description provided for @cancelMatchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this match?'**
  String get cancelMatchConfirmTitle;

  /// No description provided for @cancelMatchConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get cancelMatchConfirmBody;

  /// No description provided for @confirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get confirmYes;

  /// No description provided for @confirmNo.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get confirmNo;

  /// No description provided for @matchCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel the match. Please try again.'**
  String get matchCancelFailed;

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
