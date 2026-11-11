export 'brands.dart';

// قواعد المعرفة: قوائم الدومينات والكلمات المستخدمة في التحليل.
// تقدر تعدّل أي قائمة هنا وتضيف عليها بدون لمس باقي الكود.

const Set<String> kShorteners = <String>{
  'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'is.gd', 'buff.ly',
  'rebrand.ly', 'cutt.ly', 'shorturl.at', 't.ly', 'rb.gy', 'tiny.cc',
  'bl.ink', 'lnkd.in', 's.id', 'v.gd', 'soo.gd', 'clck.ru', 'adf.ly',
  'bit.do', 'shorte.st', 'qrco.de', 'urlz.fr', 'x.co',
};

const Set<String> kRiskyTlds = <String>{
  'zip', 'mov', 'xyz', 'top', 'click', 'country', 'gq', 'tk', 'ml', 'cf',
  'ga', 'work', 'support', 'rest', 'loan', 'icu', 'cyou', 'buzz', 'monster',
  'sbs', 'cfd', 'vip', 'men', 'win', 'bid', 'stream', 'download', 'racing',
  'review', 'date', 'party', 'trade', 'webcam', 'science', 'accountant',
};

// امتدادات الدومين المركّب (co.uk / com.eg ...)
const Set<String> kSecondLevel = <String>{
  'co', 'com', 'org', 'net', 'gov', 'edu', 'ac',
};

// استضافات مجانية/منصات محتوى يستغلها المحتالون كثيرًا
const List<String> kFreeHosts = <String>[
  'sites.google.com', 'docs.google.com', 'forms.gle', 'drive.google.com',
  'storage.googleapis.com', 'firebaseapp.com', 'web.app', 'github.io',
  'netlify.app', 'vercel.app', 'pages.dev', 'workers.dev', 'blogspot.com',
  'weebly.com', 'wixsite.com', 'herokuapp.com', 'glitch.me',
  '000webhostapp.com', 'trycloudflare.com', 'ngrok.io', 'ngrok-free.app',
  'onrender.com', 'repl.co', 'wordpress.com',
];

const List<String> kUrlWords = <String>[
  'login', 'log-in', 'signin', 'sign-in', 'verify', 'verification', 'secure',
  'account', 'update', 'confirm', 'wallet', 'password', 'passwd', 'bank',
  'billing', 'suspend', 'unlock', 'recover', 'restore', 'validate',
  'authenticate', 'otp', 'payment', 'invoice', 'refund', 'gift', 'claim',
  'reward', 'prize', 'pay',
];

const Set<String> kRedirectParams = <String>{
  'url', 'u', 'redirect', 'redirect_uri', 'redirecturl', 'next', 'continue',
  'return', 'returnurl', 'dest', 'destination', 'goto', 'link', 'target', 'r',
};

const List<String> kDangerExt = <String>[
  '.apk', '.exe', '.scr', '.bat', '.cmd', '.msi', '.jar', '.vbs', '.js',
  '.ps1', '.lnk', '.iso', '.dmg',
];

const List<String> kArchiveExt = <String>['.zip', '.rar', '.7z'];

// ---------------------------------------------------------------------------
// إشارات الرسائل
// ---------------------------------------------------------------------------
//
// المبادئ (مهمة عند التعديل):
//  - كل مفهوم (استعجال، تهديد، دفع...) إشارة واحدة بكود ثابت msg_<id>؛ لو اتذكر بالعربي
//    والإنجليزي في نفس الرسالة بيتحسب مرة واحدة. مفيش نقاط زيادة على عدد الكلمات.
//  - كل مفهوم لازم تكون عباراته متكافئة في اللغتين (عربي/إنجليزي).
//  - [SignalDef.words] عبارات قوية: وجود واحدة منها كفاية لإشارة بوزن [SignalDef.weight].
//  - [SignalDef.soft] كلمات عامة بتظهر في رسائل عادية كتير (login, account, bank, invoice,
//    البنك, فاتورة...). لوحدها بتدّي نقاط قليلة كإشارة "ضعيفة" مجموعها محدود (kWeakFamilyCap)،
//    يعني ما توصّلش رسالة عادية لمستوى "مشبوه".
//  - الكلمات بتتطابق على نص موحّد (بدون تشكيل، ألف/ياء/تاء مربوطة موحّدة). الكلمة اللي
//    بتبدأ بـ "re:" تعبير نمطي جاهز على النص الموحّد.

