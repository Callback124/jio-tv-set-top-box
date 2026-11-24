import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

class PcChannel {
  final int id, categoryId, languageId, order, channelNumber;
  final String name, logo, fallbackLogo, category, language;
  final bool hd;
  final int? epgChannelId;
  final String? epgChannelName;
  final Map<String, dynamic>? raw;

  const PcChannel({
    required this.id,
    required this.name,
    required this.logo,
    required this.fallbackLogo,
    required this.categoryId,
    required this.category,
    required this.languageId,
    required this.language,
    required this.hd,
    required this.order,
    this.channelNumber = 0,
    this.epgChannelId,
    this.epgChannelName,
    this.raw,
  });

  PcChannel copyWith({
    int? channelNumber,
    String? logo,
    String? fallbackLogo,
    int? epgChannelId,
    String? epgChannelName,
  }) {
    return PcChannel(
      id: id,
      name: name,
      logo: logo ?? this.logo,
      fallbackLogo: fallbackLogo ?? this.fallbackLogo,
      categoryId: categoryId,
      category: category,
      languageId: languageId,
      language: language,
      hd: hd,
      order: order,
      channelNumber: channelNumber ?? this.channelNumber,
      epgChannelId: epgChannelId ?? this.epgChannelId,
      epgChannelName: epgChannelName ?? this.epgChannelName,
      raw: raw,
    );
  }
}

class PcProgram {
  final int startMs;
  final String title;
  final String timeLabel;
  final String description;
  final String posterUrl;
  final String fallbackPosterUrl;
  final double progress;
  final bool isLiveNow;

  const PcProgram({
    required this.startMs,
    required this.title,
    required this.timeLabel,
    required this.description,
    required this.posterUrl,
    required this.fallbackPosterUrl,
    required this.progress,
    required this.isLiveNow,
  });
}

class PcChannelMatcher {
  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]+');
  static final RegExp _multiSpace = RegExp(r'\s+');
  static final RegExp _bracketed = RegExp(r'[\(\[\{].*?[\)\]\}]');
  static final RegExp _sonySportsTen = RegExp(r'\bsony\s+sports?\s+ten\b');
  static final RegExp _sonySportsNum = RegExp(r'\bsony\s+sports?\s+(?=[1-5]\b)');
  static final RegExp _sonyEnt = RegExp(r'\bsony\s+entertainment\s+television\b');
  static final RegExp _joinedDigits = RegExp(r'\b(ten|max|sports|sab|wah|mix|pal|pix)(\d+)\b');

  static String exactKey(String name) {
    var s = name.toLowerCase().replaceAll('&', ' and ');
    s = s.replaceAll(_bracketed, ' ');
    s = s.replaceAll(_nonAlnum, ' ').replaceAll(_multiSpace, ' ').trim();
    s = s.replaceAllMapped(_joinedDigits, (m) => '${m[1]} ${m[2]}');
    s = s.replaceAll(_sonySportsTen, 'sony ten');
    s = s.replaceAll(_sonySportsNum, 'sony ten ');
    s = s.replaceAll(_sonyEnt, 'set');
    if (s == 'sab tv' || s == 'sab') {
      s = 'sony sab';
    } else if (s.startsWith('sab tv ')) {
      s = s.replaceFirst('sab tv ', 'sony sab ');
    } else if (s.startsWith('sab ')) {
      s = s.replaceFirst('sab ', 'sony sab ');
    }
    return s.replaceAll(_multiSpace, ' ').trim();
  }

  static String sdEquivKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'sd' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String langNeutralSdKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'hindi' &&
        t != 'sd' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String baseKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'sd' &&
        t != 'hd' &&
        t != 'fhd' &&
        t != 'uhd' &&
        t != '4k' &&
        t != '1080p' &&
        t != '720p' &&
        t != 'hevc' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String langNeutralBaseKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'hindi' &&
        t != 'sd' &&
        t != 'hd' &&
        t != 'fhd' &&
        t != 'uhd' &&
        t != '4k' &&
        t != '1080p' &&
        t != '720p' &&
        t != 'hevc' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }
}

