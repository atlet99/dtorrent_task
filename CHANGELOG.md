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