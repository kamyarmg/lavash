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

import '../core/image_utils.dart';
import '../core/strings.dart';
import '../core/utils.dart';
import '../models/puzzle.dart';
import '../widgets/puzzle_widgets.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override
  State<MainApp> createState() => _MainAppState();
}

class _SavedGame {
  /// Minimal snapshot to restore a game:
  /// - [dim]: board dimension (e.g., 3, 4, 5)
  /// - [tileCurrents]: each tile's current grid index (CSV in storage)
  /// - [moves], [seconds]: progress counters
  /// - [solved]: whether the saved board was already solved
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
  bool darkMode = true;
  bool _showTileNumbers = false;
  bool _soundEnabled = true;
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
  static const String _kPrefLanguage = 'settings.language';
  AppLanguage _language = AppLanguage.fa;
  int? bestMoves;
  int? bestTime;
  List<ui.Image?>? _slices;
  static const String _kPrefDark = 'settings.darkMode';
  static const String _kPrefDim = 'settings.dimension';
  static const String _kPrefLastImage = 'settings.lastImage';
  static const String _kPrefUserImages = 'settings.userImages';
  static const String _kPrefShowNumbers = 'settings.showNumbers';
  static const String _kPrefClickSound = 'settings.clickSound';
  static const String _kGameDim = 'game.dimension';
  static const String _kGameTiles = 'game.tiles';
  static const String _kGameMoves = 'game.moves';
  static const String _kGameSeconds = 'game.seconds';
  static const String _kGameSolved = 'game.solved';

  List<String> _assetImages = [];
  bool _imagesLoaded = false;

