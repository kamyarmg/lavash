import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ماژول حذف فایل به صورت پلتفرم-شرطی (برای وب NO-OP)

// ------------------------------
// تبدیل ارقام لاتین به فارسی
// ------------------------------
String _toFaDigits(dynamic input) {
  final persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  return input.toString().replaceAllMapped(
    RegExp(r'\d'),
    (m) => persian[int.parse(m[0]!)],
  );
}

// ---------------------------------------------
// مدل کاشی (Tile)
// ---------------------------------------------
class Tile {
  final int correctIndex; // موقعیت صحیح در آرایه 0..n-1
  int currentIndex; // موقعیت فعلی
  Tile({required this.correctIndex, required this.currentIndex});

  bool get inCorrectPlace => correctIndex == currentIndex;
}

// ---------------------------------------------
// برد پازل
// ---------------------------------------------
class PuzzleBoard {
  final int dimension; // مثلا 3 برای 3x3
  final List<Tile> tiles; // آخرین خانه خالی است (index = tiles.length -1)

  PuzzleBoard._(this.dimension, this.tiles);

  factory PuzzleBoard.solved(int dim) {
    final total = dim * dim;
    final tiles = List.generate(
      total,
      (i) => Tile(correctIndex: i, currentIndex: i),
    );
    return PuzzleBoard._(dim, tiles);
  }

  int get emptyTileIndex => tiles.length - 1; // index در آرایه tiles

  bool get isSolved => tiles.every((t) => t.inCorrectPlace);

  /// لیست ایندکس‌های آرایه که قابل حرکت اند (همسایه با کاشی خالی)
  List<int> movableTileArrayIndexes() {
    final emptyPos = tiles[emptyTileIndex].currentIndex; // موقعیت خطی خالی
    final row = emptyPos ~/ dimension;
    final col = emptyPos % dimension;
    final candidates = <int>[];
    void addIfValid(int r, int c) {
      if (r >= 0 && r < dimension && c >= 0 && c < dimension) {
        final linear = r * dimension + c;
        final tileArrIdx = tiles.indexWhere((t) => t.currentIndex == linear);
        if (tileArrIdx != -1 && tileArrIdx != emptyTileIndex) {
          candidates.add(tileArrIdx);
        }
      }
    }

    addIfValid(row - 1, col);
    addIfValid(row + 1, col);
    addIfValid(row, col - 1);
    addIfValid(row, col + 1);
    return candidates;
  }

  /// تلاش برای حرکت دادن tile با index آرایه tiles
  bool move(int tileArrayIndex) {
    if (!movableTileArrayIndexes().contains(tileArrayIndex)) return false;
    final empty = tiles[emptyTileIndex];
    final tile = tiles[tileArrayIndex];
    final temp = tile.currentIndex;
    tile.currentIndex = empty.currentIndex;
    empty.currentIndex = temp;
    return true;
  }

  PuzzleBoard shuffled(Random rng) {
    final maxAttempts = 5000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final perm = List<int>.generate(tiles.length, (i) => i);
      perm.shuffle(rng);
      final emptyIdxInPerm = perm.indexOf(emptyTileIndex);
      if (emptyIdxInPerm != perm.length - 1) {
        perm[emptyIdxInPerm] = perm.last;
        perm[perm.length - 1] = emptyTileIndex;
      }
      if (_isSolvable(perm, dimension)) {
        final newTiles = List<Tile>.generate(tiles.length, (i) {
          final correct = i;
          final current = perm.indexOf(i);
          return Tile(correctIndex: correct, currentIndex: current);
        });
        return PuzzleBoard._(dimension, newTiles);
      }
    }
    return this;
  }

  static bool _isSolvable(List<int> perm, int dim) {
    final list = perm.take(perm.length - 1).toList();
    int inversions = 0;
    for (int i = 0; i < list.length; i++) {
      for (int j = i + 1; j < list.length; j++) {
        if (list[i] > list[j]) inversions++;
      }
    }
    if (dim.isOdd) {
      return inversions.isEven;
    } else {
      final emptyLinear = perm.indexOf(perm.length - 1);
      final emptyRowFromTop = emptyLinear ~/ dim;
      final emptyRowFromBottom = dim - emptyRowFromTop;
      if (emptyRowFromBottom.isOdd) {
        return inversions.isEven;
      } else {
        return inversions.isOdd;
      }
    }
  }

  PuzzleBoard partialShuffleIncorrect(Random rng) {
    final incorrectTiles = tiles
        .where(
          (t) =>
              t.correctIndex != t.currentIndex &&
              t.correctIndex != emptyTileIndex,
        )
        .toList();
    if (incorrectTiles.length < 2) return this;

    final attempts = min(incorrectTiles.length * 10, 200);
    for (int attempt = 0; attempt < attempts; attempt++) {
      final positions = incorrectTiles.map((t) => t.currentIndex).toList();
      positions.shuffle(rng);
      for (int i = 0; i < incorrectTiles.length; i++) {
        incorrectTiles[i].currentIndex = positions[i];
      }
      final perm = List<int>.filled(tiles.length, -1);
      for (final t in tiles) {
        perm[t.currentIndex] = t.correctIndex;
      }
      if (_isSolvable(perm, dimension)) {
        return this;
      }
    }
    return this;
  }
}

