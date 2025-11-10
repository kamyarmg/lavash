import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lavash/models/puzzle.dart';

void main() {
  group('PuzzleBoard', () {
    test('solved factory builds ordered tiles', () {
      final board = PuzzleBoard.solved(3);
      expect(board.dimension, 3);
      expect(board.tiles.length, 9);
      for (int i = 0; i < board.tiles.length; i++) {
        expect(board.tiles[i].correctIndex, i);
        expect(board.tiles[i].currentIndex, i);
      }
      expect(board.isSolved, isTrue);
    });

    test('move swaps with empty when adjacent', () {
      final board = PuzzleBoard.solved(3);
      // Empty tile is last (index 8). Tile with linear index 7 is adjacent.
      final tileArrayIndex = board.tiles.indexWhere((t) => t.currentIndex == 7);
      final emptyBefore = board.tiles.last.currentIndex;
      final moved = board.move(tileArrayIndex);
      expect(moved, isTrue);
      // Now tile at arrayIndex should have empty position and empty swapped.
      expect(board.tiles.last.currentIndex, 7);
      expect(board.tiles[tileArrayIndex].currentIndex, emptyBefore);
    });

    test(
      'shuffled board preserves tile permutation and solvability attempt',
      () {
        final rng = Random(1234);
        final board = PuzzleBoard.solved(3).shuffled(rng);
        expect(board.tiles.length, 9);
        // Permutation test
        final positions = board.tiles.map((t) => t.currentIndex).toList();
        expect(positions.toSet().length, 9);
        expect(positions.every((p) => p >= 0 && p < 9), isTrue);
      },
    );

    test('partialShuffleIncorrect keeps permutation', () {
      final rng = Random(42);
      var board = PuzzleBoard.solved(3).shuffled(rng);
      board = board.partialShuffleIncorrect(rng);
      final after = board.tiles.map((t) => t.currentIndex).toList();
      expect(after.toSet().length, 9);
      expect(after.every((p) => p >= 0 && p < 9), isTrue);
      // Either changed or already solved (rare). Not asserting difference strictly.
      expect(board.tiles.length, 9);
    });
  });
}
