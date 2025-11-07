import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/src/piece/piece_manager.dart';
import 'package:dtorrent_task_v2/src/piece/piece_manager_events.dart';
import 'package:dtorrent_task_v2/src/piece/base_piece_selector.dart';
import 'package:dtorrent_task_v2/src/peer/bitfield.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_creator.dart';

void main() {
  group('PieceManager Tests', () {
    late Torrent mockTorrent;
    late Bitfield bitfield;
    late PieceManager pieceManager;
    late File tempFile;

    setUp(() async {
      // Create a temporary file for testing
      tempFile = File(
          '${Directory.systemTemp.path}/test_file_${DateTime.now().millisecondsSinceEpoch}.dat');
      await tempFile
          .writeAsBytes(List<int>.generate(16384 * 10, (i) => i % 256));

      // Create a torrent from the file
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        trackers: [],
      );
      mockTorrent = await TorrentCreator.createTorrent(tempFile.path, options);

      bitfield = Bitfield.createEmptyBitfield(10);
      pieceManager = PieceManager.createPieceManager(
        BasePieceSelector(),
        mockTorrent,
        bitfield,
      );
    });

    tearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    test('should initialize with correct number of pieces', () {
      expect(pieceManager.length, equals(10));
      expect(pieceManager.pieces.length, equals(10));
    });

    test('should process received block correctly', () {
      final pieceIndex = 0;
      final begin = 0;
      final block = List<int>.generate(16384, (i) => i % 256);

      pieceManager.processReceivedBlock(pieceIndex, begin, block);

      final piece = pieceManager[pieceIndex];
      expect(piece, isNotNull);
      expect(piece!.isCompletelyDownloaded, isTrue);
    });

    test('should track downloading pieces', () {
      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress('127.0.0.1'), 6881),
        List<int>.generate(20, (i) => i),
        10,
        null,
        PeerSource.manual,
      );

      final selectedPiece = pieceManager.selectPiece(peer, pieceManager, null);
      expect(selectedPiece, isNotNull);
      expect(pieceManager.downloadingPieces.contains(selectedPiece!.index),
          isTrue);
    });

    test('should emit PieceAccepted event when piece is valid', () async {
      var acceptedIndex = -1;
      pieceManager.events.on<PieceAccepted>((event) {
        acceptedIndex = event.pieceIndex;
      });

      final pieceIndex = 0;
      final piece = pieceManager[pieceIndex]!;

      // Fill piece with correct data (read from temp file)
      piece.init();
      final fileData = await tempFile.readAsBytes();
      final pieceData = fileData.sublist(0, 16384);
      pieceManager.processReceivedBlock(pieceIndex, 0, pieceData);

      // Wait a bit for event processing
      await Future.delayed(const Duration(milliseconds: 100));

      // Piece should be accepted if data matches hash
      if (piece.isCompletelyDownloaded) {
        expect(acceptedIndex, equals(pieceIndex));
      }
    });

    test('should process piece write complete', () {
      final pieceIndex = 0;
      final piece = pieceManager[pieceIndex]!;

      expect(piece.flushed, isFalse);

      pieceManager.processPieceWriteComplete(pieceIndex);

      expect(piece.flushed, isTrue);
    });

    test('should dispose correctly', () {
      expect(pieceManager.isDisposed, isFalse);

      pieceManager.dispose();

      expect(pieceManager.isDisposed, isTrue);
      expect(pieceManager.length, equals(0));
    });
  });
}