Map<String, String> pcImageHeadersFor(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.contains('jio.com')) {
    return const {'User-Agent': PcStreamResolver.defaultUa};
  }
  if (host.contains('wikia.nocookie.net')) {
    return const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': 'https://logos.fandom.com/',
    };
  }
  return const {
    'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 13; Android TV Build/TQ3A.230805.001)',
    'Accept': '*/*',
  };
}

int? pcResolveChannelIndexByNumber(List<PcChannel> channels, int number) {
  if (channels.isEmpty || number < 1) return null;
  final exactIdx = channels.indexWhere((c) => c.channelNumber == number);
  if (exactIdx >= 0) return exactIdx;
  if (number < 101) {
    final offsetIdx = channels.indexWhere((c) => c.channelNumber == 100 + number);
    if (offsetIdx >= 0) return offsetIdx;
  }
  if (channels.every((c) => c.channelNumber <= 0)) {
    if (number >= 101) {
      final idx = number - 101;
      return (idx >= 0 && idx < channels.length) ? idx : null;
    }
    final idx = number - 1;
    return (idx >= 0 && idx < channels.length) ? idx : null;
  }
  return null;
}

class PcResolvedPlayback {
  final String streamUrl;
  final Map<String, String> headers;
  final String drmLicenseUrl;
  final Map<String, String> drmHeaders;
  final Map<String, String> clearKeys;

  const PcResolvedPlayback({
    required this.streamUrl,
    required this.headers,
    required this.drmLicenseUrl,
    required this.drmHeaders,
    required this.clearKeys,
  });
}

class PcStreamResolver {
  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';