// وضعیت ذخیره‌شده بازی برای رزومه
class _SavedGame {
  final int dim;
  final List<int> tileCurrents; // طول = dim*dim (برای هر correctIndex)
  final int moves;
  final int seconds;
  final bool solved;
  const _SavedGame({
    required this.dim,
    required this.tileCurrents,
    required this.moves,
    required this.seconds,
    required this.solved,
  });
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with TickerProviderStateMixin {
  // Keys for safe context inside MaterialApp
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  int dimension = 3;
  late PuzzleBoard board;
  ui.Image? image; // تصویر انتخاب‌شده
  final rng = Random();
  // شناسه انتخاب‌شده در اسلایدر: مسیر asset یا شناسه کاربر
  String? _selectedId;
  // گالری تصاویر کاربر (لیست بایت‌ها برای نمایش) + ورودی‌های پایدار
  List<Uint8List> _userImages = [];
  List<String> _userEntries = []; // هر ورودی: B64://... یا FILE://path
  Timer? _timer;
  int seconds = 0;
  int moves = 0;
  // نمایش شماره تایل‌ها همیشه فعال است (showNumbers حذف شد)
  bool darkMode = false; // fastMode حذف شد
  // حالت کوررنگی حذف شد
  bool _justSolved = false;
  late AnimationController _solveParticles;
  // نمایش پیام برد به صورت اوورلی
  bool _showWinOverlay = false;
  late AnimationController _winBanner;

  // تم: پالت رنگی بر اساس seed و اندیس انتخاب‌شده
  static const String _kPrefThemeIdx = 'settings.themeIndex';
  final List<Color> _seedPalette = const [
    Colors.teal,
    Colors.indigo,
    Colors.cyan,
    Colors.purple,
    Colors.lightBlue,
    Colors.amber,
    Colors.pink,
  ];
  int _themeIdx = 0; // پیش‌فرض: teal

  // رکوردها
  int? bestMoves;
  int? bestTime; // ثانیه
  // رنگ‌های ثابت (حذف سیستم پالت)
  // گرادیان روشن و درخشان که در هر دو مود زیبا باشد.
  // اگر کاربر مود تیره را بزند، یک لایه تیره شفاف روی آن اعمال می‌کنیم.
  // static const Color _accentColor = Color(0xFF00BFA5); // حذف: دیگر استفاده نمی‌شود

  // کش برش‌ها
  List<ui.Image?>? _slices; // طول = tiles.length -1
  // کلیدهای ذخیره تنظیمات کاربر
  static const String _kPrefDark = 'settings.darkMode';
  static const String _kPrefDim = 'settings.dimension';
  static const String _kPrefLastImage =
      'settings.lastImage'; // مقادیر: 'B64://...' یا مسیر asset
  static const String _kPrefUserImages =
      'settings.userImages'; // JSON list of entries (B64://... | FILE://...)
  // کلیدهای ذخیره وضعیت بازی
  static const String _kGameDim = 'game.dimension';
  static const String _kGameTiles =
      'game.tiles'; // CSV از currentIndex ها برای هر correctIndex
  static const String _kGameMoves = 'game.moves';
  static const String _kGameSeconds = 'game.seconds';
  static const String _kGameSolved = 'game.solved';

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);
    // ابتدا تنظیمات ذخیره‌شده را می‌خوانیم؛ شامل مود تیره، ابعاد، و آخرین تصویر
    _loadSettings();
    _solveParticles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _winBanner = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 300),
    );
    // اگر تنظیمات تصویری نیامد، بعداً در _loadSettings تصویر تصادفی بارگذاری می‌شود
  }

  @override
  void dispose() {
    _timer?.cancel();
    _solveParticles.dispose();
    _winBanner.dispose();
    super.dispose();
  }

  void _startTimer({bool resetSeconds = true}) {
    _timer?.cancel();
    if (resetSeconds) seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (board.isSolved) return;
      setState(() => seconds++);
      // ذخیره وضعیت هر ثانیه تا در صورت خروج، ادامه دهد
      _saveGameState(solved: false);
    });
  }

  Future<void> _loadRecords() async {
    final sp = await SharedPreferences.getInstance();
    bestMoves = sp.getInt('best_moves_$dimension');
    bestTime = sp.getInt('best_time_$dimension');
    if (mounted) setState(() {});
  }

  Future<void> _saveRecordIfBetter() async {
    final sp = await SharedPreferences.getInstance();
    bool changed = false;
    if (bestMoves == null || moves < bestMoves!) {
      bestMoves = moves;
      await sp.setInt('best_moves_$dimension', moves);
      changed = true;
    }
    if (bestTime == null || seconds < bestTime!) {
      bestTime = seconds;
      await sp.setInt('best_time_$dimension', seconds);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // progress bar حذف شد

  void _toggleDark() async {
    setState(() => darkMode = !darkMode);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefDark, darkMode);
  }

  // متد تغییر تم حذف شد
  // حالت کوررنگی حذف شد

  // لیست دینامیک تصاویر که در زمان اجرا از assets بارگذاری می‌شود
  List<String> _assetImages = [];
  bool _imagesLoaded = false;

  /// بارگذاری لیست تصاویر به صورت دینامیک از پوشه assets/images
  ///
  /// برای افزودن تصاویر جدید:
  /// 1. تصاویر جدید را در پوشه assets/images/ قرار دهید
  /// 2. نیازی به تغییر کد نیست - تصاویر به صورت خودکار شناسایی می‌شوند
  /// 3. فرمت‌های پشتیبانی شده: .jpg, .jpeg, .png, .webp
  Future<void> _loadAssetImagesList() async {
    if (_imagesLoaded) return;

    try {
      // خواندن فهرست تصاویر از AssetManifest
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // فیلتر کردن فایل‌هایی که در پوشه assets/images/ هستند
      final imageAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/images/'))
          .where(
            (String key) =>
                key.toLowerCase().endsWith('.jpg') ||
                key.toLowerCase().endsWith('.jpeg') ||
                key.toLowerCase().endsWith('.png') ||
                key.toLowerCase().endsWith('.webp'),
          )
          .toList();

      _assetImages = imageAssets;
      _imagesLoaded = true;

      // مرتب‌سازی برای نظم بهتر (اختیاری)
      _assetImages.sort();

      // لاگ برای بررسی موفقیت‌آمیز بودن بارگذاری
      // ignore: avoid_print
      print(
        '✅ ${_assetImages.length} تصویر از assets بارگذاری شد: $_assetImages',
      );

      if (mounted) setState(() {});
    } catch (e) {
      // در صورت خطا، از لیست پیش‌فرض استفاده می‌کنیم
      _assetImages = [
        'assets/images/1.jpg',
        'assets/images/2.jpg',
        'assets/images/3.jpg',
        'assets/images/4.jpg',
        'assets/images/5.jpg',
      ];
      _imagesLoaded = true;
      // ignore: avoid_print
      print('خطا در بارگذاری لیست تصاویر: $e');
    }
  }

  Future<void> _loadRandomAssetImage() async {
    try {
      // اطمینان از بارگذاری لیست تصاویر
      await _loadAssetImagesList();

      if (_assetImages.isEmpty) {
        // ignore: avoid_print
        print('هیچ تصویری در assets یافت نشد');
        return;
      }

      final pick = _assetImages[rng.nextInt(_assetImages.length)];
      await _loadAssetImage(pick);
    } catch (e) {
      // ignore: avoid_print
      print('Random asset image load failed: $e');
    }
  }

  Future<void> _loadAssetImage(String path, {bool forResume = false}) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _selectedId = path;
        image = frame.image;
        // وقتی تصویر asset انتخاب می‌شود، انتخاب کاربر غیرفعال می‌شود
      });
      // ذخیره آخرین تصویر انتخاب‌شده (asset)
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, path);
      if (forResume) {
        // فقط اسلایس ها را بساز؛ بورد را دست نزن
        await _buildSlices();
      } else {
        // تغییر تصویر = شروع بازی جدید
        await _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Asset image load failed: $e');
    }
  }

  // -----------------------------
  // User images gallery helpers
  // -----------------------------
  String _userId(int index) => 'USER:$index';

  // تابع قدیمی یافتن ایندکس Base64 حذف شد؛ از _userEntries استفاده می‌کنیم

  // حذف تابع قدیمی افزودن Base64؛ اکنون از _addUserEntry استفاده می‌شود

  // افزودن ورودی عمومی (bytes باید دادهٔ تصویر باشد)
  void _addUserEntry(String entry, Uint8List data) {
    final idx = _userEntries.indexOf(entry);
    if (idx >= 0) {
      final img = _userImages.removeAt(idx);
      _userImages.insert(0, img);
      final ent = _userEntries.removeAt(idx);
      _userEntries.insert(0, ent);
      return;
    }
    _userImages.insert(0, data);
    _userEntries.insert(0, entry);
    const maxKeep = 10;
    if (_userImages.length > maxKeep) {
      _userImages = _userImages.sublist(0, maxKeep);
      _userEntries = _userEntries.sublist(0, maxKeep);
    }
  }

  // ذخیره تصویر انتخاب‌شده: روی وب Base64، روی سایر پلتفرم‌ها فایل در Documents
  Future<String> _persistPickedImage(
    Uint8List data, {
    XFile? source,
    String? suggestedName,
  }) async {
    if (kIsWeb) {
      return 'B64://${base64Encode(data)}';
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext =
          (suggestedName != null && p.extension(suggestedName).isNotEmpty)
          ? p.extension(suggestedName)
          : '.jpg';
      final filename = 'lavash_${DateTime.now().millisecondsSinceEpoch}$ext';
      final target = p.join(dir.path, filename);
      if (source != null) {
        await source.saveTo(target);
      } else {
        final xf = XFile.fromData(data, name: filename);
        await xf.saveTo(target);
      }
      return 'FILE://$target';
    } catch (_) {
      return 'B64://${base64Encode(data)}';
    }
  }

  Future<void> _saveUserImagesList() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefUserImages, jsonEncode(_userEntries));
    } catch (_) {}
  }

  Future<void> _loadUserImagesList() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kPrefUserImages);
      if (raw == null) return;
      final List<dynamic> arr = jsonDecode(raw);
      _userImages = [];
      _userEntries = [];
      for (final item in arr) {
        if (item is String) {
          try {
            if (item.startsWith('B64://')) {
              _userImages.add(base64Decode(item.substring(6)));
              _userEntries.add(item);
            } else if (item.startsWith('FILE://') && !kIsWeb) {
              final bytes = await XFile(item.substring(7)).readAsBytes();
              _userImages.add(bytes);
              _userEntries.add(item);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
  // حالت سریع حذف شد

  Future<void> _buildSlices() async {
    if (image == null) {
      _slices = null;
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() {});
    try {
      final img = image!;
      final dim = dimension;
      final tileW = img.width / dim;
      final tileH = img.height / dim;
      final list = List<ui.Image?>.filled(dim * dim - 1, null);
      for (int i = 0; i < list.length; i++) {
        final r = i ~/ dim;
        final c = i % dim;
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        final src = Rect.fromLTWH(c * tileW, r * tileH, tileW, tileH);
        final dst = Rect.fromLTWH(0, 0, tileW, tileH);
        canvas.drawImageRect(img, src, dst, Paint());
        final pic = rec.endRecording();
        final sub = await pic.toImage(tileW.toInt(), tileH.toInt());
        list[i] = sub;
      }
      _slices = list;
    } catch (e) {
      // ignore: avoid_print
      print('slice cache failed: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final result = await picker.pickImage(source: ImageSource.gallery);
      if (result == null) return;
      final data = await result.readAsBytes();
      final entry = await _persistPickedImage(
        data,
        source: result,
        suggestedName: result.name,
      );
      _addUserEntry(entry, data);
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      // ابتدا تصویر ست می‌شود
      setState(() {
        image = frame.image;
        // شناسه انتخاب‌شده به عنوان تصویر کاربر (اولین مورد لیست)
        _selectedId = _userId(0);
      });
      // ذخیره آخرین تصویر انتخاب‌شده به صورت Base64 تا روی وب نیز کار کند
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, entry);
      await _saveUserImagesList();
      // سپس بورد ریست می‌شود (خارج از همان setState برای جلوگیری از مشکلات رندر)
      _clearGameState();
      _reset(shuffle: true);
      _buildSlices();
      // لاگ ساده برای اطمینان
      // (می‌توانید بعداً حذف کنید)
      // ignore: avoid_print
      print('Image loaded: ${image!.width}x${image!.height}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('خطا در بارگذاری تصویر: $e');
    }
  }

  Future<void> deleteFileIfExists(String path) async {
    try {
      final f = io.File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore errors
    }
  }

  // حذف تصویر انتخابی کاربر با تایید
  Future<void> _confirmAndDeleteSelectedUserImage() async {
    final id = _selectedId;
    if (id == null || !id.startsWith('USER:')) return;
    final idx = int.tryParse(id.split(':').elementAt(1));
    if (idx == null || idx < 0 || idx >= _userEntries.length) return;

    final dialogContext = _navKey.currentContext ?? context;
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف عکس'),
        content: const Text('آیا از حذف این عکس مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('خیر'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('بله، حذف شود'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // تلاش برای حذف فایل فیزیکی در صورت FILE://
    final entry = _userEntries[idx];
    if (entry.startsWith('FILE://')) {
      final path = entry.substring(7);
      await deleteFileIfExists(path);
    }

    // حذف از آرایه‌ها و ذخیره
    setState(() {
      _userEntries.removeAt(idx);
      _userImages.removeAt(idx);
    });
    await _saveUserImagesList();

    // اگر هنوز عکس کاربری داریم، اولین را انتخاب کن؛ در غیر اینصورت یکی از assets را بارگذاری کن
    if (_userImages.isNotEmpty) {
      try {
        final data = _userImages[0];
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        if (!mounted) return;
        setState(() {
          image = frame.image;
          _selectedId = _userId(0);
        });
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_kPrefLastImage, 'B64://${base64Encode(data)}');
        _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
        _showSnack('عکس حذف شد و بازی جدید شروع شد');
      } catch (_) {
        await _loadRandomAssetImage();
        _showSnack('عکس حذف شد و بازی جدید شروع شد');
      }
    } else {
      await _loadRandomAssetImage();
      _showSnack('عکس حذف شد و بازی جدید شروع شد');
    }
  }

  void _showSnack(String text) {
    final sm = _scaffoldKey.currentState;
    if (sm != null) {
      sm.clearSnackBars();
      sm.showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _reset({bool shuffle = false}) {
    _justSolved = false;
    board = PuzzleBoard.solved(dimension);
    if (shuffle) {
      board = board.shuffled(rng);
    }
    moves = 0;
    _startTimer();
    _slices = null;
    setState(() {});
    if (image != null) _buildSlices();
    // شروع جدید => وضعیت قبلی پاک شود
    _clearGameState();
  }

  void _changeDimension(int d) {
    dimension = d;
    _reset(shuffle: true);
    _loadRecords();
    // ذخیره ابعاد انتخاب‌شده
    SharedPreferences.getInstance().then((sp) => sp.setInt(_kPrefDim, d));
  }

  void _onTileTap(int tileArrayIndex) {
    if (board.isSolved) return;
    final moved = board.move(tileArrayIndex);
    if (moved) {
      moves++;
      setState(() {});
      // ذخیره پس از هر حرکت
      _saveGameState();
      if (board.isSolved) {
        _timer?.cancel();
        _saveRecordIfBetter();
        // علامت‌گذاری به عنوان حل شده تا در اجرای بعدی رزومه نشود
        _saveGameState(solved: true);
        _justSolved = true;
        _solveParticles.forward(from: 0);
        HapticFeedback.mediumImpact();
        // نمایش اوورلی برد (غیرمسدودکننده و قابل لمس برای بستن)
        setState(() => _showWinOverlay = true);
        _winBanner.forward(from: 0);
      }
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    final result =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return _toFaDigits(result);
  }

  // بارگذاری تصویر از روی فایل (برای حالت ادامه از تنظیمات)
  Future<void> _loadFileImage(String filePath, {bool forResume = false}) async {
    await Future<void>.delayed(Duration.zero); // تضمین async
    try {
      // بدون استفاده از dart:io فایل را با XFile بخوانیم
      final xf = XFile(filePath);
      final data = await xf.readAsBytes();
      final entry = 'FILE://$filePath';
      _addUserEntry(entry, data);
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        image = frame.image;
        _selectedId = _userId(0);
      });
      if (forResume) {
        await _buildSlices();
      } else {
        await _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, entry);
      await _saveUserImagesList();
    } catch (e) {
      await _loadRandomAssetImage();
    }
  }

  // خواندن و اعمال تنظیمات ذخیره‌شده (مود تیره، ابعاد، آخرین تصویر)
  Future<void> _loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    final savedDark = sp.getBool(_kPrefDark);
    final savedDim = sp.getInt(_kPrefDim);
    final savedImage = sp.getString(_kPrefLastImage);
    final savedThemeIdx = sp.getInt(_kPrefThemeIdx);
    // خواندن وضعیت بازی
    final savedGame = await _readSavedGame();

    if (savedDark != null) darkMode = savedDark;
    if (savedThemeIdx != null &&
        savedThemeIdx >= 0 &&
        savedThemeIdx < _seedPalette.length) {
      _themeIdx = savedThemeIdx;
    }
    // اگر بازی ذخیره شده معتبر داریم، بعد را از همان بگیریم
    if (savedGame != null && !savedGame.solved) {
      dimension = savedGame.dim;
    } else if (savedDim != null && savedDim >= 3 && savedDim <= 8) {
      dimension = savedDim;
    }
    // در این مرحله هنوز بورد را شافل نمی‌کنیم تا بتوانیم رزومه کنیم
    if (mounted) setState(() {});
    _loadRecords();
    // ابتدا لیست تصاویر را بارگذاری می‌کنیم
    await _loadAssetImagesList();
    // گالری کاربر را بارگذاری کن
    await _loadUserImagesList();

    // ابتدا تصویر را بارگذاری می‌کنیم
    final bool resumePlanned = savedGame != null && !savedGame.solved;
    if (savedImage != null) {
      if (savedImage.startsWith('B64://')) {
        final b64 = savedImage.substring(6);
        try {
          final data = base64Decode(b64);
          // اگر این تصویر در گالری کاربر نیست، به ابتدای لیست اضافه و ذخیره کن
          _addUserEntry('B64://$b64', data);
          await _saveUserImagesList();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          if (mounted) {
            setState(() {
              image = frame.image;
              // انتخاب ایتم مربوطه در گالری
              final idx = _userEntries.indexOf('B64://$b64');
              _selectedId = idx >= 0 ? _userId(idx) : _userId(0);
            });
          }
          await _buildSlices();
        } catch (_) {
          await _loadRandomAssetImage();
        }
      } else if (_assetImages.contains(savedImage)) {
        await _loadAssetImage(savedImage, forResume: resumePlanned);
      } else if (savedImage.startsWith('FILE://') && !kIsWeb) {
        final path = savedImage.substring(7);
        try {
          final data = await XFile(path).readAsBytes();
          _addUserEntry(savedImage, data);
          await _saveUserImagesList();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          if (mounted) {
            setState(() {
              image = frame.image;
              final idx = _userEntries.indexOf(savedImage);
              _selectedId = idx >= 0 ? _userId(idx) : _userId(0);
            });
          }
          await _buildSlices();
        } catch (_) {
          await _loadRandomAssetImage();
        }
      } else if (savedImage.startsWith('FILE://')) {
        // پشتیبانی قدیمی: تبدیل به Base64 و استفاده
        final path = savedImage.substring(7);
        await _loadFileImage(path, forResume: resumePlanned);
      } else {
        await _loadRandomAssetImage();
      }
    } else {
      await _loadRandomAssetImage();
    }

    // اگر وضعیت بازی ذخیره شده و حل نشده داریم، مستقیم رزومه کن
    if (resumePlanned) {
      _applySavedGame(savedGame);
      _startTimer(resetSeconds: false);
    } else {
      // اگر بازی قبلی حل شده بود یا نبود، یک بازی جدید داشته باشیم
      _reset(shuffle: true);
    }
  }

  // ------------------------------------------------------------
  // Game-state persistence helpers
  // ------------------------------------------------------------
  Future<void> _saveGameState({bool? solved}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final dim = dimension;
      final total = dim * dim;
      final indices = List<int>.generate(
        total,
        (i) => board.tiles[i].currentIndex,
      );
      final csv = indices.join(',');
      await sp.setInt(_kGameDim, dim);
      await sp.setString(_kGameTiles, csv);
      await sp.setInt(_kGameMoves, moves);
      await sp.setInt(_kGameSeconds, seconds);
      await sp.setBool(_kGameSolved, solved ?? false);
    } catch (_) {}
  }

  Future<void> _clearGameState() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kGameDim);
    await sp.remove(_kGameTiles);
    await sp.remove(_kGameMoves);
    await sp.remove(_kGameSeconds);
    await sp.remove(_kGameSolved);
  }

  Future<_SavedGame?> _readSavedGame() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final dim = sp.getInt(_kGameDim);
      final csv = sp.getString(_kGameTiles);
      final mv = sp.getInt(_kGameMoves);
      final sec = sp.getInt(_kGameSeconds);
      final solved = sp.getBool(_kGameSolved) ?? false;
      if (dim == null || csv == null || mv == null || sec == null) return null;
      final parts = csv.split(',');
      if (parts.length != dim * dim) return null;
      final indices = <int>[];
      for (final p in parts) {
        final v = int.tryParse(p);
        if (v == null) return null;
        indices.add(v);
      }
      final total = dim * dim;
      final setAll = indices.toSet();
      if (indices.any((e) => e < 0 || e >= total)) return null;
      if (setAll.length != indices.length) return null;
      return _SavedGame(
        dim: dim,
        tileCurrents: indices,
        moves: mv,
        seconds: sec,
        solved: solved,
      );
    } catch (_) {
      return null;
    }
  }

  void _applySavedGame(_SavedGame sg) {
    dimension = sg.dim;
    final newBoard = PuzzleBoard.solved(dimension);
    for (int i = 0; i < newBoard.tiles.length; i++) {
      newBoard.tiles[i].currentIndex = sg.tileCurrents[i];
    }
    board = newBoard;
    moves = sg.moves;
    seconds = sg.seconds;
    _justSolved = false;
    _slices = null;
    setState(() {});
    if (image != null) _buildSlices();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: darkMode ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedPalette[_themeIdx],
        brightness: darkMode ? Brightness.dark : Brightness.light,
      ),
      textTheme: GoogleFonts.vazirmatnTextTheme(
        darkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      scaffoldBackgroundColor: darkMode
          ? const Color(0xFF0E0F12)
          : Colors.white,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _scaffoldKey,
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              // پسزمینه مدرن با بلور ملایم، دِساتوره، و ویگنت
              Positioned.fill(
                child: _ModernBackground(
                  image: image,
                  dark: darkMode,
                  primary: Theme.of(context).colorScheme.primary,
                ),
              ),
              // عنوان رنگی در بالای صفحه، فقط وقتی نسبت ارتفاع برنامه به عرض آن > 1.5 باشد
              if ((MediaQuery.of(context).size.height /
                      MediaQuery.of(context).size.width) >
                  1.5)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 5,
                  child: SafeArea(
                    bottom: false,
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Center(
                          child: _RainbowTitle(text: 'پازل کشویی لواش'),
                        ),
                      ),
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  // محاسبه فضای موثر برای اجزا
                  final availableHeight = constraints.maxHeight;
                  final availableWidth = constraints.maxWidth;

                  // محاسبه فضای لازم برای نوار پایینی (حدود 80 پیکسل)
                  final bottomBarSpace = 80.0;

                  // محاسبه ارتفاع اسلایدر (200 پیکسل)
                  final sliderHeight = 200.0;

                  // محاسبه فضای باقی‌مانده برای برد پازل
                  final remainingHeight =
                      availableHeight - bottomBarSpace - sliderHeight;

                  // محاسبه حداکثر اندازه برد (مربعی)
                  final maxBoard = min(
                    availableWidth * 0.9, // 90% عرض دستگاه
                    remainingHeight * 0.7, // 70% ارتفاع باقی‌مانده
                  ).clamp(240.0, 720.0);

                  // محاسبه فاصله عمودی به صورت متناسب
                  final remainingVerticalSpace = remainingHeight - maxBoard;
                  final verticalSpacing = (remainingVerticalSpace / 3).clamp(
                    10.0,
                    50.0,
                  );

                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        availableWidth * 0.03, // 3% فاصله افقی
                        verticalSpacing, // فاصله بالا
                        availableWidth * 0.03, // 3% فاصله افقی
                        bottomBarSpace, // فضای نوار پایینی
                      ),
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // اسلایدر با همان عرض برد
                              SizedBox(
                                width: maxBoard,
                                child: _AssetSlider(
                                  assets: _assetImages,
                                  userImages: _userImages,
                                  selectedId: _selectedId,
                                  onSelect: (id) async {
                                    if (id.startsWith('USER:')) {
                                      final idx = int.tryParse(
                                        id.split(':')[1],
                                      );
                                      if (idx != null &&
                                          idx >= 0 &&
                                          idx < _userImages.length) {
                                        final data = _userImages[idx];
                                        final codec = await ui
                                            .instantiateImageCodec(data);
                                        final frame = await codec
                                            .getNextFrame();
                                        if (!mounted) return;
                                        setState(() {
                                          image = frame.image;
                                          _selectedId = id;
                                        });
                                        final sp =
                                            await SharedPreferences.getInstance();
                                        await sp.setString(
                                          _kPrefLastImage,
                                          'B64://${base64Encode(data)}',
                                        );
                                        _clearGameState();
                                        _reset(shuffle: true);
                                        _buildSlices();
                                      }
                                    } else {
                                      _loadAssetImage(id);
                                    }
                                  },
                                ),
                              ),
                              SizedBox(height: verticalSpacing), // فاصله متناسب
                              Hero(
                                tag: 'board',
                                child: _FancyFrame(
                                  child: SizedBox(
                                    width: maxBoard,
                                    height: maxBoard,
                                    child: _PuzzleView(
                                      board: board,
                                      dimension: dimension,
                                      image: image,
                                      onTileTap: _onTileTap,
                                      slices: _slices,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: verticalSpacing), // فاصله متناسب
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // دکمه های پایین
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ActionBar(
                  onPickImage: _pickImage,
                  onShuffleIncorrect: () =>
                      setState(() => board.partialShuffleIncorrect(rng)),
                  onReset: () => _loadRandomAssetImage(),
                  onChangeDim: _changeDimension,
                  dimension: dimension,
                  darkMode: darkMode,
                  onToggleDark: _toggleDark,
                  showDelete: (_selectedId?.startsWith('USER:') ?? false),
                  onDelete: _confirmAndDeleteSelectedUserImage,
                ),
              ),
              if (_justSolved)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: ParticleBurstPainter(
                        progress: _solveParticles.value,
                        seed: moves,
                      ),
                    ),
                  ),
                ),
              // اوورلی برد: پیام زیبا و انیمیشنی که با کلیک ناپدید می‌شود
              if (_showWinOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _winBanner.reverse();
                      Future.delayed(const Duration(milliseconds: 280), () {
                        if (!mounted) return;
                        setState(() => _showWinOverlay = false);
                      });
                    },
                    child: Center(
                      child: _WinToast(
                        animation: CurvedAnimation(
                          parent: _winBanner,
                          curve: Curves.easeOutBack,
                          reverseCurve: Curves.easeIn,
                        ),
                        title: 'شما برنده شدید! 🎉',
                        subtitle: 'برای ادامه کلیک کنید',
                        movesText: _toFaDigits(moves),
                        timeText: _formatTime(seconds),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Slider of asset images
// ------------------------------------------------------------
class _AssetSlider extends StatefulWidget {
  final List<String> assets;
  final List<Uint8List> userImages; // گالری تصاویر کاربر
  final String? selectedId; // مسیر asset یا '__USER__'
  final ValueChanged<String> onSelect;
  const _AssetSlider({
    required this.assets,
    required this.selectedId,
    required this.onSelect,
    this.userImages = const [],
  });
  @override
  State<_AssetSlider> createState() => _AssetSliderState();
}

class _AssetSliderState extends State<_AssetSlider> {
  final _controller = ScrollController();
  static const _thumbWidth = 96.0;
  static const _thumbSelectedWidth = 176.0;
  static const _thumbMarginH = 6.0; // دو طرف هر آیتم

  List<String> get _allItems {
    final userIds = List<String>.generate(
      widget.userImages.length,
      (i) => 'USER:$i',
    );
    return [...userIds, ...widget.assets];
  }

  @override
  void didUpdateWidget(covariant _AssetSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.userImages.length != widget.userImages.length) {
      // پس از یک فریم تا layout انجام شود
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
  }

  void _centerSelected() {
    if (!_controller.hasClients) return;
    final items = _allItems;
    final selId = widget.selectedId;
    if (selId == null) return;

    // یافتن ایندکس آیتم انتخاب‌شده
    int index = items.indexOf(selId);
    if (index < 0) return;

    // محاسبه آفست با توجه به عرض متفاوت آیتم انتخاب‌شده
    double offsetBefore = 0;
    for (int i = 0; i < index; i++) {
      // تا قبل از ایندکس انتخاب‌شده، همگی غیرانتخابی‌اند
      offsetBefore += _thumbWidth + (_thumbMarginH * 2);
    }
    final selItemWidth = _thumbSelectedWidth;
    final selCenter = offsetBefore + selItemWidth / 2;
    final viewport = _controller.position.viewportDimension;
    final targetCenterOffset = selCenter - viewport / 2;
    final maxScroll = _controller.position.maxScrollExtent;
    final clamped = targetCenterOffset.clamp(0, maxScroll);
    _controller.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _allItems;
    return SizedBox(
      height: 200,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final id = items[i];
          final isUser = id.startsWith('USER:');
          final isSel = id == widget.selectedId;
          final baseWidth = isSel ? _thumbSelectedWidth : _thumbWidth;
          final marginV = isSel ? 10.0 : 10.0;
          return _SliderThumb(
            index: i,
            selected: isSel,
            onTap: () => widget.onSelect(id),
            accent: theme.colorScheme.primary,
            isUser: isUser,
            bytes: isUser
                ? widget.userImages[int.tryParse(id.split(':')[1]) ?? 0]
                : null,
            assetPath: isUser ? null : id,
            width: baseWidth,
            margin: EdgeInsets.symmetric(
              horizontal: _thumbMarginH,
              vertical: marginV,
            ),
          );
        },
      ),
    );
  }
}

