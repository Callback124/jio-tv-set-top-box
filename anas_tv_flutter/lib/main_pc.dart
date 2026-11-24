import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'pc/pc_home_page.dart';
import 'pc/pc_trace_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PcTraceLog.write('app: startup');
  try {
    MediaKit.ensureInitialized();
    PcTraceLog.write('app: MediaKit.ensureInitialized ok');
  } catch (e, st) {
    PcTraceLog.write('app: MediaKit.ensureInitialized failed: $e\n$st');
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    PcTraceLog.write('flutterError: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    PcTraceLog.write('platformError: $error\n$stack');
    return true;
  };

  runApp(const AnasTvPcApp());
}
