import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'pc_models.dart';
import 'pc_proxy_server.dart';
import 'pc_trace_log.dart';

/// Shared singleton native MPV/VideoController engine for Windows.
/// Uses ANGLE D3D11 GpuTexture presentation (`enableHardwareAcceleration: true`)
/// paired with CPU software HEVC decoding (`hwdec: no`) so Windows PCs without
/// Microsoft HEVC Video Extensions render decoded frames reliably without
/// PixelBuffer black screens or Windows FFI disposal races.
class _MpvSharedEngine {
  _MpvSharedEngine._();
  static final _MpvSharedEngine instance = _MpvSharedEngine._();

  Player? _player;
  VideoController? _videoController;
  Future<void>? _initFuture;
  PcMpvPlayerController? _activeDelegate;
  final List<StreamSubscription> _subs = [];
  bool _ready = false;
  String? lastLibmpvError;

  bool get isReady => _ready && _player != null && _videoController != null;
  VideoController? get videoController => _videoController;
  Player? get player => _player;

  void attach(PcMpvPlayerController delegate) {
    _activeDelegate = delegate;
  }

  void detach(PcMpvPlayerController delegate) {
    if (identical(_activeDelegate, delegate)) {
      _activeDelegate = null;
    }
  }

  Future<void> ensureInitialized() {
    if (isReady) return Future<void>.value();
    return _initFuture ??= _initInternal().catchError((e, st) {
      PcTraceLog.write('mpv: _initInternal error: $e\n$st');
      _initFuture = null;
      throw e;
    });
  }

  Future<void> _initInternal() async {
    PcTraceLog.write('mpv: creating Player');
    final player = Player(
      configuration: const PlayerConfiguration(
        osc: false,
        libass: false,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _player = player;
    PcTraceLog.write('mpv: Player created');

    VideoController controller;
    try {
      PcTraceLog.write('mpv: creating VideoController(gpuTexture, hwdec=no)');
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          hwdec: 'no',
        ),
      );
      await controller.platform.future;
      PcTraceLog.write('mpv: gpuTexture controller ready (id=${controller.id.value})');
    } catch (e) {
      PcTraceLog.write('mpv: gpuTexture failed ($e), falling back to SW PixelBuffer');
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
          hwdec: 'no',
        ),
      );
      await controller.platform.future;
      PcTraceLog.write('mpv: SW controller ready (id=${controller.id.value})');
    }
    _videoController = controller;

    controller.id.addListener(() {
      PcTraceLog.write('mpv: controller.id changed=${controller.id.value}');
      _activeDelegate?.onViewReady();
    });
    controller.rect.addListener(() {
      PcTraceLog.write('mpv: controller.rect changed=${controller.rect.value}');
    });

    if (player.platform is NativePlayer) {
      final native = player.platform as NativePlayer;
      await native.setProperty('hwdec', 'no').catchError((_) {});
      await native.setProperty('vd-lavc-threads', '4').catchError((_) {});
      await native.setProperty('cache', 'yes').catchError((_) {});
      await native.setProperty('demuxer-max-bytes', '32MiB').catchError((_) {});
      await native.setProperty('hr-seek', 'no').catchError((_) {});
      await native.setProperty('sid', 'no').catchError((_) {});
      await native.setProperty('sub-auto', 'no').catchError((_) {});
      await native.setProperty('audio-display', 'no').catchError((_) {});
      await native.setProperty('network-timeout', '15').catchError((_) {});
      PcTraceLog.write('mpv: post-controller native properties applied');
    }

    _subs.add(
      player.stream.log.listen((entry) {
        if (entry.level == 'error' || entry.level == 'fatal' || entry.level == 'warn') {
          final txt = entry.text.trim();
          PcTraceLog.write('libmpv[${entry.level}/${entry.prefix}]: $txt');
          if (entry.level == 'error' || entry.level == 'fatal') {
            lastLibmpvError = txt;
          }
        }
      }),
    );

    bool hasVideoDimensions() {
      final w = player.state.width ?? player.state.videoParams.w ?? 0;
      final h = player.state.height ?? player.state.videoParams.h ?? 0;
      return w > 0 && h > 0;
    }

    _subs.add(
      player.stream.buffering.listen((buffering) {
        final d = _activeDelegate;
        if (d == null) return;
        if (buffering && !player.state.playing) {
          d.onStateChanged('buffering');
        } else if (!buffering && player.state.playing && hasVideoDimensions()) {
          d.onStateChanged('ready');
        }
      }),
    );

    _subs.add(
      player.stream.videoParams.listen((vp) {
        if ((vp.w ?? 0) > 0 && (vp.h ?? 0) > 0) {
          PcTraceLog.write('mpv: videoParams=${vp.w}x${vp.h} fmt=${vp.pixelformat} id=${controller.id.value}');
          _activeDelegate?.onStateChanged('ready');
        }
      }),
    );

    _subs.add(
      player.stream.width.listen((w) {
        if ((w ?? 0) > 0) {
          PcTraceLog.write('mpv: width=$w height=${player.state.height} id=${controller.id.value}');
          _activeDelegate?.onStateChanged('ready');
        }
      }),
    );

    _subs.add(
      player.stream.playing.listen((playing) {
        final d = _activeDelegate;
        if (d != null && playing) {
          final vCount = player.state.tracks.video.where((t) => t.id != 'auto' && t.id != 'no').length;
          final aCount = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').length;
          PcTraceLog.write(
            'mpv: playing=true w=${player.state.width} h=${player.state.height} vp=${player.state.videoParams.w}x${player.state.videoParams.h} vTracks=$vCount aTracks=$aCount id=${controller.id.value}',
          );
          if (hasVideoDimensions()) {
            d.onStateChanged('ready');
          }
        }
      }),
    );

    _subs.add(
      player.stream.completed.listen((completed) {
        final d = _activeDelegate;
        if (d != null && completed) {
          d.onStateChanged('ended');
        }
      }),
    );

    _subs.add(
      player.stream.tracks.listen((_) {
        _activeDelegate?._emitTracks();
      }),
    );

    _subs.add(
      player.stream.track.listen((_) {
        _activeDelegate?._emitTracks();
      }),
    );

    _subs.add(
      player.stream.error.listen((msg) {
        final clean = msg.trim();
        if (clean.isEmpty) return;
        PcTraceLog.write('mpv: stream.error: $clean');
        final d = _activeDelegate;
        if (d == null) return;
        final low = clean.toLowerCase();
        if (low.contains('failed') ||
            low.contains('error') ||
            low.contains('recognized') ||
            low.contains('http') ||
            low.contains('403') ||
            low.contains('404') ||
            low.contains('invalid') ||
            low.contains('unable') ||
            low.contains('denied')) {
          d.onError('HEVC Player error: $clean');
        }
      }),
    );

    _ready = true;
    PcTraceLog.write('mpv: engine _ready=true id=${controller.id.value}');
  }
}

