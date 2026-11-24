import 'dart:io';

class PcTraceLog {
  PcTraceLog._();

  static File? _file;
  static bool _disabled = false;

  static void write(String message) {
    if (_disabled || !Platform.isWindows) return;
    try {
      var file = _file;
      if (file == null) {
        final base = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['TEMP'] ?? '.';
        final dir = Directory('$base\\AnasTV');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        file = File('${dir.path}\\pc_player_trace.log');
        if (file.existsSync() && file.lengthSync() > 256 * 1024) {
          file.writeAsStringSync('', flush: true);
        }
        _file = file;
      }
      final ts = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$ts] $message\r\n', mode: FileMode.append, flush: true);
    } catch (_) {
      _disabled = true;
    }
  }
}
