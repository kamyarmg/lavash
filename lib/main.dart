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

String _toFaDigits(dynamic input) {
  final persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  return input.toString().replaceAllMapped(
    RegExp(r'\d'),
    (m) => persian[int.parse(m[0]!)],
  );
}

class Tile {
  final int correctIndex;
  int currentIndex;
  Tile({required this.correctIndex, required this.currentIndex});

  bool get inCorrectPlace => correctIndex == currentIndex;
}

class PuzzleBoard {
  final int dimension;
  final List<Tile> tiles;

  PuzzleBoard._(this.dimension, this.tiles);

  factory PuzzleBoard.solved(int dim) {
    final total = dim * dim;
    final tiles = List.generate(
      total,
      (i) => Tile(correctIndex: i, currentIndex: i),
    );
    return PuzzleBoard._(dim, tiles);
  }

  int get emptyTileIndex => tiles.length - 1;

  bool get isSolved => tiles.every((t) => t.inCorrectPlace);

  List<int> movableTileArrayIndexes() {
    final emptyPos = tiles[emptyTileIndex].currentIndex;
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

class _SavedGame {
  final int dim;
  final List<int> tileCurrents;
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
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  int dimension = 3;
  late PuzzleBoard board;
  ui.Image? image;
  final rng = Random();

  String? _selectedId;

  List<Uint8List> _userImages = [];
  List<String> _userEntries = [];
  Timer? _timer;
  int seconds = 0;
  int moves = 0;

  bool darkMode = false;

  bool _justSolved = false;
  late AnimationController _solveParticles;

  bool _showWinOverlay = false;
  late AnimationController _winBanner;

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
  int _themeIdx = 0;

  int? bestMoves;
  int? bestTime;

  List<ui.Image?>? _slices;

  static const String _kPrefDark = 'settings.darkMode';
  static const String _kPrefDim = 'settings.dimension';
  static const String _kPrefLastImage = 'settings.lastImage';
  static const String _kPrefUserImages = 'settings.userImages';

  static const String _kGameDim = 'game.dimension';
  static const String _kGameTiles = 'game.tiles';
  static const String _kGameMoves = 'game.moves';
  static const String _kGameSeconds = 'game.seconds';
  static const String _kGameSolved = 'game.solved';

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);

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

  Future<void> _setDark(bool value) async {
    if (darkMode == value) return;
    setState(() => darkMode = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefDark, darkMode);
  }

  List<String> _assetImages = [];
  bool _imagesLoaded = false;

  Future<void> _loadAssetImagesList() async {
    if (_imagesLoaded) return;

    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

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

      _assetImages.sort();

      if (mounted) setState(() {});
    } catch (e) {
      _assetImages = [
        'assets/images/1.jpg',
        'assets/images/2.jpg',
        'assets/images/3.jpg',
        'assets/images/4.jpg',
        'assets/images/5.jpg',
      ];
      _imagesLoaded = true;
    }
  }

