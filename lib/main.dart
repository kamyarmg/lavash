import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

class _MainAppState extends State<MainApp> {
  int dimension = 3;
  late PuzzleBoard board;
  ui.Image? image; // تصویر انتخاب‌شده
  XFile? pickedFile;
  final rng = Random();
  Timer? _timer;
  int seconds = 0;
  int moves = 0;
  bool showNumbers = false;
  bool darkMode = false; // fastMode حذف شد

  // رکوردها
  int? bestMoves;
  int? bestTime; // ثانیه
  // رنگ‌های ثابت (حذف سیستم پالت)
  // گرادیان روشن و درخشان که در هر دو مود زیبا باشد.
  // اگر کاربر مود تیره را بزند، یک لایه تیره شفاف روی آن اعمال می‌کنیم.
  static const Color _accentColor = Color(0xFF00BFA5); // فیروزه‌ای آرام

  // کش برش‌ها
  List<ui.Image?>? _slices; // طول = tiles.length -1
  bool _buildingCache = false;

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);
    _loadRecords();
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
      setState(() {});
      if (board.isSolved) {
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('تبریک!'),
              content: Text(
                'پازل را در ${_toFaDigits(moves)} حرکت و ${_formatTime(seconds)} حل کردید.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _reset(shuffle: true);
                  },
                  child: const Text('دوباره'),
                ),
              ],
            ),
          );
        });
        _saveRecordIfBetter();
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
        seedColor: _accentColor,
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
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(
              'پازل اسلایدی',
              style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                tooltip: darkMode ? 'حالت روشن' : 'حالت تیره',
                onPressed: _toggleDark,
                icon: Icon(darkMode ? Icons.light_mode : Icons.dark_mode),
              ),
              IconButton(
                tooltip: 'انتخاب تصویر',
                icon: const Icon(Icons.image_outlined),
                onPressed: _pickImage,
              ),
              IconButton(
                tooltip: 'شافل نامرتب‌ها',
                icon: const Icon(Icons.auto_fix_high),
                onPressed: () =>
                    setState(() => board.partialShuffleIncorrect(rng)),
              ),
              PopupMenuButton<int>(
                tooltip: 'ابعاد',
                onSelected: _changeDimension,
                itemBuilder: (_) => [3, 4, 5]
                    .map(
                      (e) => PopupMenuItem(
                        value: e,
                        child: Text(_toFaDigits('${e}×$e')),
                      ),
                    )
                    .toList(),
                icon: const Icon(Icons.grid_on),
              ),
              IconButton(
                tooltip: showNumbers ? 'مخفی کردن شماره' : 'نمایش شماره',
                onPressed: () => setState(() => showNumbers = !showNumbers),
                icon: Icon(showNumbers ? Icons.filter_9_plus : Icons.numbers),
              ),
              IconButton(
                tooltip: 'شروع دوباره',
                icon: const Icon(Icons.refresh),
                onPressed: () => _reset(shuffle: true),
              ),
            ],
          ),
          body: Container(
            color: darkMode ? const Color(0xFF121212) : Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxBoard = min(
                  constraints.maxWidth,
                  constraints.maxHeight - 220,
                ).clamp(240.0, 640.0);
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 110, 20, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
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
                          const SizedBox(height: 12),
                          _BoardFrame(
                            dark: darkMode,
                            child: SizedBox(
                              width: maxBoard,
                              height: maxBoard,
                              child: _PuzzleView(
                                board: board,
                                dimension: dimension,
                                image: image,
                                showNumbers: showNumbers,
                                onTileTap: _onTileTap,
                                slices: _slices,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (image == null)
                            Text(
                              'برای شروع یک تصویر انتخاب کنید.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: darkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                              textAlign: TextAlign.center,
                            ),
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
      spacing: 14,
      runSpacing: 10,
      children: [
        _chip(context, Icons.timer_outlined, time, 'زمان'),
        _chip(context, Icons.swipe, _toFaDigits(moves), 'حرکت'),
        _chip(context, Icons.grid_4x4, _toFaDigits('${dim}×$dim'), 'ابعاد'),
        _chip(context, Icons.emoji_events_outlined, _recordText(), 'رکورد'),
      ],
    );
  }

  String _recordText() {
    if (bestMoves == null && bestTime == null) return '—';
    final bm = bestMoves != null ? _toFaDigits(bestMoves!) : '—';
    final bt = bestTime != null ? _toFaDigits('${bestTime!}ث') : '—';
    return '$bm / $bt';
  }

  Widget _chip(BuildContext ctx, IconData icon, String value, String label) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardFrame extends StatelessWidget {
  final Widget child;
  final bool dark;
  const _BoardFrame({required this.child, required this.dark});
  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withOpacity(dark ? 0.06 : 0.10);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: color,
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: child,
    );
  }
}

class _PuzzleView extends StatelessWidget {
  final PuzzleBoard board;
  final int dimension;
  final ui.Image? image;
  final bool showNumbers;
  final void Function(int tileArrayIndex) onTileTap;
  final List<ui.Image?>? slices;
  // fastMode حذف شد
  const _PuzzleView({
    required this.board,
    required this.dimension,
    required this.image,
    required this.showNumbers,
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
          return Stack(
            children: [
              // زمینه
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.05),
                    ],
                  ),
                ),
              ),
              for (int i = 0; i < board.tiles.length - 1; i++)
                _buildTile(context, board.tiles[i], tileSize),
              if (board.isSolved && image != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.15,
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
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeInOut,
      left: col * tileSize,
      top: row * tileSize,
      width: tileSize,
      height: tileSize,
      child: GestureDetector(
        onTap: () => onTileTap(board.tiles.indexOf(tile)),
        child: _TileContent(
          image: image,
          dimension: dimension,
          correctRow: correctRow,
          correctCol: correctCol,
          showNumber: showNumbers,
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
    // رنگ پاستیلی شبه تصادفی بر اساس اندیس
    Color pastel(int i, bool correct) {
      final hue = (i * 53) % 360; // پخش یکنواخت
      final hsl = HSLColor.fromAHSL(
        1,
        hue.toDouble(),
        0.55,
        correct ? 0.70 : 0.78,
      );
      return hsl.toColor();
    }

    final baseColor = pastel(index, isCorrect);
    final child = Container(
      decoration: BoxDecoration(
        gradient: image == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  baseColor.withOpacity(0.95),
                  baseColor.withOpacity(0.7),
                ],
              )
            : null,
        color: image == null ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: slice != null
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: RawImage(
                        image: slice,
                        filterQuality: FilterQuality.medium,
                      ),
                    )
                  : CustomPaint(
                      painter: _ImagePainter(
                        image!,
                        dimension: dimension,
                        clipRow: correctRow,
                        clipCol: correctCol,
                      ),
                    ),
            ),
          if (showNumber)
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _toFaDigits(index + 1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return child;
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

void main() {
  runApp(const MainApp());
}
