import 'dart:async';

import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/utils/debouncer.dart';

void main() {
  group('Debouncer Tests', () {
    test('should debounce rapid calls', () async {
      var callCount = 0;
      var lastValue = 0;
      final debouncer = Debouncer<int>(
        const Duration(milliseconds: 100),
        (value) {
          callCount++;
          lastValue = value;
        },
      );

      // Rapid calls
      debouncer.call(1);
      debouncer.call(2);
      debouncer.call(3);
      debouncer.call(4);
      debouncer.call(5);

      // Should not be called yet
      expect(callCount, equals(0));

      // Wait for debounce delay
      await Future.delayed(const Duration(milliseconds: 150));

      // Should be called once with last value
      expect(callCount, equals(1));
      expect(lastValue, equals(5));
    });

    test('should handle multiple debounced sequences', () async {
      var callCount = 0;
      final debouncer = Debouncer<int>(
        const Duration(milliseconds: 50),
        (value) {
          callCount++;
        },
      );

      debouncer.call(1);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(callCount, equals(1));

      debouncer.call(2);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(callCount, equals(2));
    });

    test('should flush immediately', () async {
      var callCount = 0;
      var lastValue = 0;
      final debouncer = Debouncer<int>(
        const Duration(milliseconds: 1000),
        (value) {
          callCount++;
          lastValue = value;
        },
      );

      debouncer.call(42);
      expect(callCount, equals(0));

      debouncer.flush();
      expect(callCount, equals(1));
      expect(lastValue, equals(42));

      // Should not be called again after delay
      await Future.delayed(const Duration(milliseconds: 1100));
      expect(callCount, equals(1));
    });

    test('should dispose correctly', () async {
      var callCount = 0;
      final debouncer = Debouncer<int>(
        const Duration(milliseconds: 50),
        (value) {
          callCount++;
        },
      );

      debouncer.call(1);
      debouncer.dispose();

      // Should not be called after dispose
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callCount, equals(0));
    });

    test('should handle null values correctly', () async {
      String? lastValue;
      final debouncer = Debouncer<String?>(
        const Duration(milliseconds: 50),
        (value) {
          lastValue = value;
        },
      );

      debouncer.call('test');
      debouncer.call(null);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(lastValue, isNull);
    });
  });
}
