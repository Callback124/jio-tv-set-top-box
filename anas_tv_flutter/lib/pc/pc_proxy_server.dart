import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PcProxySession {
  final String streamUrl;
  final Map<String, String> headers;
  final String drmLicenseUrl;
  final Map<String, String> drmHeaders;
  final Map<String, String> clearKeys;
  Uri? lastManifestOrigin;

  PcProxySession({
    required this.streamUrl,
    required this.headers,
    required this.drmLicenseUrl,
    required this.drmHeaders,
    this.clearKeys = const {},
  });
}

class PcLocalPlayerServer {
  PcLocalPlayerServer._();
  static final PcLocalPlayerServer instance = PcLocalPlayerServer._();
  factory PcLocalPlayerServer() => instance;

  HttpServer? _server;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..badCertificateCallback = (_, __, ___) => true;

  final Map<int, PcProxySession> _sessions = {};
  int _nextSid = 1;
  int? _latestSid;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';
  String get playerPageUrl => 'http://127.0.0.1:$port/player.html';

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> stop() async {
    // Keep singleton loopback server alive for the app session so WebView2's
    // --unsafely-treat-insecure-origin-as-secure origin stays valid across screens.
    _sessions.clear();
  }

  int registerSession(PcProxySession session) {
    final sid = _nextSid++;
    _sessions[sid] = session;
    _latestSid = sid;
    if (_sessions.length > 20) {
      final oldestKey = _sessions.keys.first;
      if (oldestKey != sid) _sessions.remove(oldestKey);
    }
    return sid;
  }