class _SliderThumb extends StatefulWidget {
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final bool isUser; // آیا تصویر کاربر است
  final Uint8List? bytes; // داده‌های تصویر کاربر
  final String? assetPath; // مسیر asset
  final double? width;
  final EdgeInsetsGeometry? margin;
  const _SliderThumb({
    required this.index,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.isUser = false,
    this.bytes,
    this.assetPath,
    this.width,
    this.margin,
  });
  @override
  State<_SliderThumb> createState() => _SliderThumbState();
}

class _SliderThumbState extends State<_SliderThumb>
    with SingleTickerProviderStateMixin {
  double _hover = 0;
  late AnimationController _shine;
  @override
  void initState() {
    super.initState();
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    setState(() => _hover = v ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    // بزرگ‌نمایی واضح‌تر برای آیتم انتخاب‌شده
    final scale = sel ? 1.10 + 0.04 * _hover : 0.88 + 0.06 * _hover;
    final borderGrad = sel
        ? LinearGradient(
            colors: [
              const Color(0xFFFF80EA),
              const Color(0xFF00E5FF),
              const Color(0xFF72F1B8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return Container(
      width: widget.width ?? 96,
      margin:
          widget.margin ??
          const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: MouseRegion(
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: _SquareAwareThumb(
              square: !sel,
              borderGrad: borderGrad,
              shineAnim: _shine,
              isSelected: sel,
              isUser: widget.isUser,
              bytes: widget.bytes,
              assetPath: widget.assetPath,
            ),
          ),
        ),
      ),
    );
  }
}

// Internal reusable piece that can enforce square shape when needed
class _SquareAwareThumb extends StatelessWidget {
  final bool square;
  final Gradient borderGrad;
  final AnimationController shineAnim;
  final bool isSelected;
  final bool isUser;
  final Uint8List? bytes;
  final String? assetPath;
  const _SquareAwareThumb({
    required this.square,
    required this.borderGrad,
    required this.shineAnim,
    required this.isSelected,
    required this.isUser,
    this.bytes,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: const Color(0xFFFF6EC7).withValues(alpha: 0.55),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Stack(
        children: [
          // Outer gradient border
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: borderGrad,
            ),
            padding: const EdgeInsets.all(3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isUser)
                    (bytes != null
                        ? Image.memory(bytes!, fit: BoxFit.cover)
                        : const ColoredBox(color: Colors.black12))
                  else
                    Image.asset(assetPath!, fit: BoxFit.cover),
                  // Subtle parallax / shine overlay
                  AnimatedBuilder(
                    animation: shineAnim,
                    builder: (_, __) {
                      final t = shineAnim.value;
                      return IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1 + 2 * t, -1),
                              end: Alignment(1 + 2 * t, 1),
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(
                                  alpha: isSelected ? 0.18 : 0.07,
                                ),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Dark overlay when not selected
                  if (!isSelected)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.45),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  // Selection bottom glow
                  if (isSelected)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF141414).withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return square ? AspectRatio(aspectRatio: 1, child: tile) : tile;
  }
}

class _FancyFrame extends StatelessWidget {
  final Widget child;
  const _FancyFrame({required this.child});
  @override
  Widget build(BuildContext context) {
    // قاب کاملاً مخفی: بدون دکوراسیون و پدینگ
    return child;
  }
}

class _PuzzleView extends StatelessWidget {
  final PuzzleBoard board;
  final int dimension;
  final ui.Image? image;
  final void Function(int tileArrayIndex) onTileTap;
  final List<ui.Image?>? slices;
  // fastMode حذف شد
  const _PuzzleView({
    required this.board,
    required this.dimension,
    required this.image,
    required this.onTileTap,
    required this.slices,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileSize = constraints.maxWidth / dimension;
          if (image == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            children: [
              // پس‌زمینه روشن داخل برد برای سفیدتر و درخشان‌تر شدن پشت تایل‌ها
              Positioned.fill(child: Container(color: Colors.transparent)),
              for (int i = 0; i < board.tiles.length - 1; i++)
                _buildTile(context, board.tiles[i], tileSize),
              // وقتی حل شد، تصویر کامل را با انیمیشن فید بالای تایل‌ها نشان بده
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                    opacity: board.isSolved ? 1.0 : 0.0,
                    child: CustomPaint(
                      painter: _ImagePainter(image!, dimension: 1),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTile(BuildContext context, Tile tile, double tileSize) {
    final row = tile.currentIndex ~/ dimension;
    final col = tile.currentIndex % dimension;
    final correctPos = tile.correctIndex;
    final correctRow = correctPos ~/ dimension;
    final correctCol = correctPos % dimension;
    // حذف افکت کج و حرکت عمودی – بازگشت به حالت ثابت
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      left: col * tileSize,
      top: row * tileSize,
      width: tileSize,
      height: tileSize,
      child: _AnimatedTapScale(
        onTap: () => onTileTap(board.tiles.indexOf(tile)),
        child: _TileContent(
          image: image,
          dimension: dimension,
          correctRow: correctRow,
          correctCol: correctCol,

          isCorrect: tile.inCorrectPlace,
          slice:
              slices != null && tile.correctIndex < (dimension * dimension - 1)
              ? slices![tile.correctIndex]
              : null,
        ),
      ),
    );
  }
}

class _TileContent extends StatelessWidget {
  final ui.Image? image;
  final int dimension;
  final int correctRow;
  final int correctCol;
  final bool isCorrect;
  final ui.Image? slice;
  // fastMode حذف شد
  const _TileContent({
    required this.image,
    required this.dimension,
    required this.correctRow,
    required this.correctCol,
    required this.isCorrect,
    required this.slice,
  });

  @override
  Widget build(BuildContext context) {
    final correctGlow = isCorrect
        ? [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.9),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Color(0xFFFF6EC7),
              blurRadius: 32,
              spreadRadius: -2,
            ),
          ]
        : [
            // سایه تیره تایل‌ها نرم‌تر و کم‌عمق‌تر شد
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutQuad,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCorrect
              ? const Color(0xFFFF6EC7).withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.45),
          width: isCorrect ? 2.2 : 1.2,
        ),
        boxShadow: correctGlow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            (slice != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: RawImage(
                      image: slice,
                      filterQuality: FilterQuality.high,
                    ),
                  )
                : (image != null
                      ? CustomPaint(
                          painter: _ImagePainter(
                            image!,
                            dimension: dimension,
                            clipRow: correctRow,
                            clipCol: correctCol,
                          ),
                        )
                      : const SizedBox.shrink())),
            // شماره تایل حذف شد
            // افکت اختصاصی حالت بدون تصویر حذف شد
          ],
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final int dimension;
  final int? clipRow;
  final int? clipCol;

  _ImagePainter(
    this.image, {
    required this.dimension,
    this.clipRow,
    this.clipCol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;
    final srcRect = () {
      if (clipRow == null || clipCol == null) {
        return Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
      }
      final tileW = image.width / dimension;
      final tileH = image.height / dimension;
      return Rect.fromLTWH(clipCol! * tileW, clipRow! * tileH, tileW, tileH);
    }();
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.dimension != dimension ||
        oldDelegate.clipRow != clipRow ||
        oldDelegate.clipCol != clipCol;
  }
}

// کلاس _PatternPainter حذف شد (حالت کوررنگی)

// ------------------------------------------------------------
// Full-screen background cover painter (for transparent bg image)
// ------------------------------------------------------------
class _CoverImagePainter extends CustomPainter {
  final ui.Image image;
  _CoverImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final dstW = size.width;
    final dstH = size.height;
    if (imgW == 0 || imgH == 0 || dstW == 0 || dstH == 0) return;

    // BoxFit.cover
    final scale = max(dstW / imgW, dstH / imgH);
    final drawW = imgW * scale;
    final drawH = imgH * scale;
    final dx = (dstW - drawW) / 2;
    final dy = (dstH - drawH) / 2;

    final src = Rect.fromLTWH(0, 0, imgW, imgH);
    final dst = Rect.fromLTWH(dx, dy, drawW, drawH);
    final paint = Paint();
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _CoverImagePainter oldDelegate) =>
      oldDelegate.image != image;
}

// ------------------------------------------------------------
// Modern Background: faint image with blur, desaturation, vignette
// ------------------------------------------------------------
class _ModernBackground extends StatelessWidget {
  final ui.Image? image;
  final bool dark;
  final Color primary;
  const _ModernBackground({
    required this.image,
    required this.dark,
    required this.primary,
  });

  static List<double> _saturationMatrix(double s) {
    // s=1 original, s=0 grayscale
    const lumR = 0.213, lumG = 0.715, lumB = 0.072;
    final inv = 1 - s;
    final r = inv * lumR;
    final g = inv * lumG;
    final b = inv * lumB;
    return <double>[
      r + s,
      g,
      b,
      0,
      0,
      r,
      g + s,
      b,
      0,
      0,
      r,
      g,
      b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Base surface color
    final base = dark ? const Color(0xFF0E0F12) : Colors.white;
    final vignetteColor = Colors.black.withValues(alpha: dark ? 0.30 : 0.12);
    final topScrim = (dark ? Colors.black : Colors.white).withValues(
      alpha: dark ? 0.18 : 0.06,
    );
    final tint = primary.withValues(alpha: dark ? 0.06 : 0.04);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        if (image != null)
          IgnorePointer(
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(_saturationMatrix(0.70)),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Opacity(
                  opacity: dark ? 0.40 : 0.52,
                  child: CustomPaint(painter: _CoverImagePainter(image!)),
                ),
              ),
            ),
          ),
        // Subtle color tint from primary
        IgnorePointer(child: Container(color: tint)),
        // Soft top scrim to improve contrast under app bar/controls
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topScrim, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Vignette around edges
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [Colors.transparent, vignetteColor],
                stops: const [0.70, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// Animated Gradient Background + Blobs
// ------------------------------------------------------------
// AnimatedBackground & _BlobPainter حذف شدند تا پس زمینه کاملا سفید باشد

// عنوان گرادیانی حذف شد زیرا هدری در بالا نداریم

// ------------------------------------------------------------
// Rainbow Title (gradient text)
// ------------------------------------------------------------
class _RainbowTitle extends StatelessWidget {
  final String text;
  const _RainbowTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = const [
      Color(0xFFFF6EC7),
      Color(0xFFFFD36E),
      Color(0xFF72F1B8),
      Color(0xFF00E5FF),
      Color(0xFF9B6BFF),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // پشت‌نویس محو برای خوانایی بهتر روی پس‌زمینه
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.vazirmatn(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: Colors.black.withValues(alpha: 0.18),
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                colors: colors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.vazirmatn(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularGlassButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? baseColor;
  const _CircularGlassButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.baseColor,
  });
  @override
  Widget build(BuildContext context) {
    final c = baseColor ?? (Theme.of(context).colorScheme.primary);
    final bright = c.withValues(alpha: 0.95);
    final soft = c.withValues(alpha: 0.55);
    final btn = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [bright, soft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.65),
              blurRadius: 10,
              spreadRadius: -4,
            ),
          ],
        ),
        child: IconTheme(
          data: IconThemeData(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
            size: 26,
          ),
          child: Center(child: icon),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

// ------------------------------------------------------------
// Bottom Action Bar
// ------------------------------------------------------------
class _ActionBar extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onShuffleIncorrect;
  final VoidCallback onReset;
  final void Function(int) onChangeDim;
  final int dimension;
  final bool darkMode;
  final VoidCallback onToggleDark;
  final bool showDelete;
  final Future<void> Function()? onDelete;
  const _ActionBar({
    required this.onPickImage,
    required this.onShuffleIncorrect,
    required this.onReset,
    required this.onChangeDim,
    required this.dimension,
    required this.darkMode,
    required this.onToggleDark,
    this.showDelete = false,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    // برای چسبیدن کامل به پایین، padding پایینی قبلی حذف شد.
    // اگر بخواهید فضای امن (SafeArea) موبایل‌های ناچ‌دار حفظ شود، می‌توانید SafeArea را فعال کنید.
    // در حال حاضر عمداً از SafeArea صرفنظر شده تا کاملاً به لبه بچسبد. در صورت نیاز:
    // return SafeArea(top: false, child: ...)
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 18, // فاصله بیشتر بین دکمه‌ها
          runSpacing: 16, // فاصله بیشتر بین ردیف‌ها
          children: [
            _CircularGlassButton(
              icon: const Icon(Icons.image_outlined),
              onTap: onPickImage,
              tooltip: 'انتخاب تصویر',
              baseColor: const Color(0xFF34C3FF),
            ),
            _CircularGlassButton(
              icon: const Icon(Icons.auto_fix_high),
              onTap: onShuffleIncorrect,
              tooltip: 'تغییر نامرتب‌ها',
              baseColor: const Color(0xFF9B6BFF),
            ),
            // دکمه نمایش/مخفی شماره‌ها حذف شد (همیشه نمایش داده می‌شود)
            _CircularGlassButton(
              icon: const Icon(Icons.refresh),
              onTap: onReset,
              tooltip: 'شروع دوباره',
              baseColor: const Color(0xFFFF5A5F),
            ),
            PopupMenuButton<int>(
              tooltip: 'ابعاد',
              onSelected: onChangeDim,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              itemBuilder: (_) => [3, 4, 5]
                  .map(
                    (e) => PopupMenuItem(
                      value: e,
                      child: Text(
                        '🧩 ${_toFaDigits('$e×$e')}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                  .toList(),
              child: IgnorePointer(
                child: _CircularGlassButton(
                  icon: const Icon(Icons.grid_on),
                  onTap: () {},
                  tooltip: 'ابعاد',
                  baseColor: const Color(0xFF58D66D),
                ),
              ),
            ),
            _CircularGlassButton(
              icon: Icon(darkMode ? Icons.light_mode : Icons.dark_mode),
              onTap: onToggleDark,
              tooltip: darkMode ? 'حالت روشن' : 'حالت تیره',
              baseColor: const Color(0xFFFF78D5),
            ),
            // دکمه حالت کوررنگی حذف شد
            if (showDelete && onDelete != null)
              _CircularGlassButton(
                icon: const Icon(Icons.delete_forever_outlined),
                onTap: () async {
                  try {
                    await onDelete!();
                  } catch (e) {
                    final ctx = context;
                    // تلاش برای نمایش خطا به کاربر
                    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                      SnackBar(content: Text('خطا در حذف عکس: $e')),
                    );
                  }
                },
                tooltip: 'حذف این عکس',
                baseColor: const Color(0xFFEF5350),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Animated tap scale wrapper
// ------------------------------------------------------------
class _AnimatedTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _AnimatedTapScale({required this.child, required this.onTap});
  @override
  State<_AnimatedTapScale> createState() => _AnimatedTapScaleState();
}

class _AnimatedTapScaleState extends State<_AnimatedTapScale> {
  double _scale = 1;
  void _down(_) => setState(() => _scale = 0.92);
  void _up(_) => setState(() => _scale = 1);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: () => setState(() => _scale = 1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ------------------------------------------------------------
// Win Dialog
// ------------------------------------------------------------
// ------------------------------------------------------------
// Win Toast (animated, tappable overlay)
// ------------------------------------------------------------
class _WinToast extends StatelessWidget {
  final Animation<double> animation;
  final String title;
  final String subtitle;
  final String movesText;
  final String timeText;
  const _WinToast({
    required this.animation,
    required this.title,
    required this.subtitle,
    required this.movesText,
    required this.timeText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = Tween<double>(begin: 0.85, end: 1.0).animate(animation);
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(
          scale: scale,
          child: _WhiteWinBox(
            title: title,
            subtitle: subtitle,
            movesText: movesText,
            timeText: timeText,
            accent: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

// Crisp white colorful box used inside the overlay
class _WhiteWinBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final String movesText;
  final String timeText;
  final Color accent;
  const _WhiteWinBox({
    required this.title,
    required this.subtitle,
    required this.movesText,
    required this.timeText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final gradientBorder = const LinearGradient(
      colors: [
        Color(0xFFFF6EC7),
        Color(0xFFFFD36E),
        Color(0xFF72F1B8),
        Color(0xFF00E5FF),
        Color(0xFF9B6BFF),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    Widget chip({
      required Color from,
      required Color to,
      required Widget child,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [from, to]),
          boxShadow: [
            BoxShadow(color: from.withValues(alpha: 0.35), blurRadius: 12),
          ],
        ),
        child: DefaultTextStyle(
          style: GoogleFonts.vazirmatn(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          child: child,
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 460),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradientBorder,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.25),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header with trophy and title
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [accent, const Color(0xFFFF6EC7)],
                    ),
                  ),
                  child: const Icon(Icons.emoji_events, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.vazirmatn(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.vazirmatn(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            // Chips row
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                chip(
                  from: const Color(0xFFFF6EC7),
                  to: const Color(0xFFFF8FE3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [const Text('🔢 '), Text('حرکت: $movesText')],
                  ),
                ),
                chip(
                  from: const Color(0xFF00E5FF),
                  to: const Color(0xFF72F1B8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [const Text('⏱️ '), Text('زمان: $timeText')],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Particles Painter (simple radial burst)
// ------------------------------------------------------------
class ParticleBurstPainter extends CustomPainter {
  final double progress; // 0..1
  final int seed;
  ParticleBurstPainter({required this.progress, required this.seed});
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final rnd = Random(seed);
    final count = 140;
    for (int i = 0; i < count; i++) {
      final ang = (i / count) * 2 * pi + rnd.nextDouble() * 0.5;
      final speed = 80 + rnd.nextDouble() * 260;
      final radius = Curves.easeOut.transform(progress) * speed;
      final pos = center + Offset(cos(ang), sin(ang)) * radius;
      final sizeP = 3 + rnd.nextDouble() * 6 * (1 - progress);
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFF6EC7),
          const Color(0xFF00E5FF),
          (i / count),
        )!.withValues(alpha: 1 - progress);
      canvas.drawCircle(pos, sizeP, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ------------------------------------------------------------
// END ADDITIONS
// ------------------------------------------------------------

void main() {
  runApp(const MainApp());
}