class SignalDef {
  const SignalDef({
    required this.id,
    required this.title,
    required this.detail,
    required this.weight,
    this.words = const <String>[],
    this.soft = const <String>[],
    this.softWeight = 3,
  });

  final String id;
  final String title;
  final String detail;

  /// وزن الإشارة لو طابقت عبارة قوية.
  final int weight;

  /// عبارات قوية (عربي + إنجليزي).
  final List<String> words;

  /// كلمات عامة: لوحدها إشارة ضعيفة بـ [softWeight] نقطة.
  final List<String> soft;
  final int softWeight;
}

const List<SignalDef> kSignals = <SignalDef>[
  SignalDef(
    id: 'urgency',
    title: 'استعجال وضغط نفسي',
    detail: 'المحتال يحاول يخليك تتصرف بسرعة قبل ما تفكّر أو تتأكد.',
    weight: 12,
    words: <String>[
      // عربي
      'فورا', 'عاجل', 'عاجلا', 'خلال 24 ساعة', 'خلال 48 ساعة', 'خلال ساعتين',
      'خلال ساعة', 'اخر فرصة', 'اخر تحذير', 'انذار اخير', 'قبل فوات الاوان',
      'ينتهي اليوم', 'قبل انتهاء', 'في الحال',
      // English
      'urgent', 'urgently', 'immediately', 'asap', 'within 24 hours',
      'within 48 hours', 'within 2 hours', 'last chance', 'final notice',
      'final warning', 'act now', 'expires today', 'right away',
      'before it expires',
    ],
    soft: <String>[
      'الان', 'حالا', 'بسرعة', 'ضروري', 'دلوقتي',
      'right now', 'quickly', 'as soon as possible', 'hurry',
    ],
  ),
  SignalDef(
    id: 'threat',
    title: 'تهديد بإيقاف أو حظر',
    detail: 'التهديد بإغلاق الحساب أو الغرامة أسلوب شائع لدفعك للضغط على الرابط.',
    weight: 16,
    words: <String>[
      // عربي
      'تم ايقاف حسابك', 'سيتم ايقاف', 'ايقاف حسابك', 'ايقاف خطك', 'ايقاف بطاقتك',
      'تعليق حسابك', 'تم تعليق حسابك', 'سيتم تعليق', 'تم حظر حسابك', 'سيتم حظر',
      'حظر حسابك', 'اغلاق حسابك', 'سيتم اغلاق', 'تم تجميد', 'تجميد حسابك',
      'نشاط مشبوه', 'عملية مشبوهة', 'محاولة دخول', 'تم اختراق', 'اجراء قانوني',
      'بلاغ ضدك', 'سيتم نشر بياناتك', 'ابتزاز',
      // English
      'account suspended', 'account has been suspended', 'account is suspended',
      'account will be suspended', 'account locked', 'account has been locked',
      'account is locked', 'account will be closed', 'account has been limited',
      'account limited', 'account restricted', 'account has been restricted',
      'unauthorized access', 'unauthorized login', 'unauthorized transaction',
      'suspicious activity', 'suspicious login', 'unusual activity',
      'unusual sign-in', 'unusual sign in', 'security alert', 'legal action',
      'arrest warrant', 'outstanding fine', 'has been compromised',
      'will be terminated', 'blackmail',
    ],
    soft: <String>[
      'ايقاف', 'حظر', 'تعليق',
      'suspended', 'locked', 'blocked', 'terminated', 'compromised',
    ],
  ),
  SignalDef(
    id: 'prize',
    title: 'جائزة أو مبلغ مستحق غير متوقع',
    detail: 'لو ما اشتركتش في سحب أو ما كنتش منتظر استرداد، فالأغلب إنها خدعة.',
    weight: 18,
    words: <String>[
      // عربي
      'ربحت', 'فزت', 'تم اختيارك', 'هدية مجانية', 'مبلغ مستحق', 'ورثة',
      'تم اختيار رقمك', 'سحب على جوائز',
      // English
      'you won', 'you have won', 'you are a winner', 'lottery', 'free gift',
      'claim your', 'sweepstakes', 'unclaimed funds', 'next of kin',
      'inheritance', 'grant approved', 'you have been selected',
    ],
    soft: <String>[
      'مبروك', 'جائزة', 'استرداد', 'كاش باك', 'فائز',
      'congratulations', 'winner', 'prize', 'refund', 'cashback', 'beneficiary',
    ],
  ),
  SignalDef(
    id: 'payment',
    title: 'طلب دفع أو تحويل أموال',
    detail: 'احذر من أي رسوم أو تحويل يُطلب عبر رابط أو بطاقة هدايا أو محفظة.',
    weight: 10,
    words: <String>[
      // عربي
      'ادفع', 'ادفعي', 'دفع رسوم', 'سدد الرسوم', 'سداد الرسوم', 'حول مبلغ',
      'تحويل مبلغ', 'حول لي', 'محتاج تحويل', 'ارسل مبلغ', 'اعادة المبلغ',
      'رد المبلغ', 'رسوم الشحن', 'رسوم التوصيل', 'رسوم جمركية', 'رسوم الافراج',
      'رسوم تسجيل', 'رسوم الاشتراك', 'التسجيل برسوم', 'بطاقة هدايا', 'كارت هدايا',
      'فشلت عملية الدفع', 'فشل الدفع', 'سداد الفاتورة',
      're:تحويل.{0,40}بالخطا',
      // English
      'pay now', 'pay the fee', 'pay a fee', 'pay a small fee', 'processing fee',
      'customs fee', 'release fee', 'registration fee', 'joining fee',
      'wire transfer', 'western union', 'send money', 'send me money',
      'i need money', 'gift card', 'itunes card', 'google play card',
      'steam card', 'payment failed', 'payment declined', 'overdue payment',
      'outstanding balance', 'send back the money', 'return the money',
      're:(?:sent|transferred|deposited).{0,30}by mistake',
      're:\\bpay (?:a |the |an )?[\\d.,]+ ?(?:egp|usd|eur|gbp|\\\$)',
    ],
    soft: <String>[
      'رسوم', 'فاتورة', 'فودافون كاش', 'انستاباي', 'انستا باي', 'اورنج كاش',
      'اتصالات كاش', 'وي باي', 'شحن الخط', 'كود الشحن', 'سداد', 'عملة رقمية',
      'invoice', 'fee', 'payment', 'bitcoin', 'crypto', 'usdt',
    ],
    softWeight: 4,
  ),
  SignalDef(
    id: 'delivery',
    title: 'رسالة طرد أو شحنة',
    detail: 'رسائل "تعذر التسليم" و"رسوم شحن" من أكثر أساليب التصيّد انتشارًا.',
    weight: 8,
    words: <String>[
      // عربي
      'تعذر التسليم', 'تعذر توصيل', 'فشل التوصيل', 'فشلت محاولة التسليم',
      'عنوانك غير مكتمل', 'لم نتمكن من توصيل', 'اعادة جدولة التسليم',
      // English
      'could not be delivered', "couldn't be delivered", 'delivery failed',
      'failed delivery', 'delivery attempt', 'unable to deliver',
      'address is incomplete', 'reschedule delivery', 'reschedule your delivery',
    ],
    soft: <String>[
      'طردك', 'شحنتك', 'البريد المصري', 'ارامكس', 'بوسطة', 'رقم التتبع',
      'package', 'parcel', 'tracking number', 'shipment', 'dhl', 'aramex', 'fedex',
    ],
  ),
  SignalDef(
    id: 'utility',
    title: 'تهديد بقطع خدمة أو إيقاف دعم حكومي',
    detail:
        'تهديدات قطع الكهرباء أو إلغاء بطاقة التموين أو إيقاف المعاش عبر رسالة نصية أسلوب نصب منتشر في مصر. الجهات الحكومية لا تطلب الدفع أو البيانات برابط في رسالة.',
    weight: 16,
    words: <String>[
      // عربي
      'قطع الكهرباء', 'فصل الكهرباء', 'سيتم فصل', 'انقطاع التيار',
      'بطاقة التموين', 'البطاقة التموينية', 'الغاء بطاقتك', 'ايقاف الدعم',
      'وقف الدعم', 'تحديث بيانات التموين', 'تحديث البطاقة الذكية',
      'الدعم التمويني', 'وقف المعاش', 'ايقاف المعاش', 'الهيئة القومية للتامين',
      // English
      'electricity will be cut', 'power will be disconnected',
      'electricity will be disconnected', 'ration card', 'subsidy will be',
      'pension will be suspended', 'benefits will be suspended',
      'your benefits have been suspended',
    ],
    soft: <String>[
      'التامينات الاجتماعية', 'معاشك', 'قرار جمهوري', 'منحة',
      'social security', 'pension', 'subsidy', 'government grant',
    ],
  ),
  SignalDef(
    id: 'scheme',
    title: 'عرض ربح أو استثمار مضمون',
    detail: 'لا يوجد ربح مضمون. العروض السريعة المبالغ فيها غالبًا نصب.',
    weight: 14,
    words: <String>[
      // عربي
      'ربح مضمون', 'ارباح مضمونة', 'عائد مضمون', 'دخل يومي', 'ربح يومي',
      'استثمار مضمون', 'عمل من المنزل', 'وظيفة من المنزل', 'شغل من البيت',
      'فرصة شغل', 'مضاعفة اموالك', 'ضاعف اموالك',
      // English
      'guaranteed profit', 'guaranteed returns', 'double your', 'work from home',
      'investment opportunity', 'daily income', 'passive income',
      'make money fast', 'binary options', 'earn money from home',
    ],
    soft: <String>[
      'استثمر', 'توصيات', 'اربح',
      'invest', 'forex', 'trading signals', 'earn',
    ],
  ),
  SignalDef(
    id: 'secrecy',
    title: 'يطلب السرية',
    detail: 'المحتال يطلب منك ألا تخبر أحدًا حتى لا يتدخل أحد وينبّهك.',
    weight: 12,
    words: <String>[
      // عربي
      'لا تخبر', 'بسرية تامة', 'الامر سري', 'لا تتحدث مع احد', 'لا تقل لاحد',
      'ماتقولش لحد', 'متقولش لحد', 'ما تقولش لحد', 'خليها سر', 'خليه سر',
      // English
      'keep this secret', 'keep it secret', 'do not tell', "don't tell",
      'keep it between us', 'tell no one', 'tell nobody',
    ],
    soft: <String>['سري', 'confidential'],
  ),
  SignalDef(
    id: 'impersonation',
    title: 'انتحال شخصية قريب أو معرفة',
    detail:
        'رسالة "رقمي اتغير" أو "أنا ابنك" متبوعة بطلب مال أسلوب نصب شائع. اتصل بالشخص على رقمه القديم قبل أي تحويل.',
    weight: 10,
    words: <String>[
      // عربي
      'رقمي اتغير', 'رقمي الجديد', 'اتغير رقمي', 'انا ابن عمك', 'انا ابنك',
      'انا بنتك', 'فقدت تليفوني', 'موبايلي اتسرق',
      // English
      'my number has changed', 'my number changed', 'this is my new number',
      'i lost my phone', "i'm your son", 'i am your son', "i'm your daughter",
      'i am your daughter',
    ],
  ),
  SignalDef(
    id: 'verify',
    title: 'يطلب توثيق أو تحديث بيانات الحساب',
    detail:
        'طلب "وثّق حسابك" أو "حدّث بياناتك" عبر رسالة هو أساس التصيّد. افتح التطبيق أو الموقع الرسمي بنفسك بدل ما تتبع الرابط.',
    weight: 12,
    words: <String>[
      // عربي
      'تاكيد هويتك', 'تاكيد حسابك', 'توثيق حسابك', 'تحديث بياناتك', 'حدث بياناتك',
      'تحقق من حسابك', 'تحقق من هويتك', 'تفعيل حسابك', 'استعادة حسابك',
      'كلمة المرور منتهية', 'انتهت صلاحية كلمة المرور',
      // English
      'verify your account', 'verify your identity', 'confirm your identity',
      'confirm your account', 'validate your account', 'update your details',
      'update your information', 'update your billing', 'update your password',
      'reactivate your account', 'unlock your account', 'restore access',
      'your password has expired', 'password expires',
    ],
  ),
  SignalDef(
    id: 'cta',
    title: 'يطلب الضغط على رابط أو تسجيل الدخول',
    detail: 'صيغة "اضغط هنا" و"سجّل الدخول" شائعة في رسائل التصيّد، لكنها موجودة كمان في رسائل عادية، فلا تُحتسب لوحدها.',
    weight: 3,
    soft: <String>[
      'اضغط', 'انقر', 'افتح الرابط', 'عبر الرابط', 'من خلال الرابط',
      'سجل الدخول', 'تسجيل الدخول',
      'click here', 'tap here', 'click the link', 'log in', 'login', 'sign in',
      'follow the link',
    ],
  ),
  SignalDef(
    id: 'authority',
    title: 'يذكر جهة رسمية',
    detail: 'ذكر البنك أو الأمن أو الدعم الفني لا يعني أن المرسل منهم فعلًا، ولا يعني أن الرسالة مشبوهة بحد ذاته.',
    weight: 3,
    soft: <String>[
      'البنك', 'الشرطة', 'النيابة', 'مصلحة الضرائب', 'شركة الكهرباء',
      'وزارة التموين', 'مجلس الوزراء', 'هيئة البريد', 'الدعم الفني', 'فريق الدعم',
      'خدمة العملاء',
      'security team', 'support team', 'customer service', 'bank', 'irs',
      'tax office', 'social security administration', 'immigration office',
    ],
  ),
  SignalDef(
    id: 'techsupport',
    title: 'دعم فني وهمي أو تحكم عن بعد',
    detail:
        'شركات التقنية الحقيقية لا تتصل بيك بنفسها تقولك جهازك مصاب. طلب تثبيت برنامج تحكم عن بعد أسلوب نصب لسرقة بياناتك وحساباتك.',
    weight: 20,
    words: <String>[
      // عربي
      'جهازك مصاب', 'فيروس تم اكتشافه', 'تم اكتشاف فيروس', 'جهازك مصاب بفيروس',
      'ثبت برنامج تحكم', 'تثبيت برنامج تحكم',
      // English
      'your computer is infected', 'your device is infected', 'virus detected',
      'install remote access', 'install teamviewer', 'install anydesk',
      'call this number immediately',
    ],
    soft: <String>[
      'تحكم عن بعد', 'دعم مايكروسوفت', 'دعم ابل',
      'remote access', 'remote control', 'teamviewer', 'anydesk',
      'microsoft support', 'apple support',
    ],
    softWeight: 4,
  ),
];

