import 'dart:async';
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
        // پیدا کردن tile ای که currentIndex == linear
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
    // الگوریتم: تولید یک پرموتیشن تصادفی قابل حل.
    // رویکرد ساده: شافل تصادفی تا زمانی که قابل حل شود (برای dim کوچک اوکی است)
    final maxAttempts = 5000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final perm = List<int>.generate(tiles.length, (i) => i);
      perm.shuffle(rng);
      // اطمینان: خانه خالی باید آخرین آیتم آرایه perm نباشد؟ در حالت solved آخرین است.
      // ما می‌خواهیم empty همان correctIndex آخر باشد، پس آن را تضمین می‌کنیم.
      // اگر نبود، جای آن را با آخرین مقدار عوض می‌کنیم.
      final emptyIdxInPerm = perm.indexOf(emptyTileIndex);
      if (emptyIdxInPerm != perm.length - 1) {
        perm[emptyIdxInPerm] = perm.last;
        perm[perm.length - 1] = emptyTileIndex;
      }
      if (_isSolvable(perm, dimension)) {
        final newTiles = List<Tile>.generate(tiles.length, (i) {
          final correct = i;
          final current = perm.indexOf(i); // موقعیت فعلی در پرموتیشن
          return Tile(correctIndex: correct, currentIndex: current);
        });
        return PuzzleBoard._(dimension, newTiles);
      }
    }
    // اگر نشد برمی‌گردیم خودش را
    return this;
  }

  static bool _isSolvable(List<int> perm, int dim) {
    // حذف empty (آخرین)
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
      // برای بورد زوج، باید ردیف از پایین (1-based) که تایلی خالی در آن قرار دارد ملاک باشد
      final emptyLinear = perm.indexOf(perm.length - 1); // باید آخر باشد
      final emptyRowFromTop = emptyLinear ~/ dim; // 0-based
      final emptyRowFromBottom = dim - emptyRowFromTop; // 1-based
      if (emptyRowFromBottom.isOdd) {
        return inversions.isEven;
      } else {
        return inversions.isOdd;
      }
    }
  }

  /// شافل فقط تایل‌هایی که در جای صحیح نیستند (به جز خانه خالی)
  /// تلاش می‌کند حالت تولید شده solvable بماند. روش: جای صحیح‌ها ثابت می‌ماند
  /// لیست ایندکس‌های غلط (به جز empty) را گرفته و پرموتیشن جدید روی همان‌ها اعمال می‌کنیم
  /// سپس اگر وضعیت کلی حل‌پذیر نبود دوباره تلاش می‌کنیم (حداکثر n تلاش)
  PuzzleBoard partialShuffleIncorrect(Random rng) {
    final incorrectTiles = tiles
        .where(
          (t) =>
              t.correctIndex != t.currentIndex &&
              t.correctIndex != emptyTileIndex,
        )
        .toList();
    if (incorrectTiles.length < 2) return this; // چیزی برای جابجایی نیست

    final attempts = min(incorrectTiles.length * 10, 200);
    for (int attempt = 0; attempt < attempts; attempt++) {
      // استخراج currentIndex های این گروه
      final positions = incorrectTiles.map((t) => t.currentIndex).toList();
      positions.shuffle(rng);
      // اعمال موقتی
      for (int i = 0; i < incorrectTiles.length; i++) {
        incorrectTiles[i].currentIndex = positions[i];
      }
      // تولید پرموتیشن فعلی جهت تست solvable
      final perm = List<int>.filled(tiles.length, -1);
      for (final t in tiles) {
        perm[t.currentIndex] = t.correctIndex;
      }
      if (_isSolvable(perm, dimension)) {
        return this;
      }
      // اگر نشد ادامه (چون inplace تغییر دادیم، دور بعد دوباره تغییر می‌دهد)
    }
    return this; // در بدترین حالت بدون تضمین تغییر خاص
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
  Timer? _timer;
  int seconds = 0;
  int moves = 0;
  // نمایش شماره تایل‌ها همیشه فعال است (showNumbers حذف شد)
  bool darkMode = false; // fastMode حذف شد
  // حالت کوررنگی حذف شد
  bool _justSolved = false;
  late AnimationController _bgAnim;
  late AnimationController _solveParticles;
  late AnimationController _cartoon;
  final ValueNotifier<int> _pulseNotifier = ValueNotifier(0);

  // رکوردها
  int? bestMoves;
  int? bestTime; // ثانیه
  // رنگ‌های ثابت (حذف سیستم پالت)
  // گرادیان روشن و درخشان که در هر دو مود زیبا باشد.
  // اگر کاربر مود تیره را بزند، یک لایه تیره شفاف روی آن اعمال می‌کنیم.
  // static const Color _accentColor = Color(0xFF00BFA5); // حذف: دیگر استفاده نمی‌شود

  // کش برش‌ها
  List<ui.Image?>? _slices; // طول = tiles.length -1
  bool _buildingCache = false;

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);
    _loadRecords();
    _bgAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _solveParticles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _cartoon = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    // بارگذاری تصادفی یک تصویر از assets هنگام اولین اجرا
    _loadRandomAssetImage();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bgAnim.dispose();
    _solveParticles.dispose();
    _cartoon.dispose();
    _pulseNotifier.dispose();
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
    bestMoves = sp.getInt('best_moves_${dimension}');
    bestTime = sp.getInt('best_time_${dimension}');
    if (mounted) setState(() {});
  }

  Future<void> _saveRecordIfBetter() async {
    final sp = await SharedPreferences.getInstance();
    bool changed = false;
    if (bestMoves == null || moves < bestMoves!) {
      bestMoves = moves;
      await sp.setInt('best_moves_${dimension}', moves);
      changed = true;
    }
    if (bestTime == null || seconds < bestTime!) {
      bestTime = seconds;
      await sp.setInt('best_time_${dimension}', seconds);
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
      final data = await rootBundle.load(pick);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => image = frame.image);
      _reset(shuffle: true);
      _buildSlices();
    } catch (e) {
      // ignore: avoid_print
      print('Random asset image load failed: $e');
    }
  }
  // حالت سریع حذف شد

  Future<void> _buildSlices() async {
    if (image == null) {
      _slices = null;
      if (mounted) setState(() {});
      return;
    }
    _buildingCache = true;
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
    _buildingCache = false;
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
      setState(() => image = frame.image);
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
    _buildingCache = false;
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
      _pulseNotifier.value++;
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
      scaffoldBackgroundColor: Colors.transparent,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 6,
                ),
                child: Center(
                  child: _GradientTitle(text: 'پازل کشویی لواش 🧩'),
                ),
              ),
            ),
          ),
          body: Stack(
            children: [
              AnimatedBackground(controller: _bgAnim, dark: darkMode),
              if (darkMode) Container(color: Colors.black.withOpacity(0.25)),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxBoard = min(
                    constraints.maxWidth,
                    constraints.maxHeight - 260,
                  ).clamp(240.0, 560.0);
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 110, 20, 120),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TopStats(
                              moves: moves,
                              time: _formatTime(seconds),
                              dim: dimension,
                              bestMoves: bestMoves,
                              bestTime: bestTime,
                            ),
                            const SizedBox(height: 16),
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
                                    cartoon: _cartoon,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                            // پیام قبلی و حالت بازی بدون تصویر حذف شد
                            if (_buildingCache)
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'در حال آماده‌سازی تصویر...',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // دکمه‌های کنترل پایین
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
              // افکت حل شدن
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

class _TopStats extends StatelessWidget {
  final int moves;
  final String time;
  final int dim;
  final int? bestMoves;
  final int? bestTime;
  const _TopStats({
    required this.moves,
    required this.time,
    required this.dim,
    required this.bestMoves,
    required this.bestTime,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        _chip(context, '⏱️', time, 'زمان'),
        _chip(context, '🎯', _toFaDigits(moves), 'حرکت'),
        _chip(context, '🧩', _toFaDigits('${dim}×$dim'), 'ابعاد'),
        _chip(context, '🏆', _recordText(), 'رکورد'),
      ],
    );
  }

  String _recordText() {
    if (bestMoves == null && bestTime == null) return '—';
    final bm = bestMoves != null ? _toFaDigits(bestMoves!) : '—';
    final bt = bestTime != null ? _toFaDigits('${bestTime!}ث') : '—';
    return '$bm / $bt';
  }

  Widget _chip(BuildContext ctx, String emoji, String value, String label) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF176), Color(0xFFFFC038), Color(0xFFFF914D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC038).withOpacity(0.55),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.black87,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsets.all(20),
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
            color: Colors.black.withOpacity(0.4),
            blurRadius: 25,
            offset: const Offset(0, 12),
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
  final AnimationController cartoon;
  // fastMode حذف شد
  const _PuzzleView({
    required this.board,
    required this.dimension,
    required this.image,
    required this.onTileTap,
    required this.slices,
    required this.cartoon,
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
          showNumber: true,
          index: tile.correctIndex,
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
  final bool showNumber;
  final int index;
  final bool isCorrect;
  final ui.Image? slice;
  // fastMode حذف شد
  const _TileContent({
    required this.image,
    required this.dimension,
    required this.correctRow,
    required this.correctCol,
    required this.showNumber,
    required this.index,
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
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutQuad,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCorrect
              ? const Color(0xFFFF6EC7).withOpacity(0.9)
              : Colors.white.withOpacity(0.45),
          width: isCorrect ? 2.2 : 1.2,
        ),
        boxShadow: correctGlow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
            if (showNumber)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _toFaDigits(index + 1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
// Animated Gradient Background + Blobs
// ------------------------------------------------------------
class AnimatedBackground extends StatelessWidget {
  final AnimationController controller;
  final bool dark;
  const AnimatedBackground({
    super.key,
    required this.controller,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        // چند رنگ که در طول زمان چرخش هیو داشته باشند
        Color shift(Color c, double v) {
          final hsl = HSLColor.fromColor(c);
          return hsl.withHue((hsl.hue + v) % 360).toColor();
        }

        final base1 = shift(const Color(0xFF201F5E), t * 40);
        final base2 = shift(const Color(0xFF3C1E6E), t * 80);
        final base3 = shift(const Color(0xFFFF6EC7), t * 120);
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                -0.3 + 0.6 * sin(t * pi * 2),
                -0.2 + 0.4 * cos(t * pi * 2),
              ),
              radius: 1.2,
              colors: [base1, base2, base3.withOpacity(0.9)],
            ),
          ),
          child: CustomPaint(painter: _BlobPainter(t: t)),
        );
      },
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  _BlobPainter({required this.t});
  final List<Color> colors = const [
    Color(0x33FFFFFF),
    Color(0x22FFB6F2),
    Color(0x3357FFF5),
    Color(0x22FFC778),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 18; i++) {
      final p = Offset(
        (sin(t * 2 * pi + i) * 0.4 + 0.5) * size.width + sin(i * 11) * 8,
        (cos(t * 2 * pi + i * 0.7) * 0.4 + 0.5) * size.height + cos(i * 7) * 8,
      );
      final r = 60 + (sin(t * 6 + i) + 1) * 50;
      final paint = Paint()
        ..color = colors[i % colors.length].withOpacity(
          0.4 + 0.3 * sin(t * 4 + i),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.t != t;
}

// ------------------------------------------------------------
// Gradient Title
// ------------------------------------------------------------
class _GradientTitle extends StatelessWidget {
  final String text;
  const _GradientTitle({required this.text});
  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.vazirmatn(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFFFFB6F2), Color(0xFF72F1B8), Color(0xFF00E5FF)],
      ).createShader(rect),
      child: Text(text, style: style.copyWith(color: Colors.white)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
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
            spacing: 12,
            runSpacing: 10,
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