  static Future<PcResolvedPlayback> resolve(PcChannel channel) async {
    final raw = channel.raw ?? <String, dynamic>{};
    final rawChannelId = (raw['channel_id'] ?? raw['channelId'] ?? channel.id).toString().trim();
    final requestHeaders = <String, String>{
      'User-Agent': (raw['user_agent'] ?? raw['userAgent'] ?? defaultUa).toString(),
      'Accept': '*/*',
    };
    final drmHeaders = <String, String>{};
    final referer = (raw['referer'] ?? raw['referrer'] ?? '').toString().trim();
    final origin = (raw['origin'] ?? '').toString().trim();
    final cookie = (raw['cookie'] ?? '').toString().trim();
    if (referer.isNotEmpty) requestHeaders['Referer'] = referer;
    if (origin.isNotEmpty) requestHeaders['Origin'] = origin;
    if (cookie.isNotEmpty) requestHeaders['Cookie'] = cookie;

    String firstValue(List<String> keys) {
      for (final key in keys) {
        final value = (raw[key] ?? '').toString().trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    bool isHttp(String value) => value.startsWith('https://') || value.startsWith('http://');

    final direct = firstValue([
      'ready_to_use_link',
      'url',
      'stream_url',
      'm3u8_url',
      'mpd_url',
      'play_url',
      'playUrl',
      'channel_url',
    ]);

    String? streamUrl;
    String drmLicenseUrl = '';
    final clearKeys = <String, String>{};

    if (channel.id < 1000000 && rawChannelId.isNotEmpty) {
      try {
        final response = await http
            .get(
              Uri.https('eliteapiyash.streamxlive.workers.dev', '/', {'id': rawChannelId}),
              headers: const {'User-Agent': defaultUa},
            )
            .timeout(const Duration(seconds: 20));
        final body = response.body.replaceFirst('\uFEFF', '').trim();
        if (response.statusCode != 200) {
          throw Exception('Resolver HTTP ${response.statusCode}');
        }
        if (body.isEmpty) throw Exception('Resolver returned an empty response.');

        dynamic decoded;
        try {
          decoded = jsonDecode(_extractJsonValue(body));
        } on FormatException {
          if (isHttp(body.split('|').first.trim())) {
            decoded = {'ready_to_use_link': body, 'status': 'success'};
          } else {
            throw Exception('Resolver JSON invalid');
          }
        }

        final Map<String, dynamic> data =
            decoded is List && decoded.isNotEmpty && decoded.first is Map
                ? Map<String, dynamic>.from(decoded.first as Map)
                : decoded is Map
                    ? Map<String, dynamic>.from(decoded as Map)
                    : <String, dynamic>{};

        if ((data['status'] ?? 'success').toString().toLowerCase() == 'error') {
          throw Exception((data['message'] ?? 'Stream resolve failed').toString());
        }

        drmLicenseUrl =
            _firstFromMap(data, ['widevine_license_url', 'drm_license_url', 'license_url']) ?? '';
        if (data['drm_headers'] is Map) {
          (data['drm_headers'] as Map).forEach((k, v) {
            final ks = k.toString().trim();
            final vs = v.toString().trim();
            if (ks.isNotEmpty && vs.isNotEmpty) drmHeaders[ks] = vs;
          });
        }

        final ready = (data['ready_to_use_link'] ?? '').toString().trim();
        if (ready.isNotEmpty) {
          final parts = ready.split('|');
          final candidate = parts.first.trim();
          if (isHttp(candidate)) streamUrl = candidate;
          for (final entry in parts.skip(1).join('&').split('&')) {
            final idx = entry.indexOf('=');
            if (idx <= 0) continue;
            final k = entry.substring(0, idx).trim().toLowerCase();
            final v = Uri.decodeComponent(entry.substring(idx + 1).trim());
            if (k == 'cookie' && v.isNotEmpty) requestHeaders['Cookie'] = v;
            if ((k == 'user-agent' || k == 'useragent') && v.isNotEmpty) {
              requestHeaders['User-Agent'] = v;
            }
            if (k == 'drmlicense' && v.isNotEmpty && !v.startsWith('http')) {
              clearKeys.addAll(_parseClearKeys(v));
            }
          }
        }

        streamUrl ??= _firstFromMap(data, ['mpd_url', 'm3u8_url', 'url', 'stream_url']);

        final responseCookie = (data['cookie'] ?? '').toString().trim();
        if (responseCookie.isNotEmpty) requestHeaders['Cookie'] = responseCookie;

        final responseUa = (data['user_agent'] ?? data['userAgent'] ?? '').toString().trim();
        if (responseUa.isNotEmpty) requestHeaders['User-Agent'] = responseUa;

        for (final field in [
          'all_keys',
          'allKeys',
          'drmLicense',
          'drm_license',
          'clearkey',
          'clearKey',
          'keys',
          'key',
          'keyId',
          'key_id',
        ]) {
          if (data[field] != null) clearKeys.addAll(_parseClearKeys(data[field]));
        }
        _extractPairedKey(data, clearKeys);
      } catch (e) {
        if (!isHttp(direct.split('|').first.trim())) {
          rethrow;
        }
      }
    }

    if (streamUrl == null && direct.isNotEmpty) {
      final parts = direct.split('|');
      final candidate = parts.first.trim();
      if (isHttp(candidate)) streamUrl = candidate;
      for (final entry in parts.skip(1).join('&').split('&')) {
        final idx = entry.indexOf('=');
        if (idx <= 0) continue;
        final k = entry.substring(0, idx).trim().toLowerCase();
        final v = Uri.decodeComponent(entry.substring(idx + 1).trim());
        if (k == 'cookie' && v.isNotEmpty) requestHeaders['Cookie'] = v;
        if ((k == 'user-agent' || k == 'useragent') && v.isNotEmpty) {
          requestHeaders['User-Agent'] = v;
        }
        if (k == 'drmlicense' && v.isNotEmpty && !v.startsWith('http')) {
          clearKeys.addAll(_parseClearKeys(v));
        }
      }
    }

    if (clearKeys.isEmpty) {
      for (final field in [
        'all_keys',
        'allKeys',
        'drmLicense',
        'drm_license',
        'clearkey',
        'clearKey',
        'keys',
        'key',
        'keyId',
        'key_id',
      ]) {
        if (raw[field] != null) clearKeys.addAll(_parseClearKeys(raw[field]));
      }
      _extractPairedKey(raw, clearKeys);
    }

    if (streamUrl == null || !isHttp(streamUrl)) {
      throw Exception('Valid stream URL nahi mila');
    }

    return PcResolvedPlayback(
      streamUrl: streamUrl,
      headers: requestHeaders,
      drmLicenseUrl: drmLicenseUrl,
      drmHeaders: drmHeaders,
      clearKeys: clearKeys,
    );
  }

  static void _extractPairedKey(Map<String, dynamic> map, Map<String, String> out) {
    final kid = (map['keyId'] ?? map['key_id'] ?? map['kid'] ?? '').toString().trim();
    final key = (map['key'] ?? map['k'] ?? '').toString().trim();
    bool isBad(String v) =>
        v.isEmpty ||
        v.toLowerCase() == 'null' ||
        v.toLowerCase() == 'none' ||
        v.toLowerCase() == 'undefined' ||
        v.contains(':') ||
        v.contains(',') ||
        v.startsWith('http');
    if (!isBad(kid) && !isBad(key)) {
      out.putIfAbsent(kid, () => key);
    }
  }

  static Map<String, String> _parseClearKeys(dynamic raw) {
    final pairs = <String, String>{};
    bool isBadToken(String s) {
      final l = s.trim().toLowerCase();
      return l.isEmpty || l == 'null' || l == 'none' || l == 'undefined';
    }

    if (raw is Map) {
      final kid = (raw['kid'] ?? raw['key_id'] ?? raw['keyId'] ?? '').toString().trim();
      final key = (raw['key'] ?? raw['k'] ?? '').toString().trim();
      if (!isBadToken(kid) && !isBadToken(key)) {
        pairs[kid] = key;
      } else {
        raw.forEach((k, v) {
          final ks = k.toString().trim(), vs = v.toString().trim();
          if (!isBadToken(ks) && !isBadToken(vs)) pairs[ks] = vs;
        });
      }
    } else if (raw is List) {
      for (final item in raw) {
        pairs.addAll(_parseClearKeys(item));
      }
    } else if (raw != null) {
      final str = raw.toString().trim();
      if (!isBadToken(str) && !str.startsWith('http')) {
        for (final seg in str.split(RegExp(r'[,;\n]'))) {
          final parts = seg.trim().split(':');
          if (parts.length == 2 && !isBadToken(parts[0]) && !isBadToken(parts[1])) {
            pairs[parts[0].trim()] = parts[1].trim();
          }
        }
      }
    }
    return pairs;
  }

  static String _extractJsonValue(String raw) {
    final text = raw.replaceFirst('\uFEFF', '').trimLeft();
    final arrayStart = text.indexOf('[');
    final objectStart = text.indexOf('{');
    int start;
    if (arrayStart < 0) {
      start = objectStart;
    } else if (objectStart < 0) {
      start = arrayStart;
    } else {
      start = arrayStart < objectStart ? arrayStart : objectStart;
    }
    if (start < 0) return text;

    final opening = text[start];
    final closing = opening == '[' ? ']' : '}';
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == opening) {
        depth++;
      } else if (ch == closing) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    throw const FormatException('Resolver JSON value is incomplete.');
  }

  static String? _firstFromMap(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.startsWith('https://') || value.startsWith('http://')) return value;
    }
    return null;
  }
}