// ---------------------------------------------------------------------------
// طلب بيانات حساسة (كود/كلمة سر/بطاقة): السياق بيحدد، مش وجود الكلمة لوحده.
// الإشارة msg_secret_request بتنطلق بس لو الجملة نفسها فيها (1) مصطلح حساس و(2) فعل طلب
// (ابعت/قولّي/send/share...) و(3) مفيش عبارة تحذير ("لا تشارك"/"do not share").
// ---------------------------------------------------------------------------

const List<String> kSensitiveTerms = <String>[
  // عربي
  'كود التحقق', 'رمز التحقق', 'كود التفعيل', 'رمز التفعيل', 'كود الدخول',
  'الرقم السري', 'الرمز السري', 'كلمة المرور', 'كلمة السر', 'باسورد',
  'الرقم القومي', 'رقمك القومي', 'رقم البطاقة', 'بيانات البطاقة', 'بيانات الكارت',
  'رقم الكارت', 'بيانات حسابك', 'عبارة الاسترداد', 'المفتاح الخاص',
  'الكود اللي وصلك', 'الكود الذي وصلك', 'الكود اللي جالك', 'كود وصلني',
  'كود وصلك', 'رمز وصلك', 'الرقم اللي وصلك',
  'otp', 'cvv', 'cvc',
  // English
  'pin', 'password', 'passcode', 'verification code', 'security code',
  'one-time code', 'one time code', 'confirmation code', 'login code',
  'seed phrase', 'recovery phrase', 'private key', 'social security number',
  'ssn', 'card number', 'card details', 'the code you received', 'code sent to your phone',
  'code you just received', 'code i sent',
];

