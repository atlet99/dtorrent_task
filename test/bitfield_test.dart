import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/peer/bitfield.dart';

void main() {
  group('Bitfield Tests', () {
    test('should create empty bitfield', () {
      final bitfield = Bitfield.createEmptyBitfield(100);

      expect(bitfield.piecesNum, equals(100));
      expect(bitfield.buffer.length, equals(13)); // 100/8 = 12.5, rounded up

      // All bits should be 0
      for (var byte in bitfield.buffer) {
        expect(byte, equals(0));
      }
    });

    test('should set and get bits correctly', () {
      final bitfield = Bitfield.createEmptyBitfield(100);

      bitfield.setBit(0, true);
      expect(bitfield.getBit(0), isTrue);

      bitfield.setBit(5, true);
      expect(bitfield.getBit(5), isTrue);
      expect(bitfield.getBit(4), isFalse);

      bitfield.setBit(0, false);
      expect(bitfield.getBit(0), isFalse);
    });

    test('should handle edge cases for bit indices', () {
      final bitfield = Bitfield.createEmptyBitfield(100);

      // Negative index
      bitfield.setBit(-1, true);
      expect(bitfield.getBit(-1), isFalse);

      // Index out of range
      bitfield.setBit(100, true);
      expect(bitfield.getBit(100), isFalse);

      // Valid edge indices
      bitfield.setBit(0, true);
      bitfield.setBit(99, true);
      expect(bitfield.getBit(0), isTrue);
      expect(bitfield.getBit(99), isTrue);
    });

    test('should track completed pieces', () {
      final bitfield = Bitfield.createEmptyBitfield(100);

      expect(bitfield.completedPieces.length, equals(0));

      bitfield.setBit(0, true);
      bitfield.setBit(5, true);
      bitfield.setBit(10, true);

      expect(bitfield.completedPieces.length, equals(3));
      expect(bitfield.completedPieces.contains(0), isTrue);
      expect(bitfield.completedPieces.contains(5), isTrue);
      expect(bitfield.completedPieces.contains(10), isTrue);
    });

    test('should check if has complete piece', () {
      final bitfield = Bitfield.createEmptyBitfield(100);

      expect(bitfield.haveCompletePiece(), isFalse);

      bitfield.setBit(50, true);
      expect(bitfield.haveCompletePiece(), isTrue);
    });

    test('should check if has all pieces', () {
      final bitfield = Bitfield.createEmptyBitfield(10);

      expect(bitfield.haveAll(), isFalse);

      for (var i = 0; i < 10; i++) {
        bitfield.setBit(i, true);
      }

      expect(bitfield.haveAll(), isTrue);
    });

    test('should copy from existing buffer', () {
      final original = Bitfield.createEmptyBitfield(100);
      original.setBit(0, true);
      original.setBit(50, true);

      final copied =
          Bitfield.copyFrom(100, original.buffer, 0, original.buffer.length);

      expect(copied.piecesNum, equals(100));
      expect(copied.getBit(0), isTrue);
      expect(copied.getBit(50), isTrue);
      expect(copied.getBit(1), isFalse);
    });

    test('should handle pieces count not divisible by 8', () {
      final bitfield = Bitfield.createEmptyBitfield(123);

      // 123 / 8 = 15.375, should round up to 16 bytes
      expect(bitfield.buffer.length, equals(16));
      expect(bitfield.piecesNum, equals(123));

      // Should be able to set last bit
      bitfield.setBit(122, true);
      expect(bitfield.getBit(122), isTrue);
    });
  });
}