List<Map<String, dynamic>> _parsePcEpgBatchIsolate(Map<String, dynamic> args) {
  final body = args['body'] as String;
  final nowMs = args['nowMs'] as int;
  final cutoffMs = args['cutoffMs'] as int;
  final channelName = args['channelName'] as String;

  String fmtTime(DateTime dt) {
    final h24 = dt.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h24 >= 12 ? 'PM' : 'AM';
    return '$h12:$m $p';
  }

  String weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  (String, String) buildPosterUrls(String raw) {
    final clean = raw.trim().replaceAll(r'\/', '/');
    if (clean.isEmpty || clean == 'null') return ('', '');
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return (clean, clean);
    }
    final noLead = clean.startsWith('/') ? clean.substring(1) : clean;
    final p1 = 'https://jiotvimages.cdn.jio.com/dare_images/shows/$noLead';
    final p2 = 'https://jiotvimages.cdn.jio.com/dare_images/images/$noLead';
    return (p1, p2);
  }

  try {
    final decoded = jsonDecode(body);
    final rawList = (decoded is Map && decoded['epg'] is List) ? decoded['epg'] as List : const [];
    final out = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final startMs = (item['startEpoch'] as num?)?.toInt() ?? 0;
      final endMs = (item['endEpoch'] as num?)?.toInt() ?? 0;
      if (startMs <= 0 || endMs <= startMs) continue;
      if (endMs <= nowMs) continue;
      if (startMs > cutoffMs) continue;

      final startDt = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
      final endDt = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
      final rawTitle = (item['showname'] ?? item['title'] ?? '').toString().trim();
      final rawDesc = (item['description'] ?? item['desc'] ?? '').toString().trim();
      final rawPoster = (item['episodePoster'] ?? item['episodeThumbnail'] ?? item['poster'] ?? '').toString();
      final posters = buildPosterUrls(rawPoster);
      final isLive = startMs <= nowMs && nowMs < endMs;
      final prog = isLive ? ((nowMs - startMs) / (endMs - startMs)).clamp(0.03, 0.99) : 0.0;

      out.add({
        'startMs': startMs,
        'title': rawTitle.isNotEmpty ? rawTitle : '$channelName Live',
        'timeLabel': '${weekdayShort(startDt.weekday)} : ${fmtTime(startDt)} - ${fmtTime(endDt)}',
        'description': rawDesc.isNotEmpty ? rawDesc : '$channelName live broadcast.',
        'posterUrl': posters.$1,
        'fallbackPosterUrl': posters.$2,
        'progress': prog,
        'isLiveNow': isLive,
      });
    }
    return out;
  } catch (_) {
    return const [];
  }
}

