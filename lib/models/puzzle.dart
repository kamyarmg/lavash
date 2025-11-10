import 'dart:math';

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
    // Creates a solved board: each tile's current position equals its goal.
    final total = dim * dim;
    final tiles = List.generate(
      total,
      (i) => Tile(correctIndex: i, currentIndex: i),
    );
    return PuzzleBoard._(dim, tiles);
  }

  bool get isSolved => tiles.every((t) => t.inCorrectPlace);
  int get emptyTileIndex => tiles.length - 1;

  List<int> movableTileArrayIndexes() {
    // Returns indexes of tiles (in the tiles list) that can move into the empty space.
    // We locate the empty tile's logical grid position then test 4-neighbors.
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
    // Swaps the chosen tile with the empty tile if adjacent. Returns true if moved.
    if (!movableTileArrayIndexes().contains(tileArrayIndex)) return false;
    final empty = tiles[emptyTileIndex];
    final tile = tiles[tileArrayIndex];
    final temp = tile.currentIndex;
    tile.currentIndex = empty.currentIndex;
    empty.currentIndex = temp;
    return true;
  }

  PuzzleBoard shuffled(Random rng) {
    // Generates a random solvable permutation by shuffling until the parity & rules match.
    // Attempts are capped for safety; falls back to current board if none found.
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
    // Standard sliding puzzle solvability check:
    // - For odd dimensions: inversion count must be even.
    // - For even dimensions: parity depends on row of empty from bottom.
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
    // Light shuffle: only repositions currently incorrect non-empty tiles.
    // Tries multiple random reassignments and keeps the first solvable outcome.
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