/// أفعال "سلّم البيانات لي" (ابعت/قولّي/send/share/tell...): طلب البيانات الحساسة فعلًا.
/// تعبيرات نمطية على النص الموحّد. العربي بيقبل سوابق ولواحق (ببعتلك/تبعتهولي).
const String kHandOverVerbsAr =
    r'(?<![\u0621-\u064A])(?:[\u0621-\u064A]{0,2})?(?:ارسل|ابعت|ابعث|بعت|بعث|شارك|قول|اعط|زود|اذكر|اخبر|ارفق|صور)[\u0621-\u064A]*';
const String kHandOverVerbsEn =
    r'(?<![a-z])(?:send|sends|sending|share|sharing|provide|providing|reply|replying|tell|telling|give|giving|read out|forward|forwarding|disclose|supply|text me)(?![a-z])';

/// أفعال "اكتب/أدخل" (enter/type/confirm...): طبيعية في رسائل الكود الرسمية، فبتتحسب
/// طلب بيانات بس لو الرسالة فيها رابط مش موثوق (المدخل بيروح لموقع مشبوه).
const String kInputVerbsAr =
    r'(?<![\u0621-\u064A])(?:[\u0621-\u064A]{0,2})?(?:اكتب|ادخل|ادخال|اكد|تاكيد|حدث)[\u0621-\u064A]*';
const String kInputVerbsEn =
    r'(?<![a-z])(?:enter|entering|type|typing|submit|submitting|confirm|confirming|verify|verifying|update|updating)(?![a-z])';

/// عبارات تحذيرية موجودة في الرسائل الرسمية الحقيقية: الجملة اللي فيها واحدة منها
/// تحذير من مشاركة البيانات مش طلب لها.
const List<String> kProtectivePhrases = <String>[
  'لا تشارك', 'لا تعطي', 'لا تعط', 'لا ترسل', 'لا تبعت', 'لا تفصح', 'لن نطلب',
  'لن يطلب', 'لا نطلب', 'لا تقم بمشاركة',
  'ماتشاركش', 'متشاركش', 'ما تشاركش',
  'do not share', "don't share", 'dont share', 'never share', 'do not give',
  "don't give", 'never give', 'do not disclose', "don't disclose", 'do not send',
  "don't send", 'never send', 'will never ask', 'never ask you', "won't ask",
  'we will never',
];
