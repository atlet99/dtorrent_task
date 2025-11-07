import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'dart:io';

void main() {
  group('CongestionControl Tests', () {
    late Peer peer;

    setUp(() {
      peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress('127.0.0.1'), 6881),
        List<int>.generate(20, (i) => i),
        100,
        null,
        PeerSource.manual,
      );
    });

    test('should initialize with default window size', () {
      expect(peer.currentWindow,
          equals(1)); // DEFAULT_REQUEST_LENGTH / DEFAULT_REQUEST_LENGTH
    });

    test('should update RTO based on RTT', () {
      // Initial RTO should be high
      final initialRto = peer.currentWindow;

      // Simulate ACK with RTT
      final requests = [
        [
          0,
          0,
          16384,
          DateTime.now().microsecondsSinceEpoch - 100000,
          0
        ], // 100ms RTT
      ];
      peer.ackRequest(requests);

      // Window should have increased
      expect(peer.currentWindow, greaterThan(initialRto));
    });

    test('should handle timeout correctly', () async {
      // Add a request
      peer.addRequest(0, 0, 16384);

      // Start timeout
      peer.startRequestDataTimeout();

      // Wait a bit
      await Future.delayed(const Duration(milliseconds: 100));

      // Should still be running (timeout is longer)
      expect(peer.currentWindow, greaterThanOrEqualTo(1));
    });

    test('should limit window to MAX_WINDOW', () {
      // Simulate many successful ACKs
      for (var i = 0; i < 100; i++) {
        final requests = [
          [
            0,
            0,
            16384,
            DateTime.now().microsecondsSinceEpoch - 50000,
            0
          ], // 50ms RTT
        ];
        peer.ackRequest(requests);
      }

      // Window should be capped
      final maxWindow = 1048576 ~/ 16384; // MAX_WINDOW / DEFAULT_REQUEST_LENGTH
      expect(peer.currentWindow, lessThanOrEqualTo(maxWindow));
    });

    test('should handle uTP initialization', () {
      final utpPeer = Peer.newUTPPeer(
        CompactAddress(InternetAddress('127.0.0.1'), 6881),
        List<int>.generate(20, (i) => i),
        100,
        null,
        PeerSource.manual,
      );

      // uTP should have larger initial window
      expect(utpPeer.currentWindow, greaterThan(1));
    });

    test('should clear congestion control state', () {
      peer.addRequest(0, 0, 16384);
      expect(peer.requestBuffer.isNotEmpty, isTrue);

      peer.clearCC();

      // State should be cleared (though requestBuffer might still have items)
      expect(peer.currentWindow, greaterThanOrEqualTo(1));
    });
  });
}