class PcMpvPlayerController {
  final PcLocalPlayerServer _server = PcLocalPlayerServer.instance;
  final _MpvSharedEngine _engine = _MpvSharedEngine.instance;

  final void Function(String state) onStateChanged;
  final void Function(String message) onError;
  final void Function(List<Map<String, dynamic>> videos, List<Map<String, dynamic>> audios) onTracksChanged;
  final VoidCallback onViewReady;

  bool _disposed = false;
  bool _initialized = false;
  String _resizeMode = 'fill';
  double _volume = 1.0;
  bool _muted = false;
  List<VideoTrack> _lastVideoTracks = const [];
  List<AudioTrack> _lastAudioTracks = const [];

  PcMpvPlayerController({
    required this.onStateChanged,
    required this.onError,
    required this.onTracksChanged,
    required this.onViewReady,
  });

  bool get isInitialized => _initialized && _engine.isReady;
  String? get lastTraceHint => _engine.lastLibmpvError;

  Future<void> init() async {
    if (_disposed) return;
    if (isInitialized) {
      _engine.attach(this);
      return;
    }
    try {
      await _server.start();
      if (_disposed) return;
      await _engine.ensureInitialized();
      if (_disposed) return;
      _engine.attach(this);
      _initialized = true;
      onViewReady();
    } catch (e) {
      if (!_disposed) {
        onError('Native HEVC player init failed: $e');
      }
    }
  }

  void _emitTracks() {
    final p = _engine.player;
    if (_disposed || p == null) return;
    final stateTracks = p.state.tracks;
    final activeTrack = p.state.track;

    _lastVideoTracks = stateTracks.video
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    _lastAudioTracks = stateTracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    final videos = <Map<String, dynamic>>[];
    for (var i = 0; i < _lastVideoTracks.length; i++) {
      final t = _lastVideoTracks[i];
      final h = t.h ?? 0;
      final kbps = t.bitrate != null ? (t.bitrate! / 1000).round() : 0;
      final label = h >= 2160
          ? '4K (${h}p)'
          : h >= 1080
              ? '1080p HD'
              : h > 0
                  ? '${h}p'
                  : kbps > 0
                      ? '$kbps kbps'
                      : (t.title ?? 'Stream ${t.id}');
      videos.add({
        'id': i,
        'label': label,
        'height': h,
        'bitrate': kbps,
        'selected': activeTrack.video.id == t.id,
      });
    }
    videos.sort((a, b) {
      final ha = (a['height'] as int?) ?? 0;
      final hb = (b['height'] as int?) ?? 0;
      if (hb != ha) return hb.compareTo(ha);
      return ((b['bitrate'] as int?) ?? 0).compareTo((a['bitrate'] as int?) ?? 0);
    });
    if (videos.isEmpty) {
      videos.add({'id': -1, 'label': 'Highest (HEVC)', 'height': 0, 'bitrate': 0, 'selected': true});
    }

    final audios = <Map<String, dynamic>>[];
    for (var i = 0; i < _lastAudioTracks.length; i++) {
      final t = _lastAudioTracks[i];
      final lang = (t.language ?? '').trim();
      final title = (t.title ?? '').trim();
      final label = lang.isNotEmpty && lang != 'und'
          ? '${lang.toUpperCase()}${title.isNotEmpty ? ' • $title' : ''}'
          : (title.isNotEmpty ? title : 'Audio ${i + 1}');
      audios.add({
        'index': i,
        'language': lang,
        'role': t.id,
        'label': label,
        'selected': activeTrack.audio.id == t.id || (i == 0 && activeTrack.audio.id == 'auto'),
      });
    }

    onTracksChanged(videos, audios);
  }

