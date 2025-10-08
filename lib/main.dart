import 'dart:async';
import 'dart:io' show File; // برای نمایش تصویر انتخابی کاربر در اسلایدر
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with TickerProviderStateMixin {
  int dimension = 3;
  late PuzzleBoard board;
  ui.Image? image; // تصویر انتخاب‌شده
  XFile? pickedFile;
  final rng = Random();
  String? _selectedAssetPath; // مسیر انتخاب شده از اسلایدر
  Timer? _timer;
  int seconds = 0;
  int moves = 0;
  // نمایش شماره تایل‌ها همیشه فعال است (showNumbers حذف شد)
  bool darkMode = false; // fastMode حذف شد
  // حالت کوررنگی حذف شد
  bool _justSolved = false;
  late AnimationController _solveParticles;

  // رکوردها
  int? bestMoves;
  int? bestTime; // ثانیه
  // رنگ‌های ثابت (حذف سیستم پالت)
  // گرادیان روشن و درخشان که در هر دو مود زیبا باشد.
  // اگر کاربر مود تیره را بزند، یک لایه تیره شفاف روی آن اعمال می‌کنیم.
  // static const Color _accentColor = Color(0xFF00BFA5); // حذف: دیگر استفاده نمی‌شود

  // کش برش‌ها
  List<ui.Image?>? _slices; // طول = tiles.length -1

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);
    _loadRecords();
    _solveParticles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // بارگذاری تصادفی یک تصویر از assets هنگام اولین اجرا
    _loadRandomAssetImage();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _solveParticles.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (board.isSolved) return;
      setState(() => seconds++);
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

  void _toggleDark() => setState(() => darkMode = !darkMode);
  // حالت کوررنگی حذف شد

  // لیست نام فایل‌های موجود در assets/images (در صورت افزودن تصویر جدید این آرایه را به‌روزرسانی کنید)
  static const List<String> _assetImages = [
    'assets/images/1.jpg',
    'assets/images/2.jpg',
    'assets/images/3.jpg',
    'assets/images/4.jpg',
    'assets/images/5.jpg',
    'assets/images/6.jpg',
    'assets/images/7.jpg',
    'assets/images/8.jpg',
    'assets/images/9.jpg',
    'assets/images/10.jpg',
    'assets/images/11.jpg',
    'assets/images/12.jpg',
    'assets/images/13.jpg',
    'assets/images/14.jpg',
  ];

  Future<void> _loadRandomAssetImage() async {
    try {
      final pick = _assetImages[rng.nextInt(_assetImages.length)];
      await _loadAssetImage(pick);
    } catch (e) {
      // ignore: avoid_print
      print('Random asset image load failed: $e');
    }
  }

  Future<void> _loadAssetImage(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _selectedAssetPath = path;
        image = frame.image;
      });
      _reset(shuffle: true);
      _buildSlices();
    } catch (e) {
      // ignore: avoid_print
      print('Asset image load failed: $e');
    }
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
      pickedFile = result;
      final data = await result.readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      // ابتدا تصویر ست می‌شود
      setState(() {
        image = frame.image;
        // مسیر انتخاب شده را به عنوان selected نگه می‌داریم تا در اسلایدر سنتر شود
        _selectedAssetPath = pickedFile!.path;
      });
      // سپس بورد ریست می‌شود (خارج از همان setState برای جلوگیری از مشکلات رندر)
      _reset(shuffle: true);
      _buildSlices();
      // لاگ ساده برای اطمینان
      // (می‌توانید بعداً حذف کنید)
      // ignore: avoid_print
      print('Image loaded: ${image!.width}x${image!.height}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در بارگذاری تصویر: $e')));
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
  }

  void _changeDimension(int d) {
    dimension = d;
    _reset(shuffle: true);
    _loadRecords();
  }

  void _onTileTap(int tileArrayIndex) {
    if (board.isSolved) return;
    final moved = board.move(tileArrayIndex);
    if (moved) {
      moves++;
      setState(() {});
      if (board.isSolved) {
        _timer?.cancel();
        _saveRecordIfBetter();
        _justSolved = true;
        _solveParticles.forward(from: 0);
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          showDialog(
            barrierDismissible: false,
            context: context,
            builder: (_) => _WinDialog(
              moves: moves,
              time: _formatTime(seconds),
              onReplay: () {
                Navigator.pop(context);
                _loadRandomAssetImage();
              },
            ),
          );
        });
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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: darkMode ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF6EC7),
        brightness: darkMode ? Brightness.dark : Brightness.light,
      ),
      textTheme: GoogleFonts.vazirmatnTextTheme(
        darkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      scaffoldBackgroundColor: Colors.white,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              // پس زمینه گرادیان حذف شد؛ پس زمینه سفید ساده
              Container(color: Colors.white),
              // پسزمینه: تصویر انتخابشده پازل به صورت خیلی ترنسپرنت و شفاف
              if (image != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.15, // خیلی ترنسپرنت
                      child: CustomPaint(painter: _CoverImagePainter(image!)),
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  // فضای رزرو شده برای اسلایدر و نوار پایینی کمتر شد تا برد بزرگ‌تر شود
                  final maxBoard = min(
                    constraints.maxWidth,
                    constraints.maxHeight - 200,
                  ).clamp(240.0, 720.0);
                  return Center(
                    child: SingleChildScrollView(
                      // حاشیه‌های عمودی و افقی کمتر شد
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // باکس های بالایی (زمان، حرکت، رکورد..) بنا به درخواست حذف شدند
                              // اسلایدر با همان عرض برد (فقط تصاویر assets فعلی)
                              SizedBox(
                                width: maxBoard,
                                child: _AssetSlider(
                                  assets: _assetImages,
                                  userPath: pickedFile?.path,
                                  selected: _selectedAssetPath,
                                  onSelect: (p) => _loadAssetImage(p),
                                ),
                              ),
                              const SizedBox(height: 10),
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
                              const SizedBox(height: 30),
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
  final String? userPath; // مسیر تصویر انتخابی کاربر (File path)
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AssetSlider({
    required this.assets,
    required this.selected,
    required this.onSelect,
    this.userPath,
  });
  @override
  State<_AssetSlider> createState() => _AssetSliderState();
}

class _AssetSliderState extends State<_AssetSlider> {
  final _controller = ScrollController();
  static const _thumbWidth = 96.0;
  static const _thumbMarginH = 6.0; // دو طرف هر آیتم

  List<String> get _allItems {
    // اگر کاربر تصویری انتخاب کرده، آن را به عنوان اولین آیتم موقت قرار می‌دهیم
    if (widget.userPath != null) {
      return ['FILE://${widget.userPath}'] + widget.assets;
    }
    return widget.assets;
  }

  @override
  void didUpdateWidget(covariant _AssetSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.userPath != widget.userPath) {
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
    final selPath = widget.selected;
    if (selPath == null) return;

    // Resolve index considering file prefix
    int index = items.indexWhere((p) {
      if (p.startsWith('FILE://')) {
        final real = p.substring(7);
        return real == selPath;
      }
      return p == selPath;
    });
    if (index < 0) return;

    // محاسبه عرض موثر هر آیتم (عرض + حاشیه‌های افقی دو طرف)
    final perItem = _thumbWidth + (_thumbMarginH * 2);
    final viewport = _controller.position.viewportDimension;
    final targetCenterOffset = index * perItem + perItem / 2 - viewport / 2;
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
      height: 90,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final rawPath = items[i];
          final isFile = rawPath.startsWith('FILE://');
          final displayPath = isFile ? rawPath.substring(7) : rawPath;
          final isSel = displayPath == widget.selected;
          return _SliderThumb(
            index: i,
            path: displayPath,
            selected: isSel,
            onTap: () => widget.onSelect(displayPath),
            accent: theme.colorScheme.primary,
            isFile: isFile,
          );
        },
      ),
    );
  }
}