class PcEpgService {
  static const jioHeaders = {
    'User-Agent': 'okhttp/4.12.0',
    'Accept': 'application/json, text/plain, */*',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'devicetype': 'phone',
    'os': 'android',
    'osVersion': '15',
    'versionCode': '450',
  };

  static final Map<int, List<PcProgram>> _cache = {};
  static final Map<int, Set<int>> _loadedOffsets = {};
  static final Map<int, Set<int>> _emptyOffsets = {};
  static final Map<int, int> _epgDonorIdFor = {};
  static final Map<String, List<PcChannel>> _byExact = {};
  static final Map<String, List<PcChannel>> _bySdEquiv = {};
  static final Map<String, List<PcChannel>> _byLangSd = {};
  static final Map<String, List<PcChannel>> _byBase = {};
  static final Map<String, List<PcChannel>> _byLangBase = {};

  static void registerChannels(List<PcChannel> channels) {
    _epgDonorIdFor.clear();
    _byExact.clear();
    _bySdEquiv.clear();
    _byLangSd.clear();
    _byBase.clear();
    _byLangBase.clear();
    for (final ch in channels) {
      if (ch.epgChannelId != null && ch.epgChannelId! < 1000000) {
        _epgDonorIdFor[ch.id] = ch.epgChannelId!;
      }
      if (ch.id >= 1000000) continue;
      final ek = PcChannelMatcher.exactKey(ch.name);
      final sk = PcChannelMatcher.sdEquivKey(ch.name);
      final lk = PcChannelMatcher.langNeutralSdKey(ch.name);
      final bk = PcChannelMatcher.baseKey(ch.name);
      final lbk = PcChannelMatcher.langNeutralBaseKey(ch.name);
      if (ek.isNotEmpty) _byExact.putIfAbsent(ek, () => []).add(ch);
      if (sk.isNotEmpty) _bySdEquiv.putIfAbsent(sk, () => []).add(ch);
      if (lk.isNotEmpty) _byLangSd.putIfAbsent(lk, () => []).add(ch);
      if (bk.isNotEmpty) _byBase.putIfAbsent(bk, () => []).add(ch);
      if (lbk.isNotEmpty) _byLangBase.putIfAbsent(lbk, () => []).add(ch);
    }
  }

