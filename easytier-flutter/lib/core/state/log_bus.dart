import 'package:flutter/foundation.dart';

/// Severity of a client-side log line, matching the levels shown in Settings.
enum LogLevel {
  debug,
  info,
  warn,
  error;

  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warn => 'WARN',
    LogLevel.error => 'ERROR',
  };
}

/// One client log line. Core (Rust) does not expose a log stream over the FFI
/// seam yet, so these are the client's own lifecycle/RPC lines — clearly
/// labelled as "Client logs" in the UI so nobody mistakes them for kernel logs.
class LogEntry {
  const LogEntry({
    required this.at,
    required this.level,
    required this.source,
    required this.message,
  });

  final DateTime at;
  final LogLevel level;
  final String source;
  final String message;

  String get timeLabel {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String format() => '${at.toIso8601String()} ${level.name.toUpperCase()} '
      '[$source] $message';
}

/// Bounded in-memory ring buffer for the client log viewer.
class LogBus extends ChangeNotifier {
  LogBus({this.capacity = 500});

  final int capacity;
  final List<LogEntry> _entries = [];

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void add(LogLevel level, String source, String message) {
    _entries.insert(
      0,
      LogEntry(at: DateTime.now(), level: level, source: source, message: message),
    );
    if (_entries.length > capacity) _entries.removeLast();
    notifyListeners();
  }

  void debug(String source, String message) => add(LogLevel.debug, source, message);

  void info(String source, String message) => add(LogLevel.info, source, message);

  void warn(String source, String message) => add(LogLevel.warn, source, message);

  void error(String source, String message) => add(LogLevel.error, source, message);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String exportText() => _entries.reversed.map((e) => e.format()).join('\n');
}
