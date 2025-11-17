enum AppLanguage { fa, en }

class Strings {
  final AppLanguage lang;
  const Strings(this.lang);

  bool get isFa => lang == AppLanguage.fa;

  // NOTE: Each getter returns a localized string. Only include a doc comment where
  // semantics might not be immediately obvious. Most are self‑explanatory labels.

  // General
  String get appTitle => isFa ? 'پازل کشویی لواش' : 'Lavash Sliding Puzzle';
  String get close => isFa ? 'بستن' : 'Close';

  // Action bar labels
  String get abPickImage => isFa ? 'عکس' : 'Image';
  String get abShuffleIncorrect => isFa ? 'جابه‌جایی' : 'Shuffle';
  String get abReset => isFa ? 'دوباره' : 'Reset';
  String get abSettings => isFa ? 'تنظیمات' : 'Settings';
  String get abHelp => isFa ? 'راهنما' : 'Help';
  String get abDelete => isFa ? 'حذف' : 'Delete';

  // Settings
  String get settingsTitle => isFa ? 'تنظیمات' : 'Settings';
  String get settingsDark => isFa ? 'حالت تیره' : 'Dark mode';
  String get settingsShowNumbers =>
      isFa ? 'نمایش شماره تایل‌ها' : 'Show tile numbers';
  String get settingsPuzzleSize => isFa ? 'ابعاد پازل' : 'Puzzle size';
  String get settingsLanguage => isFa ? 'زبان' : 'Language';
  String get settingsClickSound =>
      isFa ? 'پخش صدای کلیک تایل‌ها' : 'Tile click sound';
  String get langFa => 'فارسی';
  String get langEn => 'English';

  // Help
  String get helpHowTo => isFa ? 'نحوه بازی:' : 'How to play:';
  String get helpHowToBody => isFa
      ? 'تصویر (انتخابی شما یا انتخاب شده توسط برنامه) به قطعاتی که شما انتخاب نمودید (پیشفرض ۳ در ۳) به همراه یک خانه خالی تقسیم میشود. با زدن هر قطعهٔ مجاور خانهٔ خالی آن قطعه جایگزین خانهٔ خالی میشود. هدف این است که همهٔ قطعات را به جای درستشان برگردانید و تصویر اصلی را درست کنید. به صورت پیشفرض بازی با عکس تصادفی آغاز میشود ولی شما میتوانید از طریق اسلایدر عکسی را انتخاب و بازی جدیدی آغاز کنید.'
      : 'The image (yours or app-selected) is split into tiles (default 3x3) with one empty space. Tap a tile adjacent to the empty space to move it. Your goal is to restore the original image. The game starts with a random image, but you can pick one from the slider to start a new game.';
  String get helpFeatures =>
      isFa ? 'دکمهها و امکانات:' : 'Buttons and features:';
  String get helpPickImageTitle => isFa ? 'تصویر' : 'image';
  String get helpPickImageDesc => isFa
      ? 'از گالری خودتان عکسی انتخاب کنید تا بازی جدید با عکس انتخابی شما شروع شود. عکس انتخابی شما ذخیره میشود تا بعدا نیز استفاده شود.'
      : 'Choose a photo from your gallery to start a new game. Your chosen photo is saved for later use.';
  String get helpShuffleTitle => isFa ? 'جابه جایی' : 'Shuffle';
  String get helpShuffleDesc => isFa
      ? 'چند قطعهٔ نامرتب را جابه جا میکند تا چیدمان عوض شود.'
      : 'Swaps a few incorrect tiles to change the layout.';
  String get helpResetTitle => isFa ? 'دوباره' : 'reset';
  String get helpResetDesc => isFa
      ? 'بازی را از ابتدا و با یک تصویر رندم شروع میکند.'
      : 'Starts a new game from scratch with a random image.';
  String get helpSettingsTitle => isFa ? 'تنظیمات' : 'Settings';
  String get helpSettingsDesc => isFa
      ? 'از طریق منوی تنظیمات میتوانید نمایش/عدم نمایش شمارهٔ تایلها، حالت روشن/تیره، ابعاد و زبان بازی را تغییر دهید.'
      : 'Use settings to toggle tile numbers, light/dark mode, puzzle size, and language.';
  String get helpDeleteTitle => isFa ? 'حذف عکس' : 'Delete image';
  String get helpDeleteDesc => isFa
      ? 'برای تصاویر انتخابی شما، یک آیکون ضربدر (X) شفاف در گوشهٔ بالاراست بندانگشتی داخل اسلایدر ظاهر میشود؛ با زدن آن، تصویر حذف و بازی با یک تصویر تصادفی ادامه مییابد.'
      : 'For user-picked images, a translucent X icon appears at the top-right of the thumbnail in the slider; tap it to delete';
  String get helpScoreTime => isFa ? 'امتیاز و زمان:' : 'Score and time:';
  String get helpScoreTimeDesc => isFa
      ? 'در پایان بازی و در صورت برنده شدن، تعداد حرکتها و زمان صرفشده نمایش داده میشود.'
      : 'When you win, your number of moves and elapsed time are shown.';
  String get helpTips => isFa ? 'نکات مفید:' : 'Tips:';
  String get helpTipsBody => isFa
      ? '• اگر تایل در جای درست خود باشد حاشیهٔ آن سبز میشود.\n• تنظیمات (تم/ابعاد/نمایش اعداد/زبان و تصاویر انتخابی) ذخیره میشوند.\n• بازی ذخیره میشود و میتوانید بعداً ادامه دهید.'
      : '• Tiles in the correct position get a green border.\n• Your settings and chosen images are saved.\n• The game auto-saves so you can continue later.';

  // Delete dialog
  String get dlgDeleteTitle => isFa ? 'حذف عکس' : 'Delete image';
  String get dlgDeleteConfirm => isFa
      ? 'آیا از حذف این عکس مطمئن هستید؟'
      : 'Are you sure you want to delete this image?';
  String get dlgNo => isFa ? 'خیر' : 'No';
  String get dlgYesDelete => isFa ? 'بله، حذف شود' : 'Yes, delete';

  // Win overlay
  String get winTitle => isFa ? 'شما برنده شدید! 🎉' : 'You won! 🎉';
  String get winSubtitle => isFa ? 'برای ادامه کلیک کنید' : 'Tap to continue';
  String get movesLabel => isFa ? 'حرکت' : 'Moves';
  String get timeLabel => isFa ? 'زمان' : 'Time';
}