class _SliderThumb extends StatefulWidget {
  final int index;
  final String path;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final bool isFile; // آیا تصویر فایل کاربر است
  const _SliderThumb({
    required this.index,
    required this.path,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.isFile = false,
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
    final scale = sel ? 1.0 + 0.06 * (1 - _hover) : 0.90 + 0.07 * _hover;
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
              Colors.white.withOpacity(0.28),
              Colors.white.withOpacity(0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return Container(
      width: 90,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: MouseRegion(
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  if (sel)
                    BoxShadow(
                      color: const Color(0xFFFF6EC7).withOpacity(0.55),
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
                          widget.isFile
                              ? Image.file(File(widget.path), fit: BoxFit.cover)
                              : Image.asset(widget.path, fit: BoxFit.cover),
                          // Subtle parallax / shine overlay
                          AnimatedBuilder(
                            animation: _shine,
                            builder: (_, __) {
                              final t = _shine.value;
                              return IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-1 + 2 * t, -1),
                                      end: Alignment(1 + 2 * t, 1),
                                      colors: [
                                        Colors.white.withOpacity(0.0),
                                        Colors.white.withOpacity(
                                          sel ? 0.18 : 0.07,
                                        ),
                                        Colors.white.withOpacity(0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Dark overlay when not selected
                          if (!sel)
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.25),
                                    Colors.black.withOpacity(0.45),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          // Selection bottom glow & icon
                          if (sel)
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
                                      const Color(0xFF141414).withOpacity(0.65),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (sel)
                            const Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          // شماره اسلاید حذف شد
                        ],
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
  }
}

class _FancyFrame extends StatelessWidget {
  final Widget child;
  const _FancyFrame({required this.child});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      // پدینگ قاب کمتر شد
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.22),
            Colors.white.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        backgroundBlendMode: BlendMode.overlay,
      ),
      child: child,
    );
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
              if (board.isSolved)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.12,
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
              color: Colors.white.withOpacity(0.9),
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
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutQuad,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCorrect
              ? const Color(0xFFFF6EC7).withOpacity(0.9)
              : Colors.white.withOpacity(0.45),
          width: isCorrect ? 2.2 : 1.2,
        ),
        boxShadow: correctGlow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            (slice != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: RawImage(
                      image: slice,
                      filterQuality: FilterQuality.medium,
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
    final paint = Paint();
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
// Animated Gradient Background + Blobs
// ------------------------------------------------------------
// AnimatedBackground & _BlobPainter حذف شدند تا پس زمینه کاملا سفید باشد

// عنوان گرادیانی حذف شد زیرا هدری در بالا نداریم

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
    final bright = c.withOpacity(0.95);
    final soft = c.withOpacity(0.55);
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
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: c.withOpacity(0.55),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.65),
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
  const _ActionBar({
    required this.onPickImage,
    required this.onShuffleIncorrect,
    required this.onReset,
    required this.onChangeDim,
    required this.dimension,
    required this.darkMode,
    required this.onToggleDark,
  });
  @override
  Widget build(BuildContext context) {
    // برای چسبیدن کامل به پایین، padding پایینی قبلی حذف شد.
    // اگر بخواهید فضای امن (SafeArea) موبایل‌های ناچ‌دار حفظ شود، می‌توانید SafeArea را فعال کنید.
    // در حال حاضر عمداً از SafeArea صرفنظر شده تا کاملاً به لبه بچسبد. در صورت نیاز:
    // return SafeArea(top: false, child: ...)
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.45),
                Colors.white.withOpacity(0.18),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
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
                tooltip: 'شافل نامرتب‌ها',
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
                child: _CircularGlassButton(
                  icon: const Icon(Icons.grid_on),
                  onTap: () {},
                  tooltip: 'ابعاد',
                  baseColor: const Color(0xFF58D66D),
                ),
              ),
              _CircularGlassButton(
                icon: Icon(darkMode ? Icons.light_mode : Icons.dark_mode),
                onTap: onToggleDark,
                tooltip: darkMode ? 'حالت روشن' : 'حالت تیره',
                baseColor: const Color(0xFFFF78D5),
              ),
              // دکمه حالت کوررنگی حذف شد
            ],
          ),
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
class _WinDialog extends StatelessWidget {
  final int moves;
  final String time;
  final VoidCallback onReplay;
  const _WinDialog({
    required this.moves,
    required this.time,
    required this.onReplay,
  });
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white.withOpacity(0.10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.40),
              Colors.white.withOpacity(0.16),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.65), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              '🥳 تبریک!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'پازل را در ${_toFaDigits(moves)} حرکت و زمان $time حل کردی!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: onReplay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6EC7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'دوباره',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
        )!.withOpacity(1 - progress);
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