  Future<void> _loadRandomAssetImage() async {
    try {
      await _loadAssetImagesList();

      if (_assetImages.isEmpty) {
        return;
      }

      final pick = _assetImages[rng.nextInt(_assetImages.length)];
      await _loadAssetImage(pick);
    } catch (e) {
      return;
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
      });

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, path);
      if (forResume) {
        await _buildSlices();
      } else {
        await _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
      }
    } catch (e) {
      return;
    }
  }

  String _userId(int index) => 'USER:$index';

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
      return;
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

      setState(() {
        image = frame.image;

        _selectedId = _userId(0);
      });

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, entry);
      await _saveUserImagesList();

      _clearGameState();
      _reset(shuffle: true);
      _buildSlices();
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
    } catch (_) {}
  }

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

    final entry = _userEntries[idx];
    if (entry.startsWith('FILE://')) {
      final path = entry.substring(7);
      await deleteFileIfExists(path);
    }

    setState(() {
      _userEntries.removeAt(idx);
      _userImages.removeAt(idx);
    });
    await _saveUserImagesList();

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

  void _showHelp() {
    final ctx = _navKey.currentContext ?? context;
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.32,
            maxChildSize: 0.95,
            builder: (context, sc) => Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                controller: sc,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.36),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'نحوه بازی:',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'تصویر (انتخابی شما یاانتخاب شده توسط برنامه)به قطعاتی که شما تنظیم کرده‌اید(پیش فرض ۳ در ۳) به همراه یک خانه خالی تقسیم می‌شود. با زدن هر قطعهٔ مجاور خانهٔ خالی آن قطعه جایگزین می‌شود. هدف این است که همهٔ قطعات را به جای درستشان برگردانید و تصویر اصلی را درست کنید.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'دکمه‌ها و امکانات:',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Controls with icons
                      _helpItemRow(
                        Icons.image_outlined,
                        const Color(0xFF34C3FF),
                        'انتخاب تصویر',
                        'از گالری عکسی انتخاب کنید تا بازی جدید با عکس انتخابی شما شروع شود. عکس انتخابی شما ذخیره میشود تا بعدا نیز استفاده شود.',
                      ),
                      _helpItemRow(
                        Icons.auto_fix_high,
                        const Color(0xFF9B6BFF),
                        'تغییر نامرتب‌ها',
                        'چند قطعهٔ نامرتب را جابه‌جا می‌کند تا چیدمان عوض شود.',
                      ),
                      _helpItemRow(
                        Icons.refresh,
                        const Color(0xFFFF5A5F),
                        'شروع دوباره',
                        'بازی را از ابتدا و با یک تصویر رندم شروع می‌کند.',
                      ),
                      _helpItemRow(
                        Icons.settings,
                        const Color(0xFF607D8B),
                        'تنظیمات',
                        'از طریق منوی تنظیمات می‌توانید حالت روشن/تیره و رنگ تم را تغییر دهید و ابعاد پازل را بین ۳×۳، ۴×۴ یا ۵×۵ تنظیم کنید.',
                      ),
                      _helpItemRow(
                        Icons.delete_forever_outlined,
                        const Color(0xFFEF5350),
                        'حذف عکس',
                        'برای تصاویری که کاربر انتخاب کرده فعال است و می‌توانید تصاویر انتخابی خودتان را حذف کنید.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'امتیاز و زمان:',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'در پایان بازی و در صورت برنده شدن، تعداد حرکت‌ها و زمان صرف‌شده نمایش داده می‌شود.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'نکات مفید:',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• در صورتیکه تایلی در جای مناسب و درست خود قرار گیرد هاله‌ای روشن دور آن روشن میشود.\n• تنظمیات انتخابی شما برای تم یا/ابعاد/تصاویر انتخابی شما ذخیره میشود تا دفعات بعدی هم استفاده شود.\n• بازی ذخیره می‌شود و می‌توانید بعداً از همان جایی که خارج شده‌اید ادامه دهید یا بازدن شروع دوباره بازی جدیدی را آغاز کنید.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.vazirmatn(),
                      ),
                      const SizedBox(height: 18),

                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'بستن',
                          style: GoogleFonts.vazirmatn(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _helpItemRow(IconData icon, Color color, String title, String desc) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(desc, textAlign: TextAlign.right),
              ],
            ),
          ),
        ],
      ),
    );
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

    _clearGameState();
  }

  void _changeDimension(int d) {
    dimension = d;
    _reset(shuffle: true);
    _loadRecords();

    SharedPreferences.getInstance().then((sp) => sp.setInt(_kPrefDim, d));
  }

  void _openSettings() {
    final ctx = _navKey.currentContext ?? context;
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.45,
            minChildSize: 0.30,
            maxChildSize: 0.80,
            builder: (context, sc) => Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                controller: sc,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: StatefulBuilder(
                    builder: (context, setSheet) {
                      bool isDark = darkMode;
                      int dim = dimension;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.36),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'تنظیمات',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.vazirmatn(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: Text(
                              'حالت تیره',
                              style: GoogleFonts.vazirmatn(),
                            ),
                            value: isDark,
                            onChanged: (v) async {
                              setSheet(() => isDark = v);
                              await _setDark(v);
                            },
                            secondary: const Icon(Icons.dark_mode),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          const SizedBox(height: 6),
                          const Divider(),
                          const SizedBox(height: 6),
                          Text(
                            'ابعاد پازل',
                            style: GoogleFonts.vazirmatn(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final d in const [3, 4, 5])
                                ChoiceChip(
                                  label: Text(
                                    '🧩 ${_toFaDigits('$d×$d')}',
                                    style: GoogleFonts.vazirmatn(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  selected: dim == d,
                                  onSelected: (_) {
                                    setSheet(() => dim = d);
                                    _changeDimension(d);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'بستن',
                              style: GoogleFonts.vazirmatn(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onTileTap(int tileArrayIndex) {
    if (board.isSolved) return;
    final moved = board.move(tileArrayIndex);
    if (moved) {
      moves++;
      setState(() {});

      _saveGameState();
      if (board.isSolved) {
        _timer?.cancel();
        _saveRecordIfBetter();

        _saveGameState(solved: true);
        _justSolved = true;
        _solveParticles.forward(from: 0);
        HapticFeedback.mediumImpact();

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

  Future<void> _loadFileImage(String filePath, {bool forResume = false}) async {
    await Future<void>.delayed(Duration.zero);
    try {
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

  Future<void> _loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    final savedDark = sp.getBool(_kPrefDark);
    final savedDim = sp.getInt(_kPrefDim);
    final savedImage = sp.getString(_kPrefLastImage);
    final savedThemeIdx = sp.getInt(_kPrefThemeIdx);

    final savedGame = await _readSavedGame();

    if (savedDark != null) darkMode = savedDark;
    if (savedThemeIdx != null &&
        savedThemeIdx >= 0 &&
        savedThemeIdx < _seedPalette.length) {
      _themeIdx = savedThemeIdx;
    }

    if (savedGame != null && !savedGame.solved) {
      dimension = savedGame.dim;
    } else if (savedDim != null && savedDim >= 3 && savedDim <= 8) {
      dimension = savedDim;
    }

    if (mounted) setState(() {});
    _loadRecords();

    await _loadAssetImagesList();

    await _loadUserImagesList();

    final bool resumePlanned = savedGame != null && !savedGame.solved;
    if (savedImage != null) {
      if (savedImage.startsWith('B64://')) {
        final b64 = savedImage.substring(6);
        try {
          final data = base64Decode(b64);

          _addUserEntry('B64://$b64', data);
          await _saveUserImagesList();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          if (mounted) {
            setState(() {
              image = frame.image;

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
        final path = savedImage.substring(7);
        await _loadFileImage(path, forResume: resumePlanned);
      } else {
        await _loadRandomAssetImage();
      }
    } else {
      await _loadRandomAssetImage();
    }

    if (resumePlanned) {
      _applySavedGame(savedGame);
      _startTimer(resetSeconds: false);
    } else {
      _reset(shuffle: true);
    }
  }

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
              Positioned.fill(
                child: _ModernBackground(
                  image: image,
                  dark: darkMode,
                  primary: Theme.of(context).colorScheme.primary,
                ),
              ),

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
                  final availableHeight = constraints.maxHeight;
                  final availableWidth = constraints.maxWidth;

                  final bottomBarSpace = 80.0;

                  final sliderHeight = 200.0;

                  final remainingHeight =
                      availableHeight - bottomBarSpace - sliderHeight;

                  final maxBoard = min(
                    availableWidth * 0.9,
                    remainingHeight * 0.7,
                  ).clamp(240.0, 720.0);

                  final remainingVerticalSpace = remainingHeight - maxBoard;
                  final verticalSpacing = (remainingVerticalSpace / 3).clamp(
                    10.0,
                    50.0,
                  );

                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        availableWidth * 0.03,
                        verticalSpacing,
                        availableWidth * 0.03,
                        bottomBarSpace,
                      ),
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              SizedBox(height: verticalSpacing),
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
                              SizedBox(height: verticalSpacing),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ActionBar(
                  onPickImage: _pickImage,
                  onShuffleIncorrect: () =>
                      setState(() => board.partialShuffleIncorrect(rng)),
                  onReset: () => _loadRandomAssetImage(),
                  onOpenSettings: _openSettings,
                  onHelp: _showHelp,
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

class _AssetSlider extends StatefulWidget {
  final List<String> assets;
  final List<Uint8List> userImages;
  final String? selectedId;
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
  static const _thumbMarginH = 6.0;

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

    int index = items.indexOf(selId);
    if (index < 0) return;

    double offsetBefore = 0;
    for (int i = 0; i < index; i++) {
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
  final bool isUser;
  final Uint8List? bytes;
  final String? assetPath;
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
    return child;
  }
}

class _PuzzleView extends StatelessWidget {
  final PuzzleBoard board;
  final int dimension;
  final ui.Image? image;
  final void Function(int tileArrayIndex) onTileTap;
  final List<ui.Image?>? slices;

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
              Positioned.fill(child: Container(color: Colors.transparent)),
              for (int i = 0; i < board.tiles.length - 1; i++)
                _buildTile(context, board.tiles[i], tileSize),

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

        IgnorePointer(child: Container(color: tint)),

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

class _ActionBar extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onShuffleIncorrect;
  final VoidCallback onReset;
  final VoidCallback onOpenSettings;
  final VoidCallback? onHelp;
  final bool showDelete;
  final Future<void> Function()? onDelete;
  const _ActionBar({
    required this.onPickImage,
    required this.onShuffleIncorrect,
    required this.onReset,
    required this.onOpenSettings,
    this.onHelp,
    this.showDelete = false,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 16,
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

            _CircularGlassButton(
              icon: const Icon(Icons.refresh),
              onTap: onReset,
              tooltip: 'شروع دوباره',
              baseColor: const Color(0xFFFF5A5F),
            ),
            _CircularGlassButton(
              icon: const Icon(Icons.settings),
              onTap: onOpenSettings,
              tooltip: 'تنظیمات',
              baseColor: const Color(0xFF607D8B),
            ),

            if (onHelp != null)
              _CircularGlassButton(
                icon: const Icon(Icons.help_outline),
                onTap: onHelp!,
                tooltip: 'راهنما',
                baseColor: const Color(0xFF34C3FF),
              ),

            if (showDelete && onDelete != null)
              _CircularGlassButton(
                icon: const Icon(Icons.delete_forever_outlined),
                onTap: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  try {
                    await onDelete!();
                  } catch (e) {
                    messenger?.showSnackBar(
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

class SettingsPage extends StatelessWidget {
  final bool darkMode;
  final int themeIndex;
  final List<Color> seedPalette;
  final int dimension;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<int> onThemeIndexChanged;
  final ValueChanged<int> onDimensionChanged;

  const SettingsPage({
    super.key,
    required this.darkMode,
    required this.themeIndex,
    required this.seedPalette,
    required this.dimension,
    required this.onDarkChanged,
    required this.onThemeIndexChanged,
    required this.onDimensionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تنظیمات',
          style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('تم', style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SwitchListTile(
            title: Text('حالت تیره', style: GoogleFonts.vazirmatn()),
            value: darkMode,
            onChanged: onDarkChanged,
            secondary: const Icon(Icons.dark_mode),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          Text(
            'رنگ تم',
            style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (int i = 0; i < seedPalette.length; i++)
                _ThemeColorDot(
                  color: seedPalette[i],
                  selected: i == themeIndex,
                  onTap: () => onThemeIndexChanged(i),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 24),
          const SizedBox(height: 8),
          Text(
            'ابعاد پازل',
            style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final d in const [3, 4, 5])
                ChoiceChip(
                  label: Text(
                    '🧩 ${_toFaDigits('$d×$d')}',
                    style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
                  ),
                  selected: dimension == d,
                  onSelected: (_) => onDimensionChanged(d),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check),
            label: Text(
              'بستن',
              style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: border.withValues(alpha: 0.9), width: 2),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
          ],
        ),
      ),
    );
  }
}

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

class ParticleBurstPainter extends CustomPainter {
  final double progress;
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

void main() {
  runApp(const MainApp());
}