  String toProxyUrl(int sid, String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return rawUrl;
    }
    final cleanPath = uri.path.isEmpty ? '/' : (uri.path.startsWith('/') ? uri.path : '/${uri.path}');
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return 'http://127.0.0.1:$port/p/$sid/${uri.scheme}/${uri.authority}$cleanPath$query';
  }

  String toDrmProxyUrl(int sid, String licenseUrl) {
    return 'http://127.0.0.1:$port/drm/$sid?url=${Uri.encodeQueryComponent(licenseUrl)}';
  }

  void _applyCors(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers.set('Access-Control-Expose-Headers', '*');
  }

  Future<void> _handleRequest(HttpRequest req) async {
    _applyCors(req.response);
    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return;
    }

    final path = req.uri.path;
    if (path == '/player.html') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.headers.set('Cache-Control', 'no-store');
      req.response.write(_playerHtml);
      await req.response.close();
      return;
    }

    if (path.startsWith('/drm/')) {
      await _handleDrmProxy(req);
      return;
    }

    if (path.startsWith('/p/')) {
      await _handleStreamProxy(req);
      return;
    }

    final latest = _latestSid != null ? _sessions[_latestSid] : null;
    if (latest != null && latest.lastManifestOrigin != null) {
      final fallbackUri = latest.lastManifestOrigin!.resolve(
        '${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}',
      );
      await _forwardStream(req, _latestSid!, latest, fallbackUri);
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  Future<void> _handleStreamProxy(HttpRequest req) async {
    // Format: /p/<sid>/<scheme>/<authority>/<restPath>
    final segments = req.uri.pathSegments;
    if (segments.length < 4) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final sid = int.tryParse(segments[1]);
    final scheme = segments[2].toLowerCase();
    final authority = segments[3];
    if (sid == null || (scheme != 'http' && scheme != 'https') || authority.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final session = _sessions[sid];
    if (session == null) {
      req.response.statusCode = HttpStatus.gone;
      await req.response.close();
      return;
    }

    final restSegments = segments.sublist(4);
    final trailingSlash = req.uri.path.endsWith('/') && restSegments.isNotEmpty ? '/' : '';
    final restPath = '/${restSegments.join('/')}$trailingSlash';
    final query = req.uri.hasQuery ? '?${req.uri.query}' : '';
    final upstreamUri = Uri.parse('$scheme://$authority$restPath$query');
    session.lastManifestOrigin = Uri.parse('$scheme://$authority');

    await _forwardStream(req, sid, session, upstreamUri);
  }

  Future<void> _forwardStream(
    HttpRequest req,
    int sid,
    PcProxySession session,
    Uri upstreamUri,
  ) async {
    try {
      final outReq = await _httpClient.openUrl(req.method, upstreamUri);
      outReq.followRedirects = false;

      session.headers.forEach((k, v) {
        if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
          outReq.headers.set(k, v);
        }
      });

      final range = req.headers.value('range');
      if (range != null && range.isNotEmpty) {
        outReq.headers.set('Range', range);
      }

      if (req.method == 'POST') {
        final bodyBytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
        if (bodyBytes.isNotEmpty) outReq.add(bodyBytes);
      }

      final upRes = await outReq.close();

      if (upRes.statusCode >= 300 && upRes.statusCode < 400) {
        final loc = upRes.headers.value(HttpHeaders.locationHeader);
        if (loc != null && loc.isNotEmpty) {
          await upRes.drain<void>();
          final resolved = upstreamUri.resolve(loc);
          req.response.statusCode = upRes.statusCode;
          req.response.headers.set(HttpHeaders.locationHeader, toProxyUrl(sid, resolved.toString()));
          await req.response.close();
          return;
        }
      }

      req.response.statusCode = upRes.statusCode;
      final contentType = upRes.headers.value(HttpHeaders.contentTypeHeader);
      if (contentType != null && contentType.isNotEmpty) {
        req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      final acceptRanges = upRes.headers.value('accept-ranges');
      if (acceptRanges != null) {
        req.response.headers.set('Accept-Ranges', acceptRanges);
      }
      final contentRange = upRes.headers.value('content-range');
      if (contentRange != null) {
        req.response.headers.set('Content-Range', contentRange);
      }
      req.response.headers.set('Cache-Control', 'no-store');

      final lowerPath = upstreamUri.path.toLowerCase();
      final lowerCt = (contentType ?? '').toLowerCase();
      final isMpdRequest = req.method == 'GET' &&
          upRes.statusCode == HttpStatus.ok &&
          (lowerPath.contains('.mpd') || lowerCt.contains('dash+xml'));

      if (isMpdRequest) {
        final rawBytes = await upRes.fold<List<int>>([], (a, b) => a..addAll(b));
        final rawXml = utf8.decode(rawBytes, allowMalformed: true);
        if (rawXml.contains('<MPD')) {
          final normalizedXml = _normalizeMpdForPc(rawXml, session.clearKeys);
          final outBytes = utf8.encode(normalizedXml);
          req.response.headers.contentType = ContentType('application', 'dash+xml', charset: 'utf-8');
          req.response.contentLength = outBytes.length;
          req.response.add(outBytes);
          await req.response.close();
          return;
        }
        req.response.contentLength = rawBytes.length;
        req.response.add(rawBytes);
        await req.response.close();
        return;
      }

      await upRes.pipe(req.response);
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.write('Proxy fetch error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }

  static String _formatUuid(String hex) {
    final c = hex.replaceAll('-', '').trim().toLowerCase();
    if (c.length != 32) return c;
    return '${c.substring(0, 8)}-${c.substring(8, 12)}-${c.substring(12, 16)}-${c.substring(16, 20)}-${c.substring(20)}';
  }

  static String _normalizeMpdForPc(String xml, Map<String, String> clearKeys) {
    var out = xml;

    // 1. Prune HEVC representations when H.264 (avc1) exists so WebView2 EME
    // does not fail with 6001 on systems missing Microsoft HEVC Video Extensions.
    if (out.contains('avc1.') && (out.contains('hev1.') || out.contains('hvc1.'))) {
      final prunedHevc = out
          .replaceAll(
            RegExp(r'<Representation\b[^>]*\bcodecs="[^"]*(?:hev1|hvc1)[^"]*"[^>]*>[\s\S]*?</Representation>'),
            '',
          )
          .replaceAll(
            RegExp(r'<Representation\b[^>]*\bcodecs="[^"]*(?:hev1|hvc1)[^"]*"[^>]*/>'),
            '',
          );
      if (prunedHevc.contains('<Representation')) {
        out = prunedHevc;
      }
    }

    // 2. Prune Dolby (ec-3/ac-3/ac-4) audio when AAC (mp4a) exists.
    if (out.contains('mp4a.') &&
        (out.contains('ec-3') || out.contains('ac-3') || out.contains('ac-4'))) {
      final prunedDolby = out
          .replaceAll(
            RegExp(r'<AdaptationSet\b[^>]*\bcodecs="[^"]*(?:ec-3|ac-3|ac-4)[^"]*"[^>]*>[\s\S]*?</AdaptationSet>'),
            '',
          )
          .replaceAll(
            RegExp(r'<Representation\b[^>]*\bcodecs="[^"]*(?:ec-3|ac-3|ac-4)[^"]*"[^>]*>[\s\S]*?</Representation>'),
            '',
          )
          .replaceAll(
            RegExp(r'<Representation\b[^>]*\bcodecs="[^"]*(?:ec-3|ac-3|ac-4)[^"]*"[^>]*/>'),
            '',
          );
      if (prunedDolby.contains('<AdaptationSet') && prunedDolby.contains('<Representation')) {
        out = prunedDolby;
      }
    }

    // 3. When static ClearKeys are provided, strip Widevine/PlayReady/FairPlay/Marlin
    // ContentProtection blocks that trigger Shaka 6001 in WebView2, keep cenc mp4protection
    // with default_KID, and explicitly declare ClearKey (e2719d58-a985-b3c9-781a-b030af78d30e).
    if (clearKeys.isNotEmpty) {
      final kidMatch = RegExp(
        r'''(?:cenc:)?default_KID=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(out);
      final fallbackKid = kidMatch != null
          ? kidMatch.group(1)!
          : _formatUuid(clearKeys.keys.first);

      const proprietaryUuids =
          '(?:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed|9a04f079-9840-4286-ab92-e65be0885f95|94ce86fb-07ff-4f43-adb8-93d2fa968ca2|5e629af5-38da-4063-8977-97ffbd9902d4)';

      out = out.replaceAll(
        RegExp(
          '<ContentProtection\\b[^>]*schemeIdUri=["\']urn:uuid:$proprietaryUuids["\'][^>]*>[\\s\\S]*?</ContentProtection>',
          caseSensitive: false,
        ),
        '',
      );
      out = out.replaceAll(
        RegExp(
          '<ContentProtection\\b[^>]*schemeIdUri=["\']urn:uuid:$proprietaryUuids["\'][^>]*/>',
          caseSensitive: false,
        ),
        '',
      );

      final hasClearKeyCp = out.toLowerCase().contains('e2719d58-a985-b3c9-781a-b030af78d30e');
      if (!hasClearKeyCp) {
        if (!out.contains('xmlns:cenc=')) {
          out = out.replaceFirst(
            RegExp(r'<MPD\b'),
            '<MPD xmlns:cenc="urn:mpeg:cenc:2013"',
          );
        }

        final mp4ProtRegex = RegExp(
          '<ContentProtection\\b[^>]*schemeIdUri=["\']urn:mpeg:dash:mp4protection:2011["\'][^>]*(?:/>|>[\\s\\S]*?</ContentProtection>)',
          caseSensitive: false,
        );

        if (mp4ProtRegex.hasMatch(out)) {
          out = out.replaceAllMapped(mp4ProtRegex, (m) {
            var tag = m.group(0)!;
            if (!tag.toLowerCase().contains('default_kid') && fallbackKid.isNotEmpty) {
              tag = tag.replaceFirst(
                RegExp(r'<ContentProtection\b'),
                '<ContentProtection cenc:default_KID="$fallbackKid"',
              );
            }
            return '$tag\n      <ContentProtection schemeIdUri="urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e" value="ClearKey1.0"/>';
          });
        } else if (fallbackKid.isNotEmpty) {
          out = out.replaceAllMapped(
            RegExp(r'<AdaptationSet\b[^>]*>'),
            (m) =>
                '${m.group(0)}\n      <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc" cenc:default_KID="$fallbackKid"/>\n      <ContentProtection schemeIdUri="urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e" value="ClearKey1.0"/>',
          );
        }
      }
    }

    return out;
  }

  Future<void> _handleDrmProxy(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    final sid = segments.length >= 2 ? int.tryParse(segments[1]) : null;
    final target = req.uri.queryParameters['url'] ?? '';
    final upstreamUri = Uri.tryParse(target);
    final session = sid != null ? _sessions[sid] : null;
    if (session == null || upstreamUri == null || !upstreamUri.hasScheme) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }

    try {
      final outReq = await _httpClient.openUrl(req.method, upstreamUri);
      outReq.followRedirects = true;

      session.headers.forEach((k, v) {
        if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
          outReq.headers.set(k, v);
        }
      });
      session.drmHeaders.forEach((k, v) {
        if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
          outReq.headers.set(k, v);
        }
      });

      final ct = req.headers.value(HttpHeaders.contentTypeHeader);
      if (ct != null && ct.isNotEmpty) {
        outReq.headers.set(HttpHeaders.contentTypeHeader, ct);
      }

      final bodyBytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      if (bodyBytes.isNotEmpty) {
        outReq.add(bodyBytes);
      }

      final upRes = await outReq.close();
      req.response.statusCode = upRes.statusCode;
      final resCt = upRes.headers.value(HttpHeaders.contentTypeHeader);
      if (resCt != null && resCt.isNotEmpty) {
        req.response.headers.set(HttpHeaders.contentTypeHeader, resCt);
      }
      await upRes.pipe(req.response);
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.write('DRM proxy error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }
}

const String _playerHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AnasTV Shaka Player</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #000000;
      user-select: none;
    }
    #video {
      width: 100%;
      height: 100%;
      display: block;
      background: #000000;
      object-fit: fill;
    }
  </style>
</head>
<body>
  <video id="video" autoplay playsinline></video>
  <script>
    (function() {
      var video = document.getElementById('video');
      var player = null;
      var shakaReady = false;
      var currentSid = null;
      var proxyOrigin = window.location.origin;
      var userSelectedVideoTrack = false;
      var activeLoadToken = 0;

      function postToDart(payload) {
        try {
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(JSON.stringify(payload));
          }
        } catch (e) {}
      }

      function loadScriptSequential(urls, idx, onOk, onErr) {
        if (idx >= urls.length) {
          onErr(new Error('Failed to load script: ' + urls[0]));
          return;
        }
        var s = document.createElement('script');
        s.src = urls[idx];
        s.async = false;
        s.onload = onOk;
        s.onerror = function() {
          loadScriptSequential(urls, idx + 1, onOk, onErr);
        };
        document.head.appendChild(s);
      }

      async function probeEmeSupport() {
        var cfg = [{
          initDataTypes: ['cenc'],
          videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.4d401f"' }],
          audioCapabilities: [{ contentType: 'audio/mp4; codecs="mp4a.40.2"' }]
        }];
        async function testKeySystem(ks) {
          if (!navigator.requestMediaKeySystemAccess) return 'no-api';
          try {
            await navigator.requestMediaKeySystemAccess(ks, cfg);
            return 'ok';
          } catch (err) {
            return (err && err.name ? err.name : 'fail');
          }
        }
        var results = await Promise.all([
          testKeySystem('org.w3.clearkey'),
          testKeySystem('com.widevine.alpha'),
          testKeySystem('com.microsoft.playready')
        ]);
        return 'ctx=' + (window.isSecureContext ? 'secure' : 'insecure') +
               ', clearKey=' + results[0] +
               ', widevine=' + results[1] +
               ', playready=' + results[2];
      }

      function emitTracks() {
        if (!player) return;
        try {
          var variants = player.getVariantTracks() || [];
          var seenVideo = new Set();
          var videos = [];
          variants.forEach(function(v) {
            var h = v.height || 0;
            var kbps = v.bandwidth ? Math.round(v.bandwidth / 1000) : 0;
            var label = h >= 2160 ? ('4K (' + h + 'p)') :
                        h >= 1080 ? '1080p HD' :
                        h > 0 ? (h + 'p') :
                        kbps > 0 ? (kbps + ' kbps') : ('Stream ' + v.id);
            if (!seenVideo.has(label)) {
              seenVideo.add(label);
              videos.push({
                id: v.id,
                label: label,
                height: h,
                bitrate: kbps,
                selected: !!v.active
              });
            }
          });
          videos.sort(function(a, b) {
            if (b.height !== a.height) return b.height - a.height;
            return b.bitrate - a.bitrate;
          });
          if (videos.length === 0) {
            videos.push({ id: -1, label: 'Highest (Default)', height: 0, bitrate: 0, selected: true });
          }

          var audios = [];
          var langRoles = player.getAudioLanguagesAndRoles ? player.getAudioLanguagesAndRoles() : [];
          var activeAudio = variants.find(function(v) { return v.active; });
          langRoles.forEach(function(lr, i) {
            var lang = (lr.language || '').trim();
            var role = (lr.role || '').trim();
            var label = lang && lang !== 'und' ? lang.toUpperCase() : ('Audio ' + (i + 1));
            if (role) label += ' • ' + role;
            var selected = activeAudio ? (activeAudio.language === lr.language && (activeAudio.audioRoles || []).indexOf(role) >= 0 || (!role && activeAudio.language === lr.language)) : (i === 0);
            audios.push({
              index: i,
              language: lang,
              role: role,
              label: label,
              selected: !!selected
            });
          });

          postToDart({ type: 'tracks', videos: videos, audios: audios });
        } catch (e) {}
      }

      function selectHighestVideoTrack() {
        if (!player || userSelectedVideoTrack) return;
        try {
          var variants = player.getVariantTracks() || [];
          if (!variants.length) return;
          var sorted = variants.slice().sort(function(a, b) {
            var ha = a.height || 0, hb = b.height || 0;
            if (hb !== ha) return hb - ha;
            return (b.bandwidth || 0) - (a.bandwidth || 0);
          });
          var best = sorted[0];
          if (best && !best.active) {
            player.configure({ abr: { enabled: false } });
            player.selectVariantTrack(best, true);
          } else {
            player.configure({ abr: { enabled: false } });
          }
        } catch (e) {}
      }

      async function bootShaka() {
        try {
          shaka.polyfill.installAll();
          if (!shaka.Player.isBrowserSupported()) {
            postToDart({ type: 'error', message: 'Shaka Player: Browser MSE/EME supported nahi hai.' });
            return;
          }
          player = new shaka.Player();
          await player.attach(video);

          player.getNetworkingEngine().registerRequestFilter(function(type, request) {
            if (!currentSid || !proxyOrigin) return;
            request.uris = request.uris.map(function(uri) {
              if (!uri) return uri;
              if (uri.startsWith(proxyOrigin + '/p/') || uri.startsWith(proxyOrigin + '/drm/')) {
                return uri;
              }
              if (uri.startsWith('http://') || uri.startsWith('https://')) {
                if (typeof shaka !== 'undefined' &&
                    shaka.net &&
                    shaka.net.NetworkingEngine &&
                    type === shaka.net.NetworkingEngine.RequestType.LICENSE) {
                  return proxyOrigin + '/drm/' + currentSid + '?url=' + encodeURIComponent(uri);
                }
                try {
                  var u = new URL(uri);
                  return proxyOrigin + '/p/' + currentSid + '/' + u.protocol.replace(':', '') + '/' + u.host + u.pathname + u.search;
                } catch (e) {
                  return uri;
                }
              }
              return uri;
            });
          });

          player.addEventListener('buffering', function(ev) {
            postToDart({ type: 'state', state: ev.buffering ? 'buffering' : 'ready' });
          });

          player.addEventListener('trackschanged', function() {
            selectHighestVideoTrack();
            emitTracks();
          });

          player.addEventListener('variantchanged', function() {
            emitTracks();
          });

          player.addEventListener('error', function(event) {
            var err = event && event.detail ? event.detail : event;
            var code = err && err.code ? err.code : '';
            if (code === 7000) return; // LOAD_INTERRUPTED during fast channel change
            var msg = (err && err.message) ? err.message : ('Shaka Error ' + code);
            postToDart({ type: 'error', message: 'Shaka Player (' + code + '): ' + msg });
          });

          video.addEventListener('playing', function() {
            postToDart({ type: 'state', state: 'ready' });
          });
          video.addEventListener('waiting', function() {
            postToDart({ type: 'state', state: 'buffering' });
          });
          video.addEventListener('ended', function() {
            postToDart({ type: 'state', state: 'ended' });
          });

          shakaReady = true;
          postToDart({ type: 'engineReady' });
        } catch (e) {
          postToDart({ type: 'error', message: 'Shaka init failed: ' + (e && e.message ? e.message : e) });
        }
      }

      window.anasLoadStream = async function(cfg) {
        var token = ++activeLoadToken;
        if (!shakaReady || !player) {
          postToDart({ type: 'error', message: 'Shaka Player abhi load ho raha hai, retry karein.' });
          return;
        }
        try {
          currentSid = cfg.sid;
          userSelectedVideoTrack = false;
          postToDart({ type: 'state', state: 'buffering' });
          try { await player.unload(); } catch (_) {}
          try { player.resetConfiguration(); } catch (_) {}
          if (token !== activeLoadToken) return;

          var clearKeysObj = (cfg.clearKeys && Object.keys(cfg.clearKeys).length > 0) ? cfg.clearKeys : null;
          var configObj = {
            abr: { enabled: true },
            streaming: {
              bufferingGoal: 12,
              rebufferingGoal: 2,
              bufferBehind: 15,
              ignoreTextStreamFailures: true,
              retryParameters: {
                timeout: 15000,
                maxAttempts: 4,
                baseDelay: 500,
                backoffFactor: 1.5,
                fuzzFactor: 0.3
              }
            }
          };

          if (clearKeysObj) {
            configObj.drm = {
              clearKeys: clearKeysObj,
              preferredKeySystems: ['org.w3.clearkey'],
              keySystemsMapping: {
                'urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e': 'org.w3.clearkey'
              }
            };
          } else if (cfg.drmProxyUrl) {
            configObj.drm = {
              servers: {
                'com.widevine.alpha': cfg.drmProxyUrl,
                'com.microsoft.playready': cfg.drmProxyUrl
              },
              preferredKeySystems: [
                'com.widevine.alpha',
                'com.microsoft.playready'
              ],
              advanced: {
                'com.widevine.alpha': {
                  videoRobustness: ['SW_SECURE_CRYPTO', ''],
                  audioRobustness: ['SW_SECURE_CRYPTO', ''],
                  distinctiveIdentifierRequired: false,
                  persistentStateRequired: false
                }
              }
            };
          }

          player.configure(configObj);

          await player.load(cfg.proxiedUrl, null, cfg.mimeType || undefined);
          if (token !== activeLoadToken) return;
          selectHighestVideoTrack();
          emitTracks();
          try { await video.play(); } catch (_) {}
          postToDart({ type: 'state', state: 'ready' });
        } catch (e) {
          if (token !== activeLoadToken) return;
          if (e && e.code === 7000) return;
          var code = e && e.code ? (' (' + e.code + ')') : '';
          var baseMsg = (e && e.message) ? e.message : String(e);
          if (e && e.code === 6001) {
            var diag = await probeEmeSupport();
            var keyCount = cfg.clearKeys ? Object.keys(cfg.clearKeys).length : 0;
            baseMsg += ' [' + diag + ', keys=' + keyCount + ']';
          }
          postToDart({
            type: 'error',
            message: 'Playback failed' + code + ': ' + baseMsg
          });
        }
      };

      window.anasSetPaused = function(paused) {
        if (paused) {
          video.pause();
        } else {
          video.play().catch(function() {});
        }
      };

      window.anasSetAspect = function(mode) {
        video.style.objectFit = mode === 'fit' ? 'contain' : (mode === 'zoom' ? 'cover' : 'fill');
      };

      window.anasSetVolume = function(vol, muted) {
        video.muted = !!muted;
        if (typeof vol === 'number') {
          video.volume = Math.max(0, Math.min(1, vol));
        }
      };

      window.anasSelectVideoVariant = function(trackId) {
        if (!player) return;
        if (trackId < 0) {
          userSelectedVideoTrack = false;
          selectHighestVideoTrack();
          emitTracks();
          return;
        }
        var variants = player.getVariantTracks() || [];
        var target = variants.find(function(v) { return v.id === trackId; });
        if (target) {
          userSelectedVideoTrack = true;
          player.configure({ abr: { enabled: false } });
          player.selectVariantTrack(target, true);
          emitTracks();
        }
      };

      window.anasSelectAudioTrack = function(lang, role) {
        if (!player) return;
        try {
          player.selectAudioLanguage(lang, role || '');
          setTimeout(emitTracks, 150);
        } catch (e) {}
      };

      window.anasStop = function() {
        activeLoadToken++;
        if (player) {
          try { player.unload(); } catch (_) {}
        }
      };

      loadScriptSequential(
        [
          'https://cdn.jsdelivr.net/npm/mux.js@7/dist/mux.min.js',
          'https://unpkg.com/mux.js@7/dist/mux.min.js'
        ],
        0,
        function() {
          loadScriptSequential(
            [
              'https://cdn.jsdelivr.net/npm/shaka-player@4.12.6/dist/shaka-player.compiled.js',
              'https://unpkg.com/shaka-player@4.12.6/dist/shaka-player.compiled.js',
              'https://cdn.jsdelivr.net/npm/shaka-player@4/dist/shaka-player.compiled.js'
            ],
            0,
            bootShaka,
            function(err) {
              postToDart({ type: 'error', message: 'Shaka Player JS load nahi hua: ' + err.message });
            }
          );
        },
        function() {
          loadScriptSequential(
            [
              'https://cdn.jsdelivr.net/npm/shaka-player@4.12.6/dist/shaka-player.compiled.js',
              'https://unpkg.com/shaka-player@4.12.6/dist/shaka-player.compiled.js',
              'https://cdn.jsdelivr.net/npm/shaka-player@4/dist/shaka-player.compiled.js'
            ],
            0,
            bootShaka,
            function(err) {
              postToDart({ type: 'error', message: 'Shaka Player JS load nahi hua: ' + err.message });
            }
          );
        }
      );
    })();
  </script>
</body>
</html>
''';

