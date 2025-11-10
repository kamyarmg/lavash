import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/strings.dart';
import '../core/utils.dart';
import '../models/puzzle.dart';

// Background
class ModernBackground extends StatelessWidget {
  final ui.Image? image;
  final bool dark;
  final Color primary;
  const ModernBackground({
    super.key,
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
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(covariant _CoverImagePainter oldDelegate) =>
      oldDelegate.image != image;
}

// Slider widgets
class AssetSlider extends StatefulWidget {
  final List<String> assets;
  final List<Uint8List> userImages;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final Future<void> Function()? onDeleteSelected;
  const AssetSlider({
    super.key,
    required this.assets,
    required this.selectedId,
    required this.onSelect,
    this.userImages = const [],
    this.onDeleteSelected,
  });
  @override
  State<AssetSlider> createState() => _AssetSliderState();
}

class _AssetSliderState extends State<AssetSlider> {
  final _controller = ScrollController();
  static const _thumbWidth = 96.0;
  static const _thumbSelectedWidth = 176.0;
  static const _thumbMarginH = 6.0;
  static const _edgePadding = 20.0;
  List<String> get _allItems {
    final userIds = List<String>.generate(
      widget.userImages.length,
      (i) => 'USER:$i',
    );
    return [...userIds, ...widget.assets];
  }

  @override
  void didUpdateWidget(covariant AssetSlider old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId ||
        old.userImages.length != widget.userImages.length) {
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
    final index = items.indexOf(selId);
    if (index < 0) return;
    double offsetBefore = 0;
    for (int i = 0; i < index; i++) {
      offsetBefore += _thumbWidth + (_thumbMarginH * 2);
    }
    final selCenter = _edgePadding + offsetBefore + _thumbSelectedWidth / 2;
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
        padding: const EdgeInsets.only(
          left: _edgePadding,
          right: _edgePadding,
          top: 3,
          bottom: 3,
        ),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final id = items[i];
          final isUser = id.startsWith('USER:');
          final isSel = id == widget.selectedId;
          final baseWidth = isSel ? _thumbSelectedWidth : _thumbWidth;
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
            onDeleteTap: (isSel && isUser) ? widget.onDeleteSelected : null,
            width: baseWidth,
            margin: EdgeInsets.symmetric(
              horizontal: _thumbMarginH,
              vertical: 10,
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
  final Future<void> Function()? onDeleteTap;
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
    this.onDeleteTap,
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

  void _setHover(bool v) => setState(() => _hover = v ? 1 : 0);
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
              onDeleteTap: widget.onDeleteTap,
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
  final Future<void> Function()? onDeleteTap;
  const _SquareAwareThumb({
    required this.square,
    required this.borderGrad,
    required this.shineAnim,
    required this.isSelected,
    required this.isUser,
    this.bytes,
    this.assetPath,
    this.onDeleteTap,
  });
  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
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
                  if (isSelected && isUser && onDeleteTap != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _ThumbDeleteButton(onTap: onDeleteTap!),
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

class _ThumbDeleteButton extends StatelessWidget {
  final Future<void> Function() onTap;
  const _ThumbDeleteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.red.withValues(alpha: 0.14),
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.red.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: Colors.red.withValues(alpha: 0.25),
            highlightColor: Colors.red.withValues(alpha: 0.18),
            onTap: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                await onTap();
              } catch (e) {
                messenger?.showSnackBar(
                  SnackBar(content: Text('خطا در حذف عکس: $e')),
                );
              }
            },
            child: const SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFEF5350),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Puzzle view
class PuzzleView extends StatelessWidget {
  final PuzzleBoard board;
  final int dimension;
  final ui.Image? image;
  final void Function(int tileArrayIndex) onTileTap;
  final List<ui.Image?>? slices;
  final bool showNumbers;
  final AppLanguage language;
  const PuzzleView({
    super.key,
    required this.board,
    required this.dimension,
    required this.image,
    required this.onTileTap,
    required this.slices,
    required this.showNumbers,
    required this.language,
  });
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileSize = constraints.maxWidth / dimension;
          if (image == null)
            return const Center(child: CircularProgressIndicator());
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
    final numberText = showNumbers
        ? (language == AppLanguage.fa
              ? toFaDigits(tile.correctIndex + 1)
              : (tile.correctIndex + 1).toString())
        : null;
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
          numberText: numberText,
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
  bool shouldRepaint(covariant _ImagePainter old) =>
      old.image != image ||
      old.dimension != dimension ||
      old.clipRow != clipRow ||
      old.clipCol != clipCol;
}

// Tile content
class _TileContent extends StatelessWidget {
  final ui.Image? image;
  final int dimension;
  final int correctRow;
  final int correctCol;
  final bool isCorrect;
  final ui.Image? slice;
  final String? numberText;

  const _TileContent({
    required this.image,
    required this.dimension,
    required this.correctRow,
    required this.correctCol,
    required this.isCorrect,
    required this.slice,
    required this.numberText,
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
            const BoxShadow(color: Color(0xFF4CAF50), spreadRadius: -2),
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
              ? const Color(0xFF4CAF50).withValues(alpha: 0.9)
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
            // Tile image content
            if (slice != null)
              FittedBox(
                fit: BoxFit.cover,
                child: RawImage(
                  image: slice,
                  filterQuality: FilterQuality.high,
                ),
              )
            else if (image != null)
              CustomPaint(
                painter: _ImagePainter(
                  image!,
                  dimension: dimension,
                  clipRow: correctRow,
                  clipCol: correctCol,
                ),
              )
            else
              const SizedBox.shrink(),

            // Number badge
            if (numberText != null)
              Positioned(
                top: 4,
                left: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        numberText!,
                        style: GoogleFonts.vazirmatn(
                          fontSize: dimension <= 3
                              ? 14
                              : (dimension == 4 ? 12.5 : 11),
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Tap scale animation
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

// Action bar
class ActionBar extends StatelessWidget {
  final Strings strings;
  final VoidCallback onPickImage;
  final VoidCallback onShuffleIncorrect;
  final VoidCallback onReset;
  final VoidCallback onOpenSettings;
  final VoidCallback? onHelp;
  const ActionBar({
    super.key,
    required this.strings,
    required this.onPickImage,
    required this.onShuffleIncorrect,
    required this.onReset,
    required this.onOpenSettings,
    this.onHelp,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final outline = theme.colorScheme.outlineVariant;
    final primary = theme.colorScheme.primary;
    final bgColor = isDark
        ? Colors.black.withValues(alpha: 0.36)
        : Colors.white.withValues(alpha: 0.78);
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(color: outline.withValues(alpha: 0.6)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bgColor,
                  Color.alphaBlend(primary.withValues(alpha: 0.06), bgColor),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarIconButton(
                  icon: Icons.image_outlined,
                  label: strings.abPickImage,
                  onTap: onPickImage,
                  color: const ui.Color.fromARGB(255, 241, 15, 211),
                ),
                _BarIconButton(
                  icon: Icons.auto_fix_high,
                  label: strings.abShuffleIncorrect,
                  onTap: onShuffleIncorrect,
                  color: const Color(0xFF9B6BFF),
                ),
                _BarIconButton(
                  icon: Icons.refresh,
                  label: strings.abReset,
                  onTap: onReset,
                  color: const Color(0xFFFF5A5F),
                ),
                _BarIconButton(
                  icon: Icons.settings,
                  label: strings.abSettings,
                  onTap: onOpenSettings,
                  color: const Color(0xFF607D8B),
                ),
                if (onHelp != null)
                  _BarIconButton(
                    icon: Icons.help_outline,
                    label: strings.abHelp,
                    onTap: onHelp!,
                    color: const ui.Color.fromARGB(255, 58, 161, 115),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _BarIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    TextStyle baseText = GoogleFonts.vazirmatn(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.1,
      color: color.withValues(alpha: 0.95),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.18),
        highlightColor: color.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(label, style: baseText),
            ],
          ),
        ),
      ),
    );
  }
}

// Win overlay
class WhiteWinBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final String movesText;
  final String timeText;
  final Color accent;
  final String movesLabel;
  final String timeLabel;
  const WhiteWinBox({
    super.key,
    required this.title,
    required this.subtitle,
    required this.movesText,
    required this.timeText,
    required this.accent,
    required this.movesLabel,
    required this.timeLabel,
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
                    children: [
                      const Text('🔢 '),
                      Text('$movesLabel: $movesText'),
                    ],
                  ),
                ),
                chip(
                  from: const Color(0xFF00E5FF),
                  to: const Color(0xFF72F1B8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⏱️ '),
                      Text('$timeLabel: $timeText'),
                    ],
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

// Bottom sheets (Help & Settings simplified wrappers)
class HelpBottomSheet extends StatelessWidget {
  final AppLanguage language;
  final Strings strings;
  const HelpBottomSheet({
    super.key,
    required this.language,
    required this.strings,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.32,
        maxChildSize: 0.95,
        builder: (ctx, sc) => Directionality(
          textDirection: language == AppLanguage.fa
              ? TextDirection.rtl
              : TextDirection.ltr,
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
                    strings.helpHowTo,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.helpHowToBody,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.helpFeatures,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _helpItemRow(
                    Icons.image_outlined,
                    const Color(0xFF34C3FF),
                    strings.helpPickImageTitle,
                    strings.helpPickImageDesc,
                  ),
                  _helpItemRow(
                    Icons.auto_fix_high,
                    const Color(0xFF9B6BFF),
                    strings.helpShuffleTitle,
                    strings.helpShuffleDesc,
                  ),
                  _helpItemRow(
                    Icons.refresh,
                    const Color(0xFFFF5A5F),
                    strings.helpResetTitle,
                    strings.helpResetDesc,
                  ),
                  _helpItemRow(
                    Icons.settings,
                    const Color(0xFF607D8B),
                    strings.helpSettingsTitle,
                    strings.helpSettingsDesc,
                  ),
                  _helpItemRow(
                    Icons.close_rounded,
                    const Color(0xFFEF5350),
                    strings.helpDeleteTitle,
                    strings.helpDeleteDesc,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.helpScoreTime,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.helpScoreTimeDesc,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.helpTips,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.helpTipsBody,
                    textAlign: language == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      strings.close,
                      style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
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

  Widget _helpItemRow(IconData icon, Color color, String title, String desc) {
    final textDirection = language == AppLanguage.fa
        ? TextAlign.right
        : TextAlign.left;
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
                  textAlign: textDirection,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(desc, textAlign: textDirection),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsBottomSheet extends StatefulWidget {
  final AppLanguage language;
  final Strings strings;
  final bool darkMode;
  final bool showNumbers;
  final int dimension;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<bool> onNumbersChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<int> onDimensionChanged;
  const SettingsBottomSheet({
    super.key,
    required this.language,
    required this.strings,
    required this.darkMode,
    required this.showNumbers,
    required this.dimension,
    required this.onThemeChanged,
    required this.onNumbersChanged,
    required this.onLanguageChanged,
    required this.onDimensionChanged,
  });
  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  late bool isDark;
  late bool showNums;
  late int dim;
  late AppLanguage lang;
  @override
  void initState() {
    super.initState();
    isDark = widget.darkMode;
    showNums = widget.showNumbers;
    dim = widget.dimension;
    lang = widget.language;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.30,
        maxChildSize: 0.80,
        builder: (ctx, sc) => Directionality(
          textDirection: lang == AppLanguage.fa
              ? TextDirection.rtl
              : TextDirection.ltr,
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
                    widget.strings.settingsTitle,
                    textAlign: lang == AppLanguage.fa
                        ? TextAlign.right
                        : TextAlign.left,
                    style: GoogleFonts.vazirmatn(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(
                      widget.strings.settingsDark,
                      style: GoogleFonts.vazirmatn(),
                    ),
                    value: isDark,
                    onChanged: (v) {
                      setState(() => isDark = v);
                      widget.onThemeChanged(v);
                    },
                    secondary: const Icon(Icons.dark_mode),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    title: Text(
                      widget.strings.settingsShowNumbers,
                      style: GoogleFonts.vazirmatn(),
                    ),
                    value: showNums,
                    onChanged: (v) {
                      setState(() => showNums = v);
                      widget.onNumbersChanged(v);
                    },
                    secondary: const Icon(Icons.pin),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 6),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    widget.strings.settingsPuzzleSize,
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
                            lang == AppLanguage.fa
                                ? '🧩 ${toFaDigits('$d در $d')}'
                                : '🧩 $d x $d',
                            style: GoogleFonts.vazirmatn(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          selected: dim == d,
                          onSelected: (_) {
                            setState(() => dim = d);
                            widget.onDimensionChanged(d);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    widget.strings.settingsLanguage,
                    style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: Text(
                          widget.strings.langFa,
                          style: GoogleFonts.vazirmatn(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: lang == AppLanguage.fa,
                        onSelected: (_) {
                          setState(() => lang = AppLanguage.fa);
                          widget.onLanguageChanged(AppLanguage.fa);
                        },
                      ),
                      ChoiceChip(
                        label: Text(
                          widget.strings.langEn,
                          style: GoogleFonts.vazirmatn(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: lang == AppLanguage.en,
                        onSelected: (_) {
                          setState(() => lang = AppLanguage.en);
                          widget.onLanguageChanged(AppLanguage.en);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      widget.strings.close,
                      style: GoogleFonts.vazirmatn(fontWeight: FontWeight.w700),
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