  @override
  void initState() {
    super.initState();
    // Start with a solvable random board; image will be picked/loaded later.
    board = PuzzleBoard.solved(dimension).shuffled(rng);
    _loadSettings();
    _winBanner = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 300),
    );
  }

  Strings get S => Strings(_language);

  Future<void> _setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    setState(() => _language = lang);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrefLanguage, lang == AppLanguage.fa ? 'fa' : 'en');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _winBanner.dispose();
    super.dispose();
  }

  void _startTimer({bool resetSeconds = true}) {
    _timer?.cancel();
    if (resetSeconds) seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || board.isSolved) return;
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

  Future<void> _setShowNumbers(bool value) async {
    if (_showTileNumbers == value) return;
    setState(() => _showTileNumbers = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefShowNumbers, _showTileNumbers);
  }

  Future<void> _setClickSound(bool value) async {
    if (_soundEnabled == value) return;
    setState(() => _soundEnabled = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefClickSound, _soundEnabled);
  }

  Future<void> _loadAssetImagesList() async {
    // Reads AssetManifest at runtime and lists images under assets/images/.
    // Falls back to a small fixed set if manifest isn't accessible.
    if (_imagesLoaded) return;
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final imageAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/images/'))
          .where(
            (key) =>
                key.toLowerCase().endsWith('.jpg') ||
                key.toLowerCase().endsWith('.jpeg') ||
                key.toLowerCase().endsWith('.png') ||
                key.toLowerCase().endsWith('.webp'),
          )
          .toList();
      _assetImages = imageAssets..sort();
      _imagesLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {
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
    // Picks an image from user-picked list or bundled assets, decodes it,
    // updates selection, and resets current game with new slices.
    try {
      await _loadAssetImagesList();
      final int userCount = _userImages.length;
      final int assetCount = _assetImages.length;
      final int total = userCount + assetCount;
      if (total == 0) return;
      final pickIdx = rng.nextInt(total);
      if (pickIdx < userCount) {
        final idx = pickIdx;
        final data = _userImages[idx];
        final img = await decodeUiImage(data);
        if (!mounted) return;
        setState(() {
          image = img;
          _selectedId = _userId(idx);
        });
        final sp = await SharedPreferences.getInstance();
        if (idx >= 0 && idx < _userEntries.length) {
          await sp.setString(_kPrefLastImage, _userEntries[idx]);
        } else {
          await sp.setString(_kPrefLastImage, 'B64://${base64Encode(data)}');
        }
        _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
      } else {
        final assetIdx = pickIdx - userCount;
        if (assetIdx >= 0 && assetIdx < assetCount) {
          final pick = _assetImages[assetIdx];
          await _loadAssetImage(pick);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAssetImage(String path, {bool forResume = false}) async {
    // Loads a bundled asset by path and optionally keeps the board if resuming.
    try {
      final data = await rootBundle.load(path);
      final img = await decodeUiImage(data.buffer.asUint8List());
      if (!mounted) return;
      setState(() {
        _selectedId = path;
        image = img;
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
    } catch (_) {}
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
    // Persists a picked image on disk (mobile/desktop) or as base64 (web).
    // Returns a scheme-qualified entry: FILE://path or B64://... for later reload.
    if (kIsWeb) return 'B64://${base64Encode(data)}';
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
    // Splits the full image into (dim*dim - 1) tile images for fast painting.
    // The bottom-right tile remains empty (classic 15-puzzle convention).
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
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    // Opens platform picker, persists the result, updates selection and resets the board.
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
      final img = await decodeUiImage(data);
      if (!mounted) return;
      setState(() {
        image = img;
        _selectedId = _userId(0);
      });
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefLastImage, entry);
      await _saveUserImagesList();
      _clearGameState();
      _reset(shuffle: true);
      _buildSlices();
    } catch (_) {}
  }

  Future<void> deleteFileIfExists(String path) async {
    try {
      final f = io.File(path);
      if (await f.exists()) await f.delete();
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
        title: Text(S.dlgDeleteTitle),
        content: Text(S.dlgDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.dlgNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.dlgYesDelete),
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
        final img = await decodeUiImage(data);
        if (!mounted) return;
        setState(() {
          image = img;
          _selectedId = _userId(0);
        });
        final sp = await SharedPreferences.getInstance();
        if (_userEntries.isNotEmpty) {
          await sp.setString(_kPrefLastImage, _userEntries[0]);
        } else {
          await sp.setString(_kPrefLastImage, 'B64://${base64Encode(data)}');
        }
        _clearGameState();
        _reset(shuffle: true);
        _buildSlices();
      } catch (_) {
        await _loadRandomAssetImage();
      }
    } else {
      await _loadRandomAssetImage();
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
      builder: (c) => HelpBottomSheet(language: _language, strings: S),
    );
  }

  void _reset({bool shuffle = false}) {
    board = PuzzleBoard.solved(dimension);
    if (shuffle) board = board.shuffled(rng);
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
      builder: (c) => SettingsBottomSheet(
        language: _language,
        strings: S,
        darkMode: darkMode,
        showNumbers: _showTileNumbers,
        soundEnabled: _soundEnabled,
        dimension: dimension,
        onThemeChanged: _setDark,
        onNumbersChanged: _setShowNumbers,
        onSoundChanged: _setClickSound,
        onLanguageChanged: _setLanguage,
        onDimensionChanged: _changeDimension,
      ),
    );
  }

  void _onTileTap(int tileArrayIndex) {
    if (board.isSolved) return;
    final moved = board.move(tileArrayIndex);
    if (moved) {
      if (_soundEnabled) {
        SystemSound.play(SystemSoundType.click);
      }
      moves++;
      setState(() {});
      _saveGameState();
      if (board.isSolved) {
        _timer?.cancel();
        _saveRecordIfBetter();
        _saveGameState(solved: true);
        HapticFeedback.mediumImpact();
        setState(() => _showWinOverlay = true);
      }
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    final result =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return _language == AppLanguage.fa ? toFaDigits(result) : result;
  }

  Future<void> _loadFileImage(String filePath, {bool forResume = false}) async {
    await Future<void>.delayed(Duration.zero);
    try {
      final xf = XFile(filePath);
      final data = await xf.readAsBytes();
      final entry = 'FILE://$filePath';
      _addUserEntry(entry, data);
      final img = await decodeUiImage(data);
      if (!mounted) return;
      setState(() {
        image = img;
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
    } catch (_) {
      await _loadRandomAssetImage();
    }
  }

  Future<_SavedGame?> _readSavedGame() async {
    // Reads a previously saved board from SharedPreferences.
    // Tiles are stored as a CSV of current indices, validated before use.
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

  Future<void> _saveGameState({bool? solved}) async {
    // Persists the current board state so the user can resume later.
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

  void _applySavedGame(_SavedGame sg) {
    // Applies a saved permutation/moves/time onto a fresh solved board.
    dimension = sg.dim;
    final newBoard = PuzzleBoard.solved(dimension);
    for (int i = 0; i < newBoard.tiles.length; i++) {
      newBoard.tiles[i].currentIndex = sg.tileCurrents[i];
    }
    board = newBoard;
    moves = sg.moves;
    seconds = sg.seconds;
    _slices = null;
    setState(() {});
    if (image != null) _buildSlices();
  }

  Future<void> _loadSettings() async {
    // Loads theme, language, last image, user images and game snapshot, then
    // either resumes the game (if not solved) or starts a fresh shuffled one.
    final sp = await SharedPreferences.getInstance();
    final savedDark = sp.getBool(_kPrefDark);
    final savedDim = sp.getInt(_kPrefDim);
    final savedImage = sp.getString(_kPrefLastImage);
    final savedThemeIdx = sp.getInt(_kPrefThemeIdx);
    final savedShowNumbers = sp.getBool(_kPrefShowNumbers);
    final savedClickSound = sp.getBool(_kPrefClickSound);
    final savedLang = sp.getString(_kPrefLanguage);
    final savedGame = await _readSavedGame();
    if (savedDark != null) darkMode = savedDark;
    if (savedThemeIdx != null &&
        savedThemeIdx >= 0 &&
        savedThemeIdx < _seedPalette.length) {
      _themeIdx = savedThemeIdx;
    }
    if (savedShowNumbers != null) _showTileNumbers = savedShowNumbers;
    if (savedClickSound != null) {
      _soundEnabled = savedClickSound;
    } else {
      _soundEnabled = true; // default on
    }
    if (savedLang != null) {
      if (savedLang == 'fa') _language = AppLanguage.fa;
      if (savedLang == 'en') _language = AppLanguage.en;
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
          final img = await decodeUiImage(data);
          if (mounted) {
            setState(() {
              image = img;
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
          final img = await decodeUiImage(data);
          if (mounted) {
            setState(() {
              image = img;
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
          body: Stack(
            children: [
              Positioned.fill(
                child: ModernBackground(
                  image: image,
                  dark: darkMode,
                  primary: theme.colorScheme.primary,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;
                  final availableWidth = constraints.maxWidth;
                  final padding = MediaQuery.of(context).padding;
                  final isWide = availableWidth >= 720;
                  final titleBarSpace = padding.top + (isWide ? 58.0 : 50.0);
                  final sliderHeight = (availableHeight * 0.22).clamp(
                    140.0,
                    240.0,
                  );
                  final bottomBarSpace = padding.bottom + 84.0;
                  final remainingHeight =
                      availableHeight - bottomBarSpace - sliderHeight;
                  final maxBoard = min(
                    availableWidth * 0.90,
                    remainingHeight * 0.72,
                  ).clamp(240.0, 720.0);
                  final remainingVerticalSpace = remainingHeight - maxBoard;
                  final verticalSpacing = (remainingVerticalSpace * 0.28).clamp(
                    8.0,
                    56.0,
                  );
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        availableWidth * 0.03,
                        verticalSpacing + titleBarSpace,
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
                                width: double.infinity,
                                child: AssetSlider(
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
                                        final img = await decodeUiImage(data);
                                        if (!mounted) return;
                                        setState(() {
                                          image = img;
                                          _selectedId = id;
                                        });
                                        final sp =
                                            await SharedPreferences.getInstance();
                                        if (idx < _userEntries.length) {
                                          final originalEntry =
                                              _userEntries[idx];
                                          await sp.setString(
                                            _kPrefLastImage,
                                            originalEntry,
                                          );
                                        } else {
                                          await sp.setString(
                                            _kPrefLastImage,
                                            'B64://${base64Encode(data)}',
                                          );
                                        }
                                        _clearGameState();
                                        _reset(shuffle: true);
                                        _buildSlices();
                                      }
                                    } else {
                                      _loadAssetImage(id);
                                    }
                                  },
                                  onDeleteSelected:
                                      _confirmAndDeleteSelectedUserImage,
                                ),
                              ),
                              SizedBox(height: verticalSpacing),
                              Hero(
                                tag: 'board',
                                child: SizedBox(
                                  width: maxBoard,
                                  height: maxBoard,
                                  child: PuzzleView(
                                    board: board,
                                    dimension: dimension,
                                    image: image,
                                    onTileTap: _onTileTap,
                                    slices: _slices,
                                    showNumbers: _showTileNumbers,
                                    language: _language,
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
                top: 0,
                child: TopTitleBar(title: S.appTitle),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ActionBar(
                  strings: S,
                  onPickImage: _pickImage,
                  onShuffleIncorrect: () =>
                      setState(() => board.partialShuffleIncorrect(rng)),
                  onReset: () => _loadRandomAssetImage(),
                  onOpenSettings: _openSettings,
                  onHelp: _showHelp,
                ),
              ),
              if (_showWinOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showWinOverlay = false),
                    child: Center(
                      child: WhiteWinBox(
                        title: S.winTitle,
                        subtitle: S.winSubtitle,
                        movesText: _language == AppLanguage.fa
                            ? toFaDigits(moves)
                            : moves.toString(),
                        timeText: _formatTime(seconds),
                        movesLabel: S.movesLabel,
                        timeLabel: S.timeLabel,
                        accent: theme.colorScheme.primary,
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