  Future<void> play(PcResolvedPlayback playback) async {
    if (_disposed) return;
    if (!isInitialized) await init();
    final player = _engine.player;
    if (_disposed || player == null) return;

    _engine.attach(this);
    _engine.lastLibmpvError = null;
    onStateChanged('buffering');

    final normalizedClearKeys = <String, String>{};
    playback.clearKeys.forEach((k, v) {
      final hexK = _toHexKey(k);
      final hexV = _toHexKey(v);
      if (hexK.isNotEmpty && hexV.isNotEmpty) {
        normalizedClearKeys[hexK] = hexV;
      }
    });
    PcTraceLog.write('mpv: play keys=${normalizedClearKeys.length}');

    final sid = _server.registerSession(
      PcProxySession(
        streamUrl: playback.streamUrl,
        headers: playback.headers,
        drmLicenseUrl: playback.drmLicenseUrl,
        drmHeaders: playback.drmHeaders,
        clearKeys: normalizedClearKeys,
        decryptMode: true,
      ),
    );

    final targetUrl = _server.toHlsProxyUrl(sid, playback.streamUrl);
    PcTraceLog.write('mpv: player.open($targetUrl)');
    try {
      await player.open(Media(targetUrl), play: true);
      PcTraceLog.write('mpv: player.open completed');
      if (!_disposed) {
        await player.setVolume(_muted ? 0.0 : (_volume * 100.0)).catchError((_) {});
      }
    } catch (e) {
      PcTraceLog.write('mpv: player.open threw $e');
      if (!_disposed) {
        onError('HEVC playback failed: $e');
      }
    }
  }

  Future<void> setPaused(bool paused) async {
    final p = _engine.player;
    if (_disposed || p == null) return;
    if (paused) {
      await p.pause().catchError((_) {});
    } else {
      await p.play().catchError((_) {});
    }
  }

  void setResizeMode(String mode) {
    _resizeMode = mode;
    if (!_disposed) onViewReady();
  }

  Future<void> setVolume(double volume, {bool? muted}) async {
    _volume = volume.clamp(0.0, 1.0);
    if (muted != null) _muted = muted;
    final p = _engine.player;
    if (_disposed || p == null) return;
    await p.setVolume(_muted ? 0.0 : (_volume * 100.0)).catchError((_) {});
  }

  Future<void> selectVideoVariant(int id) async {
    final p = _engine.player;
    if (_disposed || p == null) return;
    if (id < 0) {
      await p.setVideoTrack(VideoTrack.auto()).catchError((_) {});
      return;
    }
    if (id >= 0 && id < _lastVideoTracks.length) {
      await p.setVideoTrack(_lastVideoTracks[id]).catchError((_) {});
    }
  }

  Future<void> selectAudioTrack(String language, String role) async {
    final p = _engine.player;
    if (_disposed || p == null) return;
    for (final t in _lastAudioTracks) {
      if ((role.isNotEmpty && t.id == role) ||
          (language.isNotEmpty && (t.language ?? '').toLowerCase() == language.toLowerCase())) {
        await p.setAudioTrack(t).catchError((_) {});
        return;
      }
    }
  }

  Future<void> stop() async {
    final p = _engine.player;
    if (p == null) return;
    await p.stop().catchError((_) {});
  }

  Widget buildView() {
    final controller = _engine.videoController;
    if (!_initialized || !_engine.isReady || controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    final fit = _resizeMode == 'fit'
        ? BoxFit.contain
        : _resizeMode == 'zoom'
            ? BoxFit.cover
            : BoxFit.fill;
    return IgnorePointer(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        fit: fit,
        fill: Colors.black,
      ),
    );
  }

  static String _toHexKey(String input) {
    final clean = input.trim();
    final noDash = clean.replaceAll('-', '');
    if (noDash.length == 32 && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(noDash)) {
      return noDash.toLowerCase();
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
      return noDash.toLowerCase();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _engine.detach(this);
    await stop();
  }
}
