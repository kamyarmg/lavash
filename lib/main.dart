import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  ui.Image? image; // تصویر برش داده می‌شود
  XFile? pickedFile; // از XFile برای پشتیبانی وب/دسکتاپ بهتر
  final rng = Random();
  Timer? timer;
  int seconds = 0;
  int moves = 0;
  bool showNumbers = false;

  @override
  void initState() {
    super.initState();
    board = PuzzleBoard.solved(dimension).shuffled(rng);
  }

  void _startTimer() {
    timer?.cancel();
    seconds = 0;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (board.isSolved) return; // توقف زمان بعد از حل
      setState(() => seconds++);
    });
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
    setState(() {});
  }

  void _changeDimension(int d) {
    dimension = d;
    _reset(shuffle: true);
  }

  void _onTileTap(int tileArrayIndex) {
    if (board.isSolved) return;
    final moved = board.move(tileArrayIndex);
    if (moved) {
      moves++;
      setState(() {});
      if (board.isSolved) {
        timer?.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('تبریک!'),
              content: Text(
                'پازل را در $moves حرکت و ${_formatTime(seconds)} حل کردید.',
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
      }
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('پازل اسلایدی'),
          actions: [
            IconButton(
              tooltip: 'انتخاب تصویر',
              icon: const Icon(Icons.image_outlined),
              onPressed: _pickImage,
            ),
            IconButton(
              tooltip: 'شافل تایل‌های نامرتب',
              icon: const Icon(Icons.shuffle),
              onPressed: () {
                setState(() {
                  board.partialShuffleIncorrect(rng);
                });
              },
            ),
            PopupMenuButton<int>(
              tooltip: 'ابعاد',
              onSelected: _changeDimension,
              itemBuilder: (_) => [3, 4, 5]
                  .map((e) => PopupMenuItem(value: e, child: Text('${e}x$e')))
                  .toList(),
              icon: const Icon(Icons.grid_on),
            ),
            IconButton(
              tooltip: 'نمایش/مخفی شماره‌ها',
              onPressed: () => setState(() => showNumbers = !showNumbers),
              icon: Icon(showNumbers ? Icons.numbers : Icons.tag),
            ),
            IconButton(
              tooltip: 'تازه سازی',
              icon: const Icon(Icons.refresh),
              onPressed: () => _reset(shuffle: true),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = min(constraints.maxWidth, constraints.maxHeight - 140);
            return Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoBar(
                      moves: moves,
                      time: _formatTime(seconds),
                      dim: dimension,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: size,
                      height: size,
                      child: _PuzzleView(
                        board: board,
                        dimension: dimension,
                        image: image,
                        showNumbers: showNumbers,
                        onTileTap: _onTileTap,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (image == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          'برای شروع می‌توانید دکمه تصویر را بزنید یا همین حالا با زمینه رنگی بازی کنید.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  final int moves;
  final String time;
  final int dim;
  const _InfoBar({required this.moves, required this.time, required this.dim});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 8,
      children: [
        _chip(Icons.timer, time, 'زمان'),
        _chip(Icons.swipe, '$moves', 'حرکت'),
        _chip(Icons.grid_4x4, '${dim}x$dim', 'ابعاد'),
      ],
    );
  }

  Widget _chip(IconData icon, String value, String label) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _PuzzleView extends StatelessWidget {
  final PuzzleBoard board;
  final int dimension;
  final ui.Image? image;
  final bool showNumbers;
  final void Function(int tileArrayIndex) onTileTap;
  const _PuzzleView({
    required this.board,
    required this.dimension,
    required this.image,
    required this.showNumbers,
    required this.onTileTap,
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
              Container(color: Colors.grey.shade300),
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
      duration: const Duration(milliseconds: 180),
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
  const _TileContent({
    required this.image,
    required this.dimension,
    required this.correctRow,
    required this.correctCol,
    required this.showNumber,
    required this.index,
    required this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: image == null
            ? (isCorrect ? Colors.teal : Colors.teal.shade300)
            : Colors.white,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            CustomPaint(
              painter: _ImagePainter(
                image!,
                dimension: dimension,
                clipRow: correctRow,
                clipCol: correctCol,
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
                  '${index + 1}',
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