  static List<int> _candidateIdsFor(PcChannel ch) {
    final ids = <int>[];
    void addId(int? id) {
      if (id != null && id > 0 && id < 1000000 && !ids.contains(id)) {
        ids.add(id);
      }
    }

    addId(ch.id);
    addId(ch.epgChannelId);
    addId(_epgDonorIdFor[ch.id]);

    final ek = PcChannelMatcher.exactKey(ch.name);
    final sk = PcChannelMatcher.sdEquivKey(ch.name);
    final lk = PcChannelMatcher.langNeutralSdKey(ch.name);
    final bk = PcChannelMatcher.baseKey(ch.name);
    final lbk = PcChannelMatcher.langNeutralBaseKey(ch.name);
    for (final list in [
      _byExact[ek],
      _bySdEquiv[sk],
      _byLangSd[lk],
      _byBase[bk],
      _byLangBase[lbk],
    ]) {
      if (list == null) continue;
      for (final donor in list) {
        addId(donor.id);
      }
    }
    return ids;
  }

  static List<PcProgram>? cachedFor(int channelId) {
    final direct = _cache[channelId];
    if (direct != null && direct.isNotEmpty) return direct;
    final donorId = _epgDonorIdFor[channelId];
    if (donorId != null) return _cache[donorId];
    return direct;
  }

  static bool hasOffset(int channelId, int offset) =>
      _loadedOffsets[channelId]?.contains(offset) ?? false;

  static String _fmtTime(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$min $period';
  }

  static String _weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  static List<PcProgram> fallback48h(PcChannel ch) {
    final now = DateTime.now();
    final slotStartMin = now.minute < 30 ? 0 : 30;
    final firstStart = DateTime(now.year, now.month, now.day, now.hour, slotStartMin);
    final cat = ch.category.toLowerCase();

    List<(String, String)> templates;
    if (cat.contains('sport')) {
      templates = [
        ('${ch.name} Live Match & Analysis', 'Live stadium action, pitch insights, Hindi commentary aur real-time score updates.'),
        ('Post Match & Highlights Special', 'Match ke best moments, top wickets, boundaries aur expert panel analysis.'),
      ];
    } else if (cat.contains('movie')) {
      templates = [
        ('${ch.name} Blockbuster Feature Film', 'Superhit feature movie HD picture quality aur surround audio ke saath.'),
        ('Prime Cinema Showcase', 'Family entertainer blockbuster movie non-stop broadcasting ke saath.'),
      ];
    } else if (cat.contains('news')) {
      templates = [
        ('Breaking News & Live Bulletin', 'Desh aur duniya ki sabse badi khabrein aur live ground reports.'),
        ('Prime Debate & Top Headlines', 'Din bhar ki badi khabron par vishesh charcha aur tezi se updates.'),
      ];
    } else {
      templates = [
        ('${ch.name} Prime Show', '${ch.name} par dekhein popular family show aur live entertainment broadcast.'),
        ('${ch.name} Special Episode', 'Naya drama, twists aur family entertainment ka special episode.'),
      ];
    }

    final list = <PcProgram>[];
    for (var i = 0; i < 16; i++) {
      final start = firstStart.add(Duration(minutes: i * 60 - (i > 0 ? 30 : 0)));
      final end = i == 0 ? firstStart.add(const Duration(minutes: 30)) : start.add(const Duration(minutes: 60));
      final tpl = templates[i % templates.length];
      final prog = i == 0
          ? (now.difference(start).inSeconds / 1800.0).clamp(0.05, 0.96)
          : 0.0;
      list.add(PcProgram(
        startMs: start.millisecondsSinceEpoch,
        title: tpl.$1,
        timeLabel: '${_weekdayShort(start.weekday)} : ${_fmtTime(start)} - ${_fmtTime(end)}',
        description: tpl.$2,
        posterUrl: '',
        fallbackPosterUrl: '',
        progress: prog,
        isLiveNow: i == 0,
      ));
    }
    return list;
  }

