import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'pc_models.dart';
import 'pc_proxy_server.dart';

class PcShakaPlayerController {
  static bool _envInitialized = false;

  final PcLocalPlayerServer _server = PcLocalPlayerServer.instance;
  final WebviewController _webview = WebviewController();
  final List<StreamSubscription> _subs = [];

  final void Function(String state) onStateChanged;
  final void Function(String message) onError;
  final void Function(List<Map<String, dynamic>> videos, List<Map<String, dynamic>> audios) onTracksChanged;
  final VoidCallback onViewReady;

  bool _disposed = false;
  bool _engineReady = false;
  bool _initialized = false;
  PcResolvedPlayback? _pendingPlayback;
  String _resizeMode = 'fill';
  double _volume = 1.0;
  bool _muted = false;

  PcShakaPlayerController({
    required this.onStateChanged,
    required this.onError,
    required this.onTracksChanged,
    required this.onViewReady,
  });

  bool get isInitialized => _initialized;

  String? _resolveWebViewUserDataPath() {
    try {
      final baseDir = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      final dir = Directory('$baseDir${Platform.pathSeparator}AnasTV${Platform.pathSeparator}WebView2');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    try {
      await _server.start();
      if (_disposed) return;

      if (!_envInitialized) {
        _envInitialized = true;
        final userDataPath = _resolveWebViewUserDataPath();
        final originFlag = '--unsafely-treat-insecure-origin-as-secure=${_server.origin}';
        try {
          await WebviewController.initializeEnvironment(
            userDataPath: userDataPath,
            additionalArguments:
                '--autoplay-policy=no-user-gesture-required --disable-features=HardwareMediaKeyHandling --enable-features=PlatformHEVCDecoderSupport --ignore-gpu-blocklist $originFlag',
          );
        } catch (_) {}
      }

      await _webview.initialize();
      if (_disposed) return;

      await _webview.setBackgroundColor(Colors.black);
      await _webview.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _webview.setDefaultContextMenusEnabled(false);
      await _webview.setZoomControlEnabled(false);

      _subs.add(
        _webview.webMessage.listen((raw) {
          if (_disposed) return;
          try {
            final map = raw is Map
                ? Map<String, dynamic>.from(raw)
                : jsonDecode(raw.toString()) as Map<String, dynamic>;
            final type = (map['type'] ?? '').toString();
            if (type == 'engineReady') {
              _engineReady = true;
              _applyAspectAndVolume();
              final pending = _pendingPlayback;
              if (pending != null) {
                _pendingPlayback = null;
                _loadIntoShaka(pending);
              }
            } else if (type == 'state') {
              onStateChanged((map['state'] ?? 'idle').toString());
            } else if (type == 'tracks') {
              final videos = ((map['videos'] as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              final audios = ((map['audios'] as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              onTracksChanged(videos, audios);
            } else if (type == 'error') {
              onError((map['message'] ?? 'Shaka Player error').toString());
            }
          } catch (_) {}
        }),
      );

      _subs.add(
        _webview.onLoadError.listen((status) {
          if (_disposed) return;
          onError('WebView2 load error: ${status.name}');
        }),
      );

      _initialized = true;
      onViewReady();
      await _webview.loadUrl(_server.playerPageUrl);
    } on PlatformException catch (e) {
      if (!_disposed) {
        onError(
          'Windows WebView2 initialize nahi ho paaya (${e.code}): ${e.message ?? ''}\n'
          'Ensure Microsoft Edge WebView2 Runtime is installed on this PC.',
        );
      }
    } catch (e) {
      if (!_disposed) {
        onError('PC WebView player setup failed: $e');
      }
    }
  }

  void play(PcResolvedPlayback playback) {
    if (_disposed) return;
    if (!_engineReady || !_initialized) {
      _pendingPlayback = playback;
      return;
    }
    _loadIntoShaka(playback);
  }

  Future<void> _loadIntoShaka(PcResolvedPlayback playback) async {
    if (_disposed || !_engineReady) return;
    final normalizedClearKeys = <String, String>{};
    playback.clearKeys.forEach((k, v) {
      final hexK = _toHexKey(k);
      final hexV = _toHexKey(v);
      if (hexK.isNotEmpty && hexV.isNotEmpty) {
        normalizedClearKeys[hexK] = hexV;
      }
    });

    final sid = _server.registerSession(
      PcProxySession(
        streamUrl: playback.streamUrl,
        headers: playback.headers,
        drmLicenseUrl: playback.drmLicenseUrl,
        drmHeaders: playback.drmHeaders,
        clearKeys: normalizedClearKeys,
      ),
    );

    final proxiedUrl = _server.toProxyUrl(sid, playback.streamUrl);
    final drmProxyUrl = playback.drmLicenseUrl.isNotEmpty
        ? _server.toDrmProxyUrl(sid, playback.drmLicenseUrl)
        : '';

    final lowerUrl = playback.streamUrl.toLowerCase();
    String? mimeType;
    if (lowerUrl.contains('.mpd')) {
      mimeType = 'application/dash+xml';
    } else if (lowerUrl.contains('.m3u8')) {
      mimeType = 'application/x-mpegURL';
    }

    final payload = jsonEncode({
      'sid': sid,
      'proxiedUrl': proxiedUrl,
      'drmProxyUrl': drmProxyUrl,
      'clearKeys': normalizedClearKeys,
      if (mimeType != null) 'mimeType': mimeType,
    });

    try {
      await _webview.executeScript('window.anasLoadStream($payload);');
    } catch (e) {
      if (!_disposed) onError('Shaka script execution failed: $e');
    }
  }

  static String _toHexKey(String input) {
    final clean = input.trim().replaceAll('-', '');
    if (clean.length == 32 && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(clean)) {
      return clean.toLowerCase();
    }
    try {
      var b64 = clean.replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final bytes = base64Decode(b64);
      final sb = StringBuffer();
      for (final b in bytes) {
        sb.write(b.toRadixString(16).padLeft(2, '0'));
      }
      return sb.toString();
    } catch (_) {
      return clean.toLowerCase();
    }
  }

  Future<void> setPaused(bool paused) async {
    if (_disposed || !_engineReady) return;
    await _webview.executeScript('window.anasSetPaused(${paused ? 'true' : 'false'});').catchError((_) {});
  }

  Future<void> setResizeMode(String mode) async {
    _resizeMode = mode;
    if (_disposed || !_engineReady) return;
    await _webview.executeScript('window.anasSetAspect(${jsonEncode(mode)});').catchError((_) {});
  }

  Future<void> setVolume(double volume, {bool? muted}) async {
    _volume = volume.clamp(0.0, 1.0);
    if (muted != null) _muted = muted;
    if (_disposed || !_engineReady) return;
    await _webview
        .executeScript('window.anasSetVolume($_volume, ${_muted ? 'true' : 'false'});')
        .catchError((_) {});
  }

  Future<void> selectVideoVariant(int id) async {
    if (_disposed || !_engineReady) return;
    await _webview.executeScript('window.anasSelectVideoVariant($id);').catchError((_) {});
  }

  Future<void> selectAudioTrack(String language, String role) async {
    if (_disposed || !_engineReady) return;
    await _webview
        .executeScript('window.anasSelectAudioTrack(${jsonEncode(language)}, ${jsonEncode(role)});')
        .catchError((_) {});
  }

  Future<void> stop() async {
    if (_disposed || !_engineReady) return;
    await _webview.executeScript('window.anasStop();').catchError((_) {});
  }

  void _applyAspectAndVolume() {
    setResizeMode(_resizeMode);
    setVolume(_volume, muted: _muted);
  }

  Widget buildView() {
    if (!_initialized) {
      return const ColoredBox(color: Colors.black);
    }
    return IgnorePointer(
      child: Webview(
        _webview,
        permissionRequested: (_, __, ___) => WebviewPermissionDecision.allow,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (_initialized) {
      await _webview.dispose().catchError((_) {});
    }
    await _server.stop();
  }
}
