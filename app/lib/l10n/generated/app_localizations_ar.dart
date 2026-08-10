// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'Go Play';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navCommunities => 'المجتمعات';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get emailRequired => 'البريد الإلكتروني مطلوب';

  @override
  String get emailInvalid => 'أدخل بريداً إلكترونياً صحيحاً';

  @override
  String get phoneLabel => 'رقم الجوال';

  @override
  String get phoneHint => '٨ أرقام، مثال: 9012 3456';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get phoneRequired => 'رقم الجوال مطلوب';

  @override
  String get phoneInvalid => 'أدخل رقم جوال من 8 أرقام';

  @override
  String get passwordRequired => 'كلمة المرور مطلوبة';

  @override
  String get passwordTooShort => 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';

  @override
  String get loginTitle => 'تسجيل الدخول';

  @override
  String get loginButton => 'دخول';

  @override
  String get loginFailed =>
      'فشل تسجيل الدخول. تحقق من البريد الإلكتروني وكلمة المرور.';

  @override
  String get noAccountPrompt => 'ليس لديك حساب؟ إنشاء حساب';

  @override
  String get registerTitle => 'إنشاء حساب';

  @override
  String get registerButton => 'إنشاء الحساب';

  @override
  String get registerFailed => 'فشل إنشاء الحساب. حاول مرة أخرى.';

  @override
  String get emailAlreadyUsed => 'البريد الإلكتروني مسجل مسبقاً.';

  @override
  String get fullNameLabel => 'الاسم الكامل';

  @override
  String get fullNameRequired => 'الاسم الكامل مطلوب';

  @override
  String get positionLabel => 'المركز الأساسي';

  @override
  String get positionRequired => 'المركز الأساسي مطلوب';

  @override
  String get haveAccountPrompt => 'لديك حساب؟ تسجيل الدخول';

  @override
  String get positionGk => 'حارس مرمى';

  @override
  String get positionDef => 'مدافع';

  @override
  String get positionMid => 'وسط';

  @override
  String get positionFwd => 'مهاجم';

  @override
  String get secondaryPositionLabel => 'المركز الثانوي (اختياري)';

  @override
  String get noSecondaryPosition => 'بدون';

  @override
  String get secondaryPositionSameAsPrimary =>
      'المركز الثانوي يجب أن يختلف عن المركز الأساسي';

  @override
  String get dateOfBirthLabel => 'تاريخ الميلاد';

  @override
  String get dateOfBirthRequired => 'تاريخ الميلاد مطلوب';

  @override
  String get selectDateLabel => 'اختر التاريخ';

  @override
  String get profileTitle => 'الملف الشخصي';

  @override
  String get profileSaved => 'تم تحديث الملف الشخصي.';

  @override
  String get profileSaveFailed => 'فشل حفظ الملف الشخصي. حاول مرة أخرى.';

  @override
  String get homeTitle => 'الرئيسية';

  @override
  String get logoutLabel => 'تسجيل الخروج';

  @override
  String get communitiesTitle => 'المجتمعات';

  @override
  String get communitiesEmpty =>
      'لست عضواً في أي مجتمع بعد.\nأنشئ مجتمعاً أو انضم برمز الانضمام.';

  @override
  String get createCommunityTitle => 'إنشاء مجتمع';

  @override
  String get createCommunityButton => 'إنشاء المجتمع';

  @override
  String get joinCommunityTitle => 'الانضمام لمجتمع';

  @override
  String get joinCommunityButton => 'انضمام';

  @override
  String get communityNameLabel => 'اسم المجتمع';

  @override
  String get communityNameRequired => 'اسم المجتمع مطلوب';

  @override
  String get communityDescriptionLabel => 'الوصف (اختياري)';

  @override
  String get joinCodeLabel => 'رمز الانضمام';

  @override
  String get joinCodeRequired => 'رمز الانضمام مطلوب';

  @override
  String get communityNotFound => 'لا يوجد مجتمع بهذا الرمز.';

  @override
  String get alreadyMemberOfCommunity => 'أنت عضو في هذا المجتمع بالفعل.';

  @override
  String get communityCreateFailed => 'فشل إنشاء المجتمع. حاول مرة أخرى.';

  @override
  String get communityJoinFailed => 'فشل الانضمام للمجتمع. حاول مرة أخرى.';

  @override
  String get membersTitle => 'الأعضاء';

  @override
  String get joinCodeCopied => 'تم نسخ رمز الانضمام';

  @override
  String get myCommunitiesSection => 'مجتمعاتي';

  @override
  String get publicCommunitiesSection => 'المجتمعات العامة';

  @override
  String get joinedCommunity => 'تم انضمامك للمجتمع.';

  @override
  String get matchesTitle => 'المباريات';

  @override
  String get createMatchTitle => 'إنشاء مباراة';

  @override
  String get createMatchButton => 'إنشاء المباراة';

  @override
  String get matchDetailsTitle => 'تفاصيل المباراة';

  @override
  String get locationLabel => 'الموقع';

  @override
  String get locationRequired => 'الموقع مطلوب';

  @override
  String get dateLabel => 'التاريخ';

  @override
  String get startTimeLabel => 'وقت البداية';

  @override
  String get endTimeLabel => 'وقت النهاية';

  @override
  String get dateTimeRequired => 'اختر التاريخ والأوقات';

  @override
  String get endAfterStartError => 'وقت النهاية يجب أن يكون بعد وقت البداية';

  @override
  String get startInPastError => 'يجب أن تبدأ المباراة في المستقبل';

  @override
  String get startingPlayersLabel => 'اللاعبون الأساسيون';

  @override
  String get startingPlayersInvalid => 'أدخل رقماً بين 4 و 30';

  @override
  String capacityAutoNote(int reserve, int max) {
    return 'لاعبو الاحتياط: $reserve (تلقائي) — الحد الأقصى للتسجيل: $max';
  }

  @override
  String get matchCreateFailed => 'فشل إنشاء المباراة. حاول مرة أخرى.';

  @override
  String get errInvalidTitle => 'أدخل اسم مباراة لا يقل عن حرفين.';

  @override
  String get errInvalidLocation => 'أدخل موقعاً لا يقل عن حرفين.';

  @override
  String get errCommunityInactive =>
      'هذا المجتمع لم يعد نشطاً، ولا يمكن إنشاء مباراة فيه.';

  @override
  String get communityMatchesEmpty => 'لا توجد مباريات في هذا المجتمع بعد.';

  @override
  String get upcomingMatchesTitle => 'المباريات القادمة';

  @override
  String get upcomingMatchesEmpty =>
      'لا توجد مباريات قادمة.\nانضم لمجتمع للبدء.';

  @override
  String get matchStatusOpen => 'مفتوحة';

  @override
  String get matchStatusFull => 'مكتملة';

  @override
  String get matchStatusCompleted => 'منتهية';

  @override
  String get confirmNo => 'رجوع';

  @override
  String get joinMatchButton => 'الانضمام للمباراة';

  @override
  String get withdrawMatchButton => 'الانسحاب';

  @override
  String get joinedConfirmed => 'تم تسجيلك في المباراة.';

  @override
  String get joinedReserve => 'المباراة مكتملة. تمت إضافتك لقائمة الاحتياط.';

  @override
  String get youAreConfirmed => 'أنت مسجل في هذه المباراة.';

  @override
  String get youAreReserve => 'أنت في قائمة الاحتياط.';

  @override
  String get reserveListTitle => 'قائمة الاحتياط';

  @override
  String get matchFullNote =>
      'المباراة مكتملة. الانضمام الآن يضيفك لقائمة الاحتياط.';

  @override
  String get withdrawConfirmTitle => 'الانسحاب من هذه المباراة؟';

  @override
  String get withdrawConfirmBody =>
      'إذا كان لديك مقعد أساسي فسيحل أول لاعب احتياط مكانك.';

  @override
  String get errOverlappingMatch => 'أنت مسجل في مباراة أخرى في نفس الوقت.';

  @override
  String get errMatchClosed => 'التسجيل مغلق لهذه المباراة.';

  @override
  String get errAlreadyRegistered => 'أنت مسجل في هذه المباراة بالفعل.';

  @override
  String get errNotRegistered => 'أنت غير مسجل في هذه المباراة.';

  @override
  String get joinMatchFailed => 'فشل الانضمام للمباراة. حاول مرة أخرى.';

  @override
  String get withdrawMatchFailed => 'فشل الانسحاب. حاول مرة أخرى.';

  @override
  String homeGreeting(String name) {
    return 'مرحباً، $name';
  }

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get notificationsEmpty => 'لا توجد إشعارات بعد.';

  @override
  String get notifMatchUpdated => 'تم تعديل تفاصيل المباراة.';

  @override
  String get notifMovedToReserve =>
      'تم نقلك إلى قائمة الاحتياط بسبب تعديل عدد اللاعبين.';

  @override
  String get notifRemoved => 'قام المنظم بإزالتك من المباراة.';

  @override
  String get notifPromoted => 'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.';

  @override
  String get notifMatchDeleted => 'تم حذف المباراة.';

  @override
  String get notifMatchCreated => 'تم إنشاء مباراة جديدة.';

  @override
  String get notifRegistrationOpened => 'تم فتح التسجيل.';

  @override
  String get notifMatchFull => 'اكتمل عدد اللاعبين في المباراة.';

  @override
  String get notifTeamsRegenerated => 'تمت إعادة توزيع الفرق.';

  @override
  String get notifMatchStartingSoon => 'تبدأ مباراتك خلال أقل من ساعة.';

  @override
  String get notifMatchTimeChanged => 'تم تغيير موعد المباراة.';

  @override
  String get notifCommunityInvitation => 'تمت دعوتك إلى مجتمع.';

  @override
  String get notifCommunityJoinAccepted => 'تم قبول طلب انضمامك.';

  @override
  String get notifCommunityPictureUpdated => 'تم تحديث صورة المجتمع.';

  @override
  String get notifCommunityDescriptionUpdated => 'تم تحديث وصف المجتمع.';

  @override
  String get notifCommunitySettingsUpdated => 'تم تحديث إعدادات المجتمع.';

  @override
  String get pushSettingsTitle => 'إشعارات الجوال';

  @override
  String get pushSettingsIntro =>
      'تُحفظ جميع الإشعارات داخل التطبيق. هذه الخيارات تحدد ما ينبهك به جوالك فقط.';

  @override
  String get pushMatchLabel => 'إشعارات المباريات';

  @override
  String get pushMatchSubtitle => 'التسجيل وتغييرات اللاعبين والتذكيرات.';

  @override
  String get pushCommunityLabel => 'إشعارات المجتمعات';

  @override
  String get pushCommunitySubtitle => 'الدعوات والعضوية.';

  @override
  String get pushMuteAllLabel => 'كتم جميع إشعارات الجوال';

  @override
  String get pushMuteAllSubtitle =>
      'لن يصل شيء إلى جوالك. سجل الإشعارات داخل التطبيق لا يتغير.';

  @override
  String get pushSaveFailed => 'تعذر حفظ هذا الخيار. حاول مرة أخرى.';

  @override
  String get matchManagementTitle => 'إدارة المباراة';

  @override
  String get editMatchTitle => 'تعديل المباراة';

  @override
  String get managePlayersTitle => 'إدارة اللاعبين';

  @override
  String get manageReserveTitle => 'إدارة قائمة الاحتياط';

  @override
  String get matchTitleLabel => 'عنوان المباراة';

  @override
  String get matchDescriptionLabel => 'الوصف';

  @override
  String get reducePlayersNote =>
      'عند تقليل عدد اللاعبين الأساسيين يُنقل آخر المسجّلين إلى قائمة الاحتياط ويُشعَرون بذلك.';

  @override
  String get saveButton => 'حفظ';

  @override
  String get matchUpdatedSaved =>
      'تم تعديل المباراة وإشعار اللاعبين المسجّلين.';

  @override
  String get matchUpdateFailed => 'فشل حفظ المباراة. حاول مرة أخرى.';

  @override
  String get deleteMatchButton => 'حذف المباراة';

  @override
  String get deleteMatchHint =>
      'يتم إشعار اللاعبين المسجّلين. حذف مباراة منتهية يلغي أيضاً كل الإحصائيات والتقييمات التي نتجت عن نتيجتها.';

  @override
  String get deleteMatchConfirmTitle => 'حذف هذه المباراة؟';

  @override
  String get deleteMatchConfirmBody =>
      'ستُحذف جميع التسجيلات ويُشعَر اللاعبون. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get removePlayerButton => 'إزالة';

  @override
  String get removePlayerConfirmTitle => 'إزالة اللاعب؟';

  @override
  String removePlayerConfirmBody(String name) {
    return 'إزالة $name من المباراة؟';
  }

  @override
  String get rosterEmpty => 'لا يوجد لاعبون هنا بعد.';

  @override
  String get errMatchCompleted => 'المباراة منتهية ولم يعد بالإمكان تعديلها.';

  @override
  String get errNotAuthorized => 'منظّم المباراة فقط يمكنه هذا الإجراء.';

  @override
  String get errRegistrationClosed =>
      'التسجيل مغلق؛ اكتمل الحد الأقصى للمباراة.';

  @override
  String get errMatchLocked => 'بدأت المباراة وهي مقفلة حتى انتهائها.';

  @override
  String get matchLockedNote =>
      'بدأت المباراة. التسجيل والانسحاب وتعديل القائمة مقفلة حتى انتهائها.';

  @override
  String get errMaxBelowRegistered =>
      'الحد الأقصى للتسجيل لا يمكن أن يقل عن عدد اللاعبين المسجّلين.';

  @override
  String get networkError => 'تعذر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';

  @override
  String get loadFailed => 'فشل تحميل البيانات.';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get genericError => 'حدث خطأ غير متوقع. حاول مرة أخرى.';

  @override
  String get roleOwner => 'المالك';

  @override
  String get roleAdmin => 'مشرف';

  @override
  String get rolePlayer => 'لاعب';

  @override
  String get manageMembersTitle => 'إدارة الأعضاء';

  @override
  String get searchPlayersLabel => 'البحث بالاسم';

  @override
  String get searchPlayersHint => 'اكتب حرفين على الأقل';

  @override
  String get searchNoResults => 'لا يوجد لاعبون مطابقون.';

  @override
  String get inviteAsRoleLabel => 'الدعوة بصفة';

  @override
  String get invitationSent => 'تم إرسال الدعوة.';

  @override
  String get myInvitationsEmpty => 'لا توجد دعوات.';

  @override
  String get invitationAccepted => 'تم انضمامك للمجتمع.';

  @override
  String get invitationRevoked => 'تم إلغاء الدعوة.';

  @override
  String get promoteToAdminButton => 'تعيين مشرفاً';

  @override
  String get demoteToPlayerButton => 'إعادة إلى لاعب';

  @override
  String get transferOwnershipButton => 'نقل الملكية';

  @override
  String get removeMemberButton => 'إزالة من المجتمع';

  @override
  String get memberRoleChanged => 'تم تحديث صلاحية العضو.';

  @override
  String get ownershipTransferred => 'تم نقل الملكية. أنت الآن مشرف.';

  @override
  String get memberRemoved => 'تمت إزالة العضو من المجتمع.';

  @override
  String get transferOwnershipConfirmTitle => 'نقل الملكية؟';

  @override
  String transferOwnershipConfirmBody(String name) {
    return 'سيصبح $name المالك وستصبح أنت مشرفاً. المالك الجديد وحده يمكنه إعادتها.';
  }

  @override
  String get removeMemberConfirmTitle => 'إزالة هذا العضو؟';

  @override
  String removeMemberConfirmBody(String name) {
    return 'ستتم إزالة $name من المجتمع وسحبه من جميع مبارياته.';
  }

  @override
  String get deleteCommunityButton => 'حذف المجتمع';

  @override
  String get deleteCommunityConfirmTitle => 'حذف هذا المجتمع؟';

  @override
  String get deleteCommunityConfirmBody =>
      'ستُحذف جميع المباريات والتسجيلات والأعضاء والدعوات. لا يمكن التراجع.';

  @override
  String get communityDeleted => 'تم حذف المجتمع.';

  @override
  String get permissionOwnerOnly => 'المالك وحده يمكنه القيام بذلك.';

  @override
  String get permissionOrganizersOnly =>
      'المالك والمشرفون فقط يمكنهم القيام بذلك.';

  @override
  String get matchCreateOrganizersOnly =>
      'إنشاء المباريات متاح للمالك والمشرفين فقط في هذا المجتمع.';

  @override
  String get matchManageOrganizersOnly =>
      'إدارة المباراة أصبحت مرتبطة بصلاحيات المجتمع. تواصل مع مالك أو مشرف فيه.';

  @override
  String get errCannotChangeOwnRole => 'لا يمكنك تغيير صلاحيتك الخاصة.';

  @override
  String get errCannotRemoveSelf =>
      'لا يمكنك إزالة نفسك من هنا. استخدم مغادرة المجتمع.';

  @override
  String get errCannotRemoveOwner =>
      'لا يمكن إزالة المالك. انقل الملكية أولاً.';

  @override
  String get errAlreadyOwner => 'هذا العضو هو المالك بالفعل.';

  @override
  String get errMemberNotFound => 'هذا الشخص ليس عضواً في هذا المجتمع.';

  @override
  String get errInvalidRole => 'لا يمكن تعيين هذه الصلاحية.';

  @override
  String get inviteTitle => 'دعوة';

  @override
  String get inviteLoadError =>
      'تعذّر فتح هذه الدعوة. تحقّق من الاتصال وحاول مرة أخرى.';

  @override
  String get inviteNotFound => 'لم نعثر على هذه الدعوة. قد يكون الرابط ناقصاً.';

  @override
  String get inviteJoinCommunity => 'انضم إلى المجتمع';

  @override
  String get inviteSignInFirst => 'سجّل الدخول أو أنشئ حساباً للانضمام.';

  @override
  String get inviteAlreadyMemberNote => 'أنت عضو في هذا المجتمع بالفعل.';

  @override
  String get shareInvitation => 'مشاركة دعوة';

  @override
  String get inviteLinkCopied => 'نُسخت الدعوة. الصقها حيث تريد مشاركتها.';

  @override
  String inviteShareCommunityBody(String community, String link) {
    return 'انضم إلى $community على Go Play:\n$link';
  }

  @override
  String get errNotCommunityMember => 'أنت لست عضواً في هذا المجتمع.';

  @override
  String get copyLinkButton => 'نسخ';

  @override
  String matchCapacityLabel(int count) {
    return '👥 $count لاعبًا';
  }

  @override
  String get matchTitleRequired => 'عنوان المباراة مطلوب';

  @override
  String get communityInvitationTitle => 'الدعوة';

  @override
  String get communityInvitationHelp =>
      'كل من يملك هذا الرابط أو الرمز يمكنه الانضمام إلى المجتمع. وكلاهما يحمل الرمز نفسه.';

  @override
  String get inviteLinkLabel => 'رابط الدعوة';

  @override
  String get copyJoinCodeButton => 'نسخ الرمز';

  @override
  String get inviteOpenCommunity => 'فتح المجتمع';

  @override
  String get inviteOpenAction => 'فتح دعوة';

  @override
  String get invitePasteHint => 'الصق رابط الدعوة أو الرمز';

  @override
  String get inviteInvalidInput => 'هذا ليس رابط دعوة ولا رمزاً.';

  @override
  String get regenerateJoinCodeButton => 'تجديد الرمز';

  @override
  String get regenerateJoinCodeConfirmTitle => 'تجديد رمز الانضمام؟';

  @override
  String get regenerateJoinCodeConfirmBody =>
      'سيتوقف الرابط والرمز الحاليان فوراً، فلن يتمكن من يملكهما من الانضمام. من هم أعضاء فعلاً يبقون أعضاء.';

  @override
  String get joinCodeRegenerated => 'صدر رمز جديد. القديم لم يعد يعمل.';

  @override
  String get joinPolicyLabel => 'الانضمام';

  @override
  String get joinPolicyOpen => 'انضمام مفتوح';

  @override
  String get joinPolicyOpenHelp => 'يمكن لأي شخص الانضمام من قائمة المجتمعات.';

  @override
  String get joinPolicyCodeRequired => 'انضمام برمز';

  @override
  String get joinPolicyCodeRequiredHelp =>
      'يحتاج الناس إلى رمز الانضمام، أو رابط دعوة يحمله.';

  @override
  String get joinPolicySaved => 'حُدّثت طريقة الانضمام.';

  @override
  String get joinCodeRequiredPrompt => 'هذا المجتمع يحتاج رمز الانضمام.';

  @override
  String get adminTitle => 'الإدارة';

  @override
  String get adminUsersTab => 'المستخدمون';

  @override
  String get adminCommunitiesTab => 'المجتمعات';

  @override
  String get adminMatchesTab => 'المباريات';

  @override
  String get adminSearchLabel => 'بحث';

  @override
  String get adminEmpty => 'لا توجد نتائج.';

  @override
  String get adminDeleteButton => 'حذف';

  @override
  String get adminDeleted => 'حُذف.';

  @override
  String adminDeleteConfirmTitle(String name) {
    return 'حذف $name؟';
  }

  @override
  String get adminDeleteUserConfirmBody =>
      'يُحذف الحساب وكل ما يتبعه: المجتمعات التي يملكها، والمباريات التي أنشأها، والعضويات والتسجيلات. لا يمكن التراجع.';

  @override
  String get adminDeleteCommunityConfirmBody =>
      'يُحذف المجتمع وكل ما تحته: المباريات والعضويات والتسجيلات. لا يمكن التراجع.';

  @override
  String get adminDeleteMatchConfirmBody =>
      'تُحذف المباراة وتسجيلاتها، ويُبلَّغ المسجّلون. لا يمكن التراجع.';

  @override
  String get teamsTitle => 'الفريقان';

  @override
  String get teamsEmpty => 'لم تُنشأ فرق هذه المباراة بعد.';

  @override
  String get generateTeamsButton => 'إنشاء الفرق';

  @override
  String get regenerateTeamsButton => 'إعادة إنشاء الفرق';

  @override
  String get regenerateTeamsConfirmTitle => 'إعادة إنشاء الفرق؟';

  @override
  String get regenerateTeamsConfirmBody =>
      'تُستبدل الفرق الحالية بتوزيع جديد للاعبين المؤكدين.';

  @override
  String get teamsGenerated => 'أُنشئت الفرق.';

  @override
  String get teamAName => 'الفريق أ';

  @override
  String get teamBName => 'الفريق ب';

  @override
  String get teamsOutOfPosition => 'خارج مركزه';

  @override
  String teamsPlayerRangeNote(int min, int max, int count) {
    return 'إنشاء الفرق يحتاج من $min إلى $max لاعباً مؤكداً. في هذه المباراة $count.';
  }

  @override
  String get errMissingPlayerInputs =>
      'بعض اللاعبين المؤكدين ملفهم غير مكتمل. كل واحد منهم يحتاج تاريخ ميلاد قبل إنشاء الفرق.';

  @override
  String get errTeamsNotGenerated => 'تعذّر إنشاء الفرق من هذه القائمة.';

  @override
  String editPlayerTitle(String player) {
    return 'تعديل $player';
  }

  @override
  String get movePlayerAction => 'نقل إلى الفريق الآخر';

  @override
  String get swapPlayerAction => 'تبديل مع لاعب';

  @override
  String get changePositionAction => 'تغيير المركز';

  @override
  String get swapPlayerTitle => 'التبديل مع';

  @override
  String get swapNobodyAvailable =>
      'لا يوجد في الفريق الآخر من يمكن التبديل معه.';

  @override
  String get changePositionTitle => 'المركز في هذه المباراة';

  @override
  String get lineupUpdated => 'حُدّثت التشكيلة.';

  @override
  String get errLineupRefused =>
      'رُفض هذا التغيير. لا يمكن أن يضم فريق حارسَي مرمى.';

  @override
  String get errLineupNotChanged =>
      'هذا التغيير لم يعد ينطبق على هذه التشكيلة. أُعيد تحميلها.';

  @override
  String get matchResultTitle => 'نتيجة المباراة';

  @override
  String get saveResultButton => 'حفظ النتيجة';

  @override
  String get resultSaved => 'تم حفظ نتيجة المباراة بنجاح';

  @override
  String get resultOrganizersOnly =>
      'تسجيل نتيجة المباراة متاح لمالك المجتمع والمشرفين فقط.';

  @override
  String get mvpLabel => 'أفضل لاعب';

  @override
  String get addGoalLabel => 'إضافة هدف';

  @override
  String get removeGoalLabel => 'حذف هدف';

  @override
  String goalsScoredLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count هدفاً',
      few: '$count أهداف',
      two: 'هدفان',
      one: 'هدف واحد',
      zero: 'لا أهداف',
    );
    return '$_temp0';
  }

  @override
  String goalsRecordedNote(int recorded, int total) {
    return 'أُسند $recorded من $total هدفاً إلى مسجّليها.';
  }

  @override
  String get editResultConfirmTitle => 'استبدال النتيجة المسجّلة؟';

  @override
  String get editResultConfirmBody =>
      'تُعكس التقييمات والإحصائيات الناتجة عن النتيجة السابقة، ثم تُطبَّق النتيجة الجديدة بدلاً منها.';

  @override
  String get errGoalsDoNotMatchScore =>
      'مجموع الأهداف المسندة إلى المسجّلين يجب أن يساوي النتيجة النهائية.';

  @override
  String get errMvpNotParticipant =>
      'أفضل لاعب يجب أن يكون أحد لاعبي هذه المباراة.';

  @override
  String get errScorerNotParticipant =>
      'لا يمكن إسناد هدف إلا إلى لاعب شارك في هذه المباراة.';

  @override
  String get errResultNeedsLineup =>
      'لم تُولَّد فرق هذه المباراة بعد. تحتاج النتيجة إلى معرفة فريق كل لاعب.';

  @override
  String get errInvalidResultNumbers =>
      'تعذّر حفظ النتيجة. تحقّق من النتيجة ومن الأهداف.';

  @override
  String get dashboardTab => 'لوحة المعلومات';

  @override
  String get communityStatisticsTitle => 'إحصائيات المجتمع';

  @override
  String get statTotalMatches => 'إجمالي المباريات';

  @override
  String get statTotalPlayers => 'إجمالي اللاعبين';

  @override
  String get statTotalGoals => 'إجمالي الأهداف';

  @override
  String get statLeadersTitle => 'المتصدّرون';

  @override
  String get statTopScorer => 'الهدّاف';

  @override
  String get statMostActivePlayer => 'الأكثر مشاركة';

  @override
  String get statMostMvp => 'الأكثر اختياراً كأفضل لاعب';

  @override
  String get statNoneYet => 'لا يوجد بعد';

  @override
  String get statFormerPlayer => 'لاعب سابق';

  @override
  String statMatchesPlayedValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مباراة',
      few: '$count مباريات',
      two: 'مباراتان',
      one: 'مباراة واحدة',
      zero: 'لا مباريات',
    );
    return '$_temp0';
  }

  @override
  String statMvpValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مرة',
      few: '$count مرات',
      two: 'مرتان',
      one: 'مرة واحدة',
      zero: 'لم يحدث',
    );
    return '$_temp0';
  }

  @override
  String get statScopeNote =>
      'تُحتسب إحصائيات اللاعبين من المباريات المسجَّلة نتائجها، بينما يشمل إجمالي المباريات كل مباراة أنشأها المجتمع.';

  @override
  String get statEmptyBody =>
      'لم تُسجَّل أي نتيجة في هذا المجتمع بعد. تظهر الإحصائيات بمجرّد حفظ نتيجة مباراة.';

  @override
  String get playerStatisticsTitle => 'إحصائياتي';

  @override
  String get statCurrentRating => 'التقييم الحالي';

  @override
  String get statMatchesPlayed => 'المباريات المُلعوبة';

  @override
  String get statWins => 'الانتصارات';

  @override
  String get statDraws => 'التعادلات';

  @override
  String get statLosses => 'الخسارات';

  @override
  String get statGoals => 'الأهداف';

  @override
  String get statMvpCount => 'مرات أفضل لاعب';

  @override
  String get statCareerNote =>
      'سجلّك في كل المجتمعات التي تلعب فيها. يضبط التطبيق هذه الأرقام عند تسجيل نتيجة مباراة، وتُحتسب من المباريات المحفوظة نتائجها.';

  @override
  String get statNoMatchesYet =>
      'لم تلعب بعد أي مباراة مسجَّلة النتيجة. تبدأ أرقامك من الصفر، والتقييم هو التقييم الابتدائي الذي يبدأ به كل لاعب.';

  @override
  String get leaderboardsTab => 'لوحات الصدارة';

  @override
  String get leaderboardHighestRated => 'الأعلى تقييماً';

  @override
  String get leaderboardTopScorer => 'الهدّاف';

  @override
  String get leaderboardMostMvp => 'الأكثر اختياراً كأفضل لاعب';

  @override
  String get leaderboardMostActive => 'الأكثر مشاركة';

  @override
  String get leaderboardMostWins => 'الأكثر فوزاً';

  @override
  String get leaderboardsEmpty =>
      'لا توجد لوحات صدارة بعد. بمجرّد تسجيل نتيجة مباراة، سيظهر هنا من يتصدّر المجتمع.';

  @override
  String get leaderboardRatingNote =>
      'يعتمد ترتيب «الأعلى تقييماً» على التقييم العام للاعب في كل المجتمعات.';

  @override
  String get cancelButton => 'إلغاء';

  @override
  String get changeAction => 'تغيير';

  @override
  String get editProfileTitle => 'تعديل الملف الشخصي';

  @override
  String get editProfileAction => 'تعديل الملف الشخصي';

  @override
  String get profilePersonalSection => 'المعلومات الشخصية';

  @override
  String get profileAccountSection => 'الحساب';

  @override
  String get profilePlayingSection => 'الملف الرياضي';

  @override
  String get passwordHiddenNote => 'مخفية لحماية حسابك';

  @override
  String get changeEmailTitle => 'تغيير البريد الإلكتروني';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get confirmPasswordLabel => 'تأكيد كلمة المرور';

  @override
  String get passwordsDoNotMatch => 'كلمتا المرور غير متطابقتين';

  @override
  String get passwordChanged => 'تم تغيير كلمة المرور.';

  @override
  String get emailChangeRequested => 'تحقق من بريدك الجديد لتأكيد التغيير.';

  @override
  String get avatarChangeAction => 'تغيير الصورة';

  @override
  String get avatarSourceCamera => 'التقاط صورة';

  @override
  String get avatarSourceGallery => 'الاختيار من المعرض';

  @override
  String get ageLabel => 'العمر';

  @override
  String get avatarRemoveAction => 'إزالة الصورة';

  @override
  String get avatarUpdated => 'تم تحديث الصورة.';

  @override
  String get avatarRemoved => 'تمت إزالة الصورة.';

  @override
  String get avatarUploadFailed => 'تعذّر تحديث الصورة. حاول مرة أخرى.';

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سنة',
      many: '$count سنة',
      few: '$count سنوات',
      two: 'سنتان',
      one: 'سنة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get logoutConfirmTitle => 'تسجيل الخروج؟';

  @override
  String get logoutConfirmBody =>
      'ستحتاج إلى تسجيل الدخول مجدداً لاستخدام Go Play.';

  @override
  String get completedMatchesTitle => 'المباريات المنتهية';

  @override
  String get addPlayedPlayerAction => 'إضافة لاعب شارك في المباراة';

  @override
  String get addPlayedPlayerNobodyAvailable =>
      'كل أعضاء المجتمع موجودون في التشكيلة.';

  @override
  String get removePlayedPlayerAction => 'إزالة من المباراة';

  @override
  String get removePlayedPlayerConfirmTitle => 'إزالة هذا اللاعب؟';

  @override
  String removePlayedPlayerConfirmBody(String name) {
    return 'سيُزال $name من التشكيلة، وستُسترجع كل الإحصائيات والتقييمات التي منحتها له هذه المباراة.';
  }

  @override
  String get editPlayedMatchNote =>
      'أي تعديل على مباراة منتهية يعيد احتساب الإحصائيات والتقييمات ولوحات الصدارة.';

  @override
  String get chooseTeamTitle => 'أي فريق؟';

  @override
  String get choosePositionTitle => 'أي مركز؟';

  @override
  String get errResultParticipantRemoved =>
      'هذا اللاعب هو أفضل لاعب أو مسجّل هدف في النتيجة المسجّلة. عدّل النتيجة أولاً.';

  @override
  String get errMatchNotCompleted =>
      'لا يمكن تصحيح لاعبي المباراة بهذه الطريقة إلا بعد انتهائها.';

  @override
  String get communityTitle => 'المجتمع';

  @override
  String get discoverHeroTitle => 'كرة القدم أجمل مع مجتمعك.';

  @override
  String get discoverHeroBody =>
      'اكتشف المجتمعات من حولك، وتابع مباريات هذا الأسبوع، واحجز مكانك في الملعب.';

  @override
  String get discoverAlreadyHaveAccount => 'لديك حساب؟ سجّل الدخول';

  @override
  String discoverSeatsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مقاعد متبقية',
      two: 'مقعدان متبقيان',
      one: 'مقعد واحد متبقٍ',
    );
    return '$_temp0';
  }

  @override
  String discoverMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count أعضاء',
      two: 'عضوان',
      one: 'عضو واحد',
      zero: 'لا أعضاء',
    );
    return '$_temp0';
  }

  @override
  String discoverUpcomingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مباريات قادمة',
      two: 'مباراتان قادمتان',
      one: 'مباراة قادمة',
    );
    return '$_temp0';
  }

  @override
  String get discoverNoUpcomingMatches =>
      'لا توجد مباريات مجدولة حالياً. عد إلينا قريباً.';

  @override
  String get discoverNoCommunities =>
      'لا توجد مجتمعات بعد. كن أول من ينشئ واحداً.';

  @override
  String get discoverCtaTitle => 'جاهز للعب؟';

  @override
  String get discoverCtaBody =>
      'أنشئ حساباً للانضمام إلى المجتمعات، والتسجيل في المباريات، وبدء مجتمعك الخاص.';

  @override
  String get authRequiredTitle => 'تحتاج إلى حساب';

  @override
  String get authRequiredJoinCommunity =>
      'أنشئ حساباً للانضمام إلى هذا المجتمع.';

  @override
  String get authRequiredRegisterMatch =>
      'أنشئ حساباً للتسجيل في هذه المباراة.';

  @override
  String get authRequiredCreateCommunity => 'أنشئ حساباً لبدء مجتمعك الخاص.';

  @override
  String get mvpOptionalNote =>
      'اضغط على النجمة لاختيار أفضل لاعب. هذا اختياري — يمكنك حفظ النتيجة بدونه.';

  @override
  String get navDiscover => 'استكشف';

  @override
  String get viewCommunityAction => 'عرض المجتمع';

  @override
  String get viewMatchAction => 'عرض المباراة';

  @override
  String discoverWelcomeBack(String name) {
    return 'أهلاً بعودتك، $name';
  }

  @override
  String get discoverHeroBodySignedIn =>
      'تابع ما تلعبه مجتمعاتك هذا الأسبوع، واكتشف مجتمعات جديدة للانضمام إليها.';

  @override
  String discoverCommunityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مجتمعات',
      two: 'مجتمعان',
      one: 'مجتمع واحد',
      zero: 'لا مجتمعات',
    );
    return '$_temp0';
  }

  @override
  String get discoverCtaTitleSignedIn => 'ابدأ مجتمعك الخاص';

  @override
  String get discoverCtaBodySignedIn =>
      'أنشئ مجتمعاً واجمع مباراتك المعتادة في مكان واحد.';

  @override
  String get discoverMatchesSubtitle => 'مباريات ما زالت فيها مقاعد';

  @override
  String get discoverCommunitiesSubtitle => 'مجتمعات يمكنك الانضمام إليها';

  @override
  String get homeUpcomingSubtitle => 'من جميع مجتمعاتك';
}