  static Future<List<PcProgram>> fetchOffset(PcChannel ch, {int offset = 0}) async {
    final loaded = _loadedOffsets.putIfAbsent(ch.id, () => <int>{});
    final existing = _cache[ch.id];
    if (loaded.contains(offset) && existing != null && existing.isNotEmpty) {
      return existing;
    }

    final candidates = _candidateIdsFor(ch);
    if (candidates.isEmpty) {
      return existing ?? fallback48h(ch);
    }

    for (final cid in candidates) {
      final cidLoaded = _loadedOffsets.putIfAbsent(cid, () => <int>{});
      final cidEmpty = _emptyOffsets.putIfAbsent(cid, () => <int>{});
      final cidCache = _cache[cid];

      if (cidLoaded.contains(offset) && cidCache != null && cidCache.isNotEmpty) {
        _cache[ch.id] = cidCache;
        loaded.add(offset);
        return cidCache;
      }
      if (cidEmpty.contains(offset)) continue;

      try {
        final url = 'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get?channel_id=$cid&offset=$offset';
        final res = await http
            .get(Uri.parse(url), headers: jioHeaders)
            .timeout(const Duration(seconds: 6));

        if (res.statusCode != 200 || res.body.trim().isEmpty) {
          cidEmpty.add(offset);
          continue;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final cutoffMs = nowMs + const Duration(hours: 48).inMilliseconds;
        final parsedMaps = await compute(_parsePcEpgBatchIsolate, {
          'body': res.body,
          'nowMs': nowMs,
          'cutoffMs': cutoffMs,
          'channelName': ch.name,
        });

        if (parsedMaps.isEmpty) {
          cidEmpty.add(offset);
          continue;
        }

        final byStart = <int, PcProgram>{};
        if (cidCache != null) {
          for (final item in cidCache) {
            byStart[item.startMs] = item;
          }
        }
        if (existing != null) {
          for (final item in existing) {
            byStart[item.startMs] = item;
          }
        }
        for (final m in parsedMaps) {
          final sMs = (m['startMs'] as num?)?.toInt() ?? 0;
          if (sMs <= 0) continue;
          byStart[sMs] = PcProgram(
            startMs: sMs,
            title: (m['title'] ?? '').toString(),
            timeLabel: (m['timeLabel'] ?? '').toString(),
            description: (m['description'] ?? '').toString(),
            posterUrl: (m['posterUrl'] ?? '').toString(),
            fallbackPosterUrl: (m['fallbackPosterUrl'] ?? '').toString(),
            progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
            isLiveNow: m['isLiveNow'] == true,
          );
        }

        final merged = byStart.values.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
        if (merged.isEmpty) {
          cidEmpty.add(offset);
          continue;
        }
        _cache[cid] = merged;
        cidLoaded.add(offset);
        _cache[ch.id] = merged;
        loaded.add(offset);
        return merged;
      } catch (_) {
        continue;
      }
    }

    return existing ?? fallback48h(ch);
  }
}

class PcBrandCircularLoader extends StatelessWidget {
  final double size;

  const PcBrandCircularLoader({super.key, this.size = 76});

