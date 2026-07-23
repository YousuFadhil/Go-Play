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
  String get navGroups => 'المجموعات';

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
  String get groupsTitle => 'المجموعات';

  @override
  String get groupsEmpty =>
      'لست عضواً في أي مجموعة بعد.\nأنشئ مجموعة أو انضم برمز الانضمام.';

  @override
  String get createGroupTitle => 'إنشاء مجموعة';

  @override
  String get createGroupButton => 'إنشاء المجموعة';

  @override
  String get joinGroupTitle => 'الانضمام لمجموعة';

  @override
  String get joinGroupButton => 'انضمام';

  @override
  String get groupNameLabel => 'اسم المجموعة';

  @override
  String get groupNameRequired => 'اسم المجموعة مطلوب';

  @override
  String get groupDescriptionLabel => 'الوصف (اختياري)';

  @override
  String get privateGroupLabel => 'مجموعة خاصة';

  @override
  String get privateGroupHelp =>
      'المجموعات الخاصة لا يمكن الانضمام إليها إلا برمز الانضمام.';

  @override
  String get joinCodeLabel => 'رمز الانضمام';

  @override
  String get joinCodeRequired => 'رمز الانضمام مطلوب';

  @override
  String get groupNotFound => 'لا توجد مجموعة بهذا الرمز.';

  @override
  String get alreadyMember => 'أنت عضو في هذه المجموعة بالفعل.';

  @override
  String get groupCreateFailed => 'فشل إنشاء المجموعة. حاول مرة أخرى.';

  @override
  String get groupJoinFailed => 'فشل الانضمام للمجموعة. حاول مرة أخرى.';

  @override
  String get membersTitle => 'الأعضاء';

  @override
  String get ownerBadge => 'المالك';

  @override
  String get joinCodeCopied => 'تم نسخ رمز الانضمام';

  @override
  String get myGroupsSection => 'مجموعاتي';

  @override
  String get publicGroupsSection => 'المجموعات العامة';

  @override
  String get joinedGroup => 'تم انضمامك للمجموعة.';

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
  String get maxRegistrationInvalid => 'أدخل رقماً بين 2 و 60';

  @override
  String get capacityInvalid =>
      'الحد الأقصى للتسجيل يجب أن يكون أكبر من أو يساوي عدد اللاعبين الأساسيين';

  @override
  String get matchCreateFailed => 'فشل إنشاء المباراة. حاول مرة أخرى.';

  @override
  String get groupMatchesEmpty => 'لا توجد مباريات في هذه المجموعة بعد.';

  @override
  String get upcomingMatchesTitle => 'المباريات القادمة';

  @override
  String get upcomingMatchesEmpty =>
      'لا توجد مباريات قادمة.\nانضم لمجموعة وأنشئ مباراة للبدء.';

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
  String get errNotOrganizer => 'منظّم المباراة فقط يمكنه هذا الإجراء.';

  @override
  String get errRegistrationClosed =>
      'التسجيل مغلق؛ اكتمل الحد الأقصى للمباراة.';

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
}
