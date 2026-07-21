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
  String get phoneLabel => 'رقم الجوال';

  @override
  String get phoneHint => 'مثال: 9665xxxxxxxx (مع رمز الدولة)';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get phoneRequired => 'رقم الجوال مطلوب';

  @override
  String get phoneInvalid => 'أدخل رقم جوال صحيح مع رمز الدولة';

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
      'فشل تسجيل الدخول. تحقق من رقم الجوال وكلمة المرور.';

  @override
  String get noAccountPrompt => 'ليس لديك حساب؟ إنشاء حساب';

  @override
  String get registerTitle => 'إنشاء حساب';

  @override
  String get registerButton => 'إنشاء الحساب';

  @override
  String get registerFailed => 'فشل إنشاء الحساب. حاول مرة أخرى.';

  @override
  String get phoneAlreadyUsed => 'رقم الجوال مسجل مسبقاً.';

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
  String get maxPlayersLabel => 'الحد الأقصى للاعبين';

  @override
  String get maxPlayersInvalid => 'أدخل رقماً بين 2 و 30';

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
  String get matchStatusCancelled => 'ملغاة';

  @override
  String get matchStatusCompleted => 'منتهية';

  @override
  String get playersCountLabel => 'اللاعبون';

  @override
  String get cancelMatchButton => 'إلغاء المباراة';

  @override
  String get cancelMatchConfirmTitle => 'إلغاء هذه المباراة؟';

  @override
  String get cancelMatchConfirmBody => 'لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get confirmYes => 'نعم، إلغاء';

  @override
  String get confirmNo => 'رجوع';

  @override
  String get matchCancelFailed => 'فشل إلغاء المباراة. حاول مرة أخرى.';

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
  String get loadFailed => 'فشل تحميل البيانات.';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get genericError => 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}