  @override
  Widget build(BuildContext context) {
    final innerSize = size - 14;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: innerSize * 0.86,
              height: innerSize * 0.86,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            SvgPicture.asset(
              'assets/images/jio_logo.svg',
              width: innerSize,
              height: innerSize,
              fit: BoxFit.contain,
            ),
            SizedBox(
              width: size,
              height: size,
              child: const CircularProgressIndicator(
                strokeWidth: 3.2,
                color: Color(0xFFE65312),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PcStbChannelNumberOsd extends StatelessWidget {
  final String digits;
  final String? previewChannelName;
  final String? errorMessage;

  const PcStbChannelNumberOsd({
    super.key,
    required this.digits,
    this.previewChannelName,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final text = errorMessage ?? (digits.isEmpty ? '' : digits);
    if (text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              errorMessage != null ? errorMessage! : digits,
              style: const TextStyle(
                fontFamily: 'Anton',
                color: Colors.white,
                fontSize: 32,
                height: 1.05,
                letterSpacing: 1.8,
              ),
            ),
            if (errorMessage == null && (previewChannelName ?? '').isNotEmpty) ...[
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  previewChannelName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Anton',
                    color: Color(0xFFD6DCE8),
                    fontSize: 13.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PcProgramPoster extends StatefulWidget {
  final String primaryUrl, fallbackUrl, title;
  const PcProgramPoster({
    super.key,
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.title,
  });

  @override
  State<PcProgramPoster> createState() => _PcProgramPosterState();
}

class _PcProgramPosterState extends State<PcProgramPoster> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant PcProgramPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl || oldWidget.fallbackUrl != widget.fallbackUrl) {
      _attempt = 0;
    }
  }

  List<String> get _candidates {
    final out = <String>[];
    void addUrl(String raw) {
      final clean = raw.trim();
      if (clean.isNotEmpty && !out.contains(clean)) out.add(clean);
    }

    addUrl(widget.primaryUrl);
    addUrl(widget.fallbackUrl);
    if (widget.primaryUrl.contains('jiotvimages.cdn.jio.com/')) {
      addUrl(widget.primaryUrl.replaceFirst('jiotvimages.cdn.jio.com/', 'jiotv.catchup.cdn.jio.com/'));
    }
    return out;
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171C24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.live_tv_rounded, color: Colors.white54, size: 32),
          if (widget.title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = _candidates;
    if (_attempt >= urls.length) return _placeholder();
    final url = urls[_attempt];
    return ColoredBox(
      color: Colors.white,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: pcImageHeadersFor(url),
        fit: BoxFit.fill,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 640,
        memCacheHeight: 360,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) {
          if (_attempt + 1 < urls.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _attempt++);
            });
          }
          return _placeholder();
        },
      ),
    );
  }
}

class PcChannelLogo extends StatefulWidget {
  final String primaryUrl, fallbackUrl;
  const PcChannelLogo({
    super.key,
    required this.primaryUrl,
    required this.fallbackUrl,
  });

  @override
  State<PcChannelLogo> createState() => _PcChannelLogoState();
}

class _PcChannelLogoState extends State<PcChannelLogo> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant PcChannelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl || oldWidget.fallbackUrl != widget.fallbackUrl) {
      _attempt = 0;
    }
  }

  List<String> get _candidates {
    final out = <String>[];
    void addUrl(String raw) {
      final clean = raw.trim();
      if (clean.isNotEmpty && !out.contains(clean)) out.add(clean);
    }

    addUrl(widget.primaryUrl);
    if (widget.primaryUrl.contains('://www.sonypicturesnetworks.com/')) {
      addUrl(widget.primaryUrl.replaceFirst('://www.sonypicturesnetworks.com/', '://sonypicturesnetworks.com/'));
    }
    addUrl(widget.fallbackUrl);
    if (widget.fallbackUrl.contains('jiotvimages.cdn.jio.com/')) {
      addUrl(widget.fallbackUrl.replaceFirst('jiotvimages.cdn.jio.com/', 'jiotv.catchup.cdn.jio.com/'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final urls = _candidates;
    if (_attempt >= urls.length) {
      return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Color(0xFF163842)));
    }
    final url = urls[_attempt];
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: pcImageHeadersFor(url),
      fit: BoxFit.contain,
      memCacheWidth: 160,
      memCacheHeight: 160,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorWidget: (_, __, ___) {
        if (_attempt + 1 < urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _attempt++);
          });
        }
        return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Color(0xFF163842)));
      },
    );
  }
}
