## 0.0.1

- Initial version

## 0.0.2

- Fix license file error
- Fix example error

## 0.1.1
- Add DHT support
- Add PEX support
- Change Tracker
- Fix some bugs

## 0.1.2
- Support peer reconnect
- Fix some bugs

## 0.1.4
- Fix some issues
- Fix peer download slow issue

## 0.2.0
- Add UTP support
- Add holepunch extension
- Add LSD extension
- Fix PEX extension bugs

## 0.2.1
- Change congestion control

## 0.3.0
- Add Send Metadata extension (BEP0009)

## 0.3.1
- nullsafety

## 0.3.2
- pub.dev fixes

## 0.3.3
- migrate to events_emitter2

## 0.3.4
- use events_emitter and streams when possible
- video streaming fixes
- fix tests
- validate completed pieces
- add task start, task stop, task resume events
- move more dynamic types to explicit types
- update deps and sdk constraints

## 0.3.5
- use more broad collection constraints

## 0.4.0
- enable utp
- decouple some parts of the code
- use logging package
- select pieces when stream is seeking
- cache piece in memory until it is validated then write to disk
- enable lsd
- fixes for PEX
- emit useful events
- add simple binary for testing
- optimizing
- fix memory leaks
- some refactoring and cleanup

## 0.4.1
- update dependencies to latest compatible versions
- upgrade SDK constraint to >=3.0.0
- fix dead code warnings in examples
- remove unused code (_hookUTP method, unused imports)
- fix TCPConnectException to properly use exception field
- update analysis options to disable constant naming checks

## 0.4.2
- update mime dependency from ^1.0.6 to ^2.0.0
- optimize lookupMimeType usage to avoid duplicate calls
- update lints dev dependency from ^2.1.1 to ^6.0.0
- fix linter warnings for new lint rules (unnecessary_library_name, strict_top_level_inference, unintended_html_in_doc_comment)
- fix uTP RangeError crashes with comprehensive protection:
  - add buffer bounds validation before all setRange operations
  - add message length validation (negative, oversized, and overflow values)
  - add integer overflow protection for message length calculations
  - wrap all critical uTP operations in try-catch blocks with RangeError handling
  - add RangeError metrics tracking (Peer.rangeErrorCount, Peer.utpRangeErrorCount)
  - add detailed logging for uTP debugging (buffer sizes, message parsing)
  - extract magic numbers to constants (MAX_MESSAGE_SIZE, BUFFER_SIZE_WARNING_THRESHOLD)
- create comprehensive test suite for uTP RangeError protection:
  - utp_range_error_protection_test.dart: basic validation tests
  - utp_stress_test.dart: stress tests with 50+ parallel peers
  - utp_reorder_test.dart: packet reordering and burst ACK tests
  - utp_extreme_values_test.dart: extreme value tests (large seq/ack, overflows)
  - utp_long_session_test.dart: long session stability tests

## 0.4.3
- fix critical bug where downloads don't start despite connected peers (fixes #4)
- fix race condition in bitfield processing when peer sends unchoke before interested
- optimize progress event emission with debouncing to reduce UI update frequency
- improve uTP congestion control with optimized initial window size
- add streaming isolate support for better performance during video streaming
- export magnet parser and torrent creator in public API