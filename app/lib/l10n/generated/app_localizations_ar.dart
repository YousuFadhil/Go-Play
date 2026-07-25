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
  String get homeTitle => 'الرئيسية';

  @override
  String get logoutLabel => 'تسجيل الخروج';

  @override
  String get welcomeMessage => 'تم تسجيل الدخول بنجاح';

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
  String get privateCommunityLabel => 'مجتمع خاص';

  @override
  String get privateCommunityHelp =>
      'المجتمعات الخاصة لا يمكن الانضمام إليها إلا برمز الانضمام.';

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
  String get ownerBadge => 'المالك';

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
  String get startingPlayersInvalid => 'أدخل رقماً بين 2 و 30';

  @override
  String get maxRegistrationLabel => 'الحد الأقصى للتسجيل';

  @override
  String capacityAutoNote(int reserve, int max) {
    return 'لاعبو الاحتياط: $reserve (تلقائي) — الحد الأقصى للتسجيل: $max';
  }

  @override
  String get matchCreateFailed => 'فشل إنشاء المباراة. حاول مرة أخرى.';

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
  String get confirmYes => 'نعم';

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
  String get matchManagementTitle => 'إدارة المباراة';

  @override
  String get editMatchTitle => 'تعديل المباراة';

  @override
  String get managePlayersTitle => 'إدارة اللاعبين';

  @override
  String get manageReserveTitle => 'إدارة قائمة الاحتياط';

  @override
  String get matchTitleLabel => 'عنوان المباراة (اختياري)';

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
      'يتم إشعار اللاعبين المسجّلين. لا يمكن حذف المباريات المنتهية.';

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
  String get manageCommunityTitle => 'إدارة المجتمع';

  @override
  String get manageMembersTitle => 'إدارة الأعضاء';

  @override
  String get invitationsTitle => 'الدعوات';

  @override
  String get myInvitationsTitle => 'دعواتي';

  @override
  String get pendingInvitationsTitle => 'الدعوات المعلقة';

  @override
  String get inviteMemberTitle => 'دعوة لاعب';

  @override
  String get inviteButton => 'دعوة';

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
  String get invitationsEmpty => 'لا توجد دعوات معلقة.';

  @override
  String get myInvitationsEmpty => 'لا توجد دعوات.';

  @override
  String invitationFrom(String community) {
    return 'دعوة للانضمام إلى $community';
  }

  @override
  String get acceptInvitationButton => 'قبول';

  @override
  String get revokeInvitationButton => 'إلغاء';

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
  String get deleteCommunityHint =>
      'يحذف المجتمع مع جميع مبارياته وأعضائه ودعواته.';

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
  String get errInvitationExists => 'توجد دعوة معلقة لهذا اللاعب بالفعل.';

  @override
  String get errInvitationNotFound => 'هذه الدعوة لم تعد موجودة.';

  @override
  String get errInvitationNotPending => 'هذه الدعوة استُخدمت مسبقاً.';

  @override
  String get errInvitationExpired => 'انتهت صلاحية هذه الدعوة.';

  @override
  String get errInvalidRole => 'لا يمكن تعيين هذه الصلاحية.';

  @override
  String get leaveCommunityButton => 'مغادرة المجتمع';

  @override
  String get leaveCommunityConfirmTitle => 'مغادرة هذا المجتمع؟';

  @override
  String get leaveCommunityConfirmBody =>
      'ستفقد الوصول إلى مبارياته. يمكنك الانضمام مجدداً برمز الانضمام.';

  @override
  String get leftCommunity => 'غادرت المجتمع.';

  @override
  String get ownerCannotLeave => 'لا يمكن للمالك المغادرة. انقل الملكية أولاً.';
}
