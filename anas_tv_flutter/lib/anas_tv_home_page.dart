import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AnasTvApp extends StatefulWidget {
  const AnasTvApp({super.key});
  @override
  State<AnasTvApp> createState() => _AnasTvAppState();
}

class _AnasTvAppState extends State<AnasTvApp> {
  ThemeMode mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AnasTV',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE65312)),
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE65312),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF050505),
        ),
        home: AnasTvHomePage(
          isDark: mode == ThemeMode.dark,
          onToggleTheme: () => setState(() {
            mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }),
        ),
      );
}

class TvChannel {
  final int id, categoryId, languageId, order;
  final String name, logo, fallbackLogo, category, language;
  final bool hd;
  final Map<String, dynamic>? raw;

  const TvChannel({
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
    this.raw,
  });
}

class AnasTvHomePage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const AnasTvHomePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<AnasTvHomePage> createState() => _AnasTvHomePageState();
}

class _AnasTvHomePageState extends State<AnasTvHomePage> {
  static const categories = <int, String>{
    0: 'All',
    5: 'Entertainment',
    6: 'Movies',
    8: 'Sports',
    12: 'News',
    7: 'Kids',
    13: 'Music',
    10: 'Infotainment',
    9: 'Lifestyle',
    15: 'Devotional',
    16: 'Business',
    17: 'Educational',
    18: 'Shopping',
  };

  static const languages = <int, String>{
    0: 'All Languages',
    1: 'Hindi',
    6: 'English',
    8: 'Tamil',
    11: 'Telugu',
    2: 'Marathi',
    5: 'Bengali',
    9: 'Gujarati',
    13: 'Kannada',
    7: 'Malayalam',
    3: 'Punjabi',
    10: 'Odia',
    12: 'Bhojpuri',
    4: 'Urdu',
    14: 'Assamese',
    15: 'Nepali',
  };

  static const headers = {
    'User-Agent': 'JioTV',
    'x-api-key': 'l7xx75e822925f184370b2e25170c5d5820a',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': 'application/json',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'os': 'android',
    'devicetype': 'phone',
  };

  static const extraUrl = 'https://api.npoint.io/9db02feba76eb297fc65?v=1794981838621';
  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';

  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  final List<String> _debugErrors = [];

  List<TvChannel> allChannels = [];
  bool loading = true, searchOpen = false, hdOnly = false, resolving = false;
  String? error;
  String query = '';
  int categoryId = 0, languageId = 0;

  int _int(dynamic value, [int fallback = 0]) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  String _category(int id) => categories[id] ?? 'General';
  String _language(int id) => languages[id] ?? 'Regional';

  (String, String) _logoUrls(String raw) {
    final clean = raw.trim().replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty) return ('', '');
    if (clean.startsWith('http')) return (clean, clean);
    final path = clean.startsWith('dare_images/') ? clean : 'dare_images/images/$clean';
    return (
      'https://jiotvimages.cdn.jio.com/$path',
      'https://jiotv.catchup.cdn.jio.com/$path',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<List<TvChannel>> _fetchJio() async {
    const urls = [
      'https://jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
      'https://jiotv.data.cdn.jio.com/apis/v3.0/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 18));
        if (response.statusCode != 200) {
          _debugErrors.add('JioTV API HTTP ${response.statusCode}');
          continue;
        }
        if (response.body.trim().isEmpty) {
          _debugErrors.add('JioTV API: empty response body');
          continue;
        }
        final decoded = jsonDecode(response.body);
        final List rows =
            decoded is Map && decoded['result'] is List ? decoded['result'] as List : [];
        final parsed = rows
            .whereType<Map>()
            .map((e) {
              final j = Map<String, dynamic>.from(e);
              final id = _int(j['channel_id']);
              final logos = _logoUrls((j['logoUrl'] ?? '').toString());
              final c = _int(j['channelCategoryId']), l = _int(j['channelLanguageId']);
              return TvChannel(
                id: id,
                name: (j['channel_name'] ?? 'Channel $id').toString(),
                logo: logos.$1,
                fallbackLogo: logos.$2,
                categoryId: c,
                category: _category(c),
                languageId: l,
                language: _language(l),
                hd: j['isHD'] == true,
                order: _int(j['channel_order'], 999999),
                raw: j,
              );
            })
            .where((c) => c.id > 0)
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        _debugErrors.add('JioTV API error: $e');
      }
    }
    return [];
  }

  Future<List<TvChannel>> _fetchExtra() async {
    try {
      final response = await http.get(
        Uri.parse(extraUrl),
        headers: const {'Accept': 'application/json', 'User-Agent': defaultUa},
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        _debugErrors.add('npoint API HTTP ${response.statusCode}');
        return [];
      }
      final decoded = jsonDecode(response.body);
      List rows = [];
      if (decoded is List) rows = decoded;
      if (decoded is Map) {
        for (final key in ['channels', 'result', 'data', 'list', 'items', 'tv']) {
          if (decoded[key] is List) {
            rows = decoded[key] as List;
            break;
          }
        }
        if (rows.isEmpty) {
          rows = decoded.values.firstWhere((v) => v is List, orElse: () => []) as List;
        }
      }
      final result = <TvChannel>[];
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is! Map) continue;
        final j = Map<String, dynamic>.from(rows[i]);
        String pick(List<String> keys) {
          for (final key in keys) {
            final value = (j[key] ?? '').toString().trim();
            if (value.isNotEmpty && value != 'null') return value;
          }
          return '';
        }

        final name = pick(['channel_name', 'channelName', 'name', 'title', 'tvg_name']);
        final stream = pick([
          'channel_url',
          'stream_url',
          'mpd_url',
          'm3u8_url',
          'url',
          'ready_to_use_link',
        ]);
        if (name.isEmpty && stream.isEmpty) continue;
        final id = _int(pick(['channel_id', 'channelId', 'id', 'chid', 'channelNo']), 1000000 + i);
        final logos = _logoUrls(pick(['channel_logo', 'logoUrl', 'logo', 'tvg_logo', 'image', 'thumbnail']));
        final rawCategory = pick(['channel_genre', 'cat', 'categoryName', 'category', 'genre', 'group_title']);
        final c = _int(pick(['channelCategoryId', 'category_id', 'categoryId']));
        final rawLanguage = pick(['languageName', 'language', 'lang']);
        final l = _int(pick(['channelLanguageId', 'language_id', 'languageId']));
        final normalizedLanguage = rawLanguage.toLowerCase() == 'malyalam' ? 'Malayalam' : rawLanguage;
        final inferredCategory = c != 0 ? c : _inferCategory('$rawCategory $name');
        final inferredLanguage = l != 0 ? l : _inferLanguage(normalizedLanguage);

        result.add(TvChannel(
          id: id,
          name: name.isEmpty ? 'Channel $id' : name,
          logo: logos.$1,
          fallbackLogo: logos.$2,
          categoryId: inferredCategory,
          category: rawCategory.isNotEmpty ? rawCategory : _category(inferredCategory),
          languageId: inferredLanguage,
          language: normalizedLanguage.isNotEmpty ? normalizedLanguage : _language(inferredLanguage),
          hd: j['isHD'] == true || j['isHd'] == true || name.toUpperCase().contains('HD'),
          order: _int(pick(['channel_order', 'order']), 10000 + i),
          raw: j,
        ));
      }
      return result;
    } catch (e) {
      _debugErrors.add('npoint API error: $e');
      return [];
    }
  }

  int _inferCategory(String value) {
    final s = value.toLowerCase();
    if (s.contains('movie') || s.contains('cinema')) return 6;
    if (s.contains('sport') || s.contains('cricket')) return 8;
    if (s.contains('news')) return 12;
    if (s.contains('kid') || s.contains('cartoon') || s.contains('nick')) return 7;
    if (s.contains('music') || s.contains('mtv')) return 13;
    if (s.contains('discovery') || s.contains('history') || s.contains('nat geo')) return 10;
    if (s.contains('bhakti') || s.contains('sanskar') || s.contains('aastha')) return 15;
    return value.trim().isEmpty ? 0 : 5;
  }

  int _inferLanguage(String value) {
    final s = value.toLowerCase();
    for (final entry in languages.entries) {
      if (entry.key != 0 && s.contains(entry.value.toLowerCase())) return entry.key;
    }
    return 0;
  }

  Future<void> _loadChannels() async {
    setState(() {
      loading = true;
      error = null;
      _debugErrors.clear();
    });
    try {
      final results = await Future.wait([_fetchJio(), _fetchExtra()]);
      final merged = <int, TvChannel>{};
      for (final channel in results[0]) {
        merged.putIfAbsent(channel.id, () => channel);
      }
      for (final extra in results[1]) {
        final old = merged[extra.id];
        if (old == null) {
          merged[extra.id] = extra;
        } else {
          merged[extra.id] = TvChannel(
            id: old.id,
            name: old.name.isNotEmpty ? old.name : extra.name,
            logo: old.logo.isNotEmpty ? old.logo : extra.logo,
            fallbackLogo: old.fallbackLogo.isNotEmpty ? old.fallbackLogo : extra.fallbackLogo,
            categoryId: old.categoryId != 0 ? old.categoryId : extra.categoryId,
            category: old.categoryId != 0 ? old.category : extra.category,
            languageId: old.languageId != 0 ? old.languageId : extra.languageId,
            language: old.languageId != 0 ? old.language : extra.language,
            hd: old.hd || extra.hd,
            order: old.order,
            raw: extra.raw,
          );
        }
      }
      final sorted = merged.values.toList()
        ..sort((a, b) {
          final order = a.order.compareTo(b.order);
          return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      if (sorted.isEmpty) {
        throw Exception(_debugErrors.isEmpty ? 'Both APIs returned zero channels.' : _debugErrors.join('\n'));
      }
      if (!mounted) return;
      setState(() => allChannels = sorted);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<TvChannel> get _filteredChannels {
    final q = query.trim().toLowerCase();
    return allChannels
        .where((c) =>
            (categoryId == 0 || c.categoryId == categoryId) &&
            (languageId == 0 || c.languageId == languageId) &&
            (!hdOnly || c.hd) &&
            (q.isEmpty ||
                c.name.toLowerCase().contains(q) ||
                c.category.toLowerCase().contains(q) ||
                c.language.toLowerCase().contains(q) ||
                c.id.toString() == q))
        .toList();
  }

  void _toggleSearch() {
    setState(() {
      searchOpen = !searchOpen;
      if (!searchOpen) {
        searchController.clear();
        query = '';
      } else {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) searchFocus.requestFocus();
        });
      }
    });
  }

  void _resetFilters() => setState(() {
        categoryId = 0;
        languageId = 0;
        hdOnly = false;
        query = '';
        searchController.clear();
      });

  Future<void> _openChannel(TvChannel channel) async {
    if (resolving) return;
    setState(() => resolving = true);

    try {
      final raw = channel.raw ?? <String, dynamic>{};
      final rawChannelId = (raw['channel_id'] ?? raw['channelId'] ?? channel.id).toString().trim();
      final requestHeaders = <String, String>{
        'User-Agent': (raw['user_agent'] ?? raw['userAgent'] ?? defaultUa).toString(),
        'Accept': '*/*',
      };
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
              firstFromMap(data, ['widevine_license_url', 'drm_license_url', 'license_url']) ?? '';

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

          streamUrl ??= firstFromMap(data, ['mpd_url', 'm3u8_url', 'url', 'stream_url']);

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
          ]) {
            if (data[field] != null) clearKeys.addAll(_parseClearKeys(data[field]));
          }
        } catch (e) {
          if (!isHttp(direct.split('|').first.trim())) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${channel.name}: $e'), duration: const Duration(seconds: 6)),
              );
            }
            return;
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
          if (k == 'drmlicense' && v.isNotEmpty && !v.startsWith('http')) {
            clearKeys.addAll(_parseClearKeys(v));
          }
        }
      }

      if (clearKeys.isEmpty) {
        for (final field in ['all_keys', 'drmLicense', 'drm_license', 'clearkey', 'clearKey', 'key']) {
          if (raw[field] != null) clearKeys.addAll(_parseClearKeys(raw[field]));
        }
      }

      if (!mounted || streamUrl == null || !isHttp(streamUrl)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${channel.name}: Valid stream URL nahi mila')),
          );
        }
        return;
      }

      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AnasTvPlayerScreen(
          channel: channel,
          url: streamUrl!,
          headers: requestHeaders,
          drmLicenseUrl: drmLicenseUrl,
          clearKeys: clearKeys,
        ),
      ));
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Map<String, String> _parseClearKeys(dynamic raw) {
    final pairs = <String, String>{};
    if (raw is Map) {
      final kid = (raw['kid'] ?? raw['key_id'] ?? '').toString().trim();
      final key = (raw['key'] ?? raw['k'] ?? '').toString().trim();
      if (kid.isNotEmpty && key.isNotEmpty) {
        pairs[kid] = key;
      } else {
        raw.forEach((k, v) {
          final ks = k.toString().trim(), vs = v.toString().trim();
          if (ks.isNotEmpty && vs.isNotEmpty) pairs[ks] = vs;
        });
      }
    } else if (raw is List) {
      for (final item in raw) {
        pairs.addAll(_parseClearKeys(item));
      }
    } else if (raw != null) {
      final str = raw.toString().trim();
      if (str.isNotEmpty && !str.startsWith('http')) {
        for (final seg in str.split(RegExp(r'[,;\n]'))) {
          final parts = seg.trim().split(':');
          if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
            pairs[parts[0].trim()] = parts[1].trim();
          }
        }
      }
    }
    return pairs;
  }

  String _extractJsonValue(String raw) {
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

  String? firstFromMap(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.startsWith('https://') || value.startsWith('http://')) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChannels;
    final dark = widget.isDark;
    final bg = dark ? const Color(0xFF050505) : const Color(0xFFF5F7FB);
    final textColor = dark ? Colors.white : const Color(0xFF121826);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                  child: Row(
                    children: [
                      if (!searchOpen) ...[
                        const Icon(Icons.live_tv_rounded, color: Color(0xFFE65312), size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'AnasTV',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const Spacer(),
                      ] else ...[
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            focusNode: searchFocus,
                            style: TextStyle(color: textColor),
                            onChanged: (v) => setState(() => query = v),
                            decoration: InputDecoration(
                              hintText: 'Search channels...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              filled: true,
                              fillColor: dark ? const Color(0xFF141821) : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                      IconButton(
                        onPressed: _toggleSearch,
                        icon: Icon(searchOpen ? Icons.close_rounded : Icons.search_rounded, color: textColor),
                        tooltip: 'Search',
                      ),
                      IconButton(
                        onPressed: widget.onToggleTheme,
                        icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: textColor),
                        tooltip: 'Theme',
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      PopupMenuButton<int>(
                        onSelected: (id) => setState(() => languageId = id),
                        itemBuilder: (_) => languages.entries
                            .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: languageId != 0
                                ? const Color(0xFFE65312)
                                : (dark ? const Color(0xFF191F2E) : const Color(0xFFEAEFF8)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Text(
                                languages[languageId] ?? 'Language',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: languageId != 0 ? Colors.white : textColor,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                                color: languageId != 0 ? Colors.white : textColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: 'HD',
                        selected: hdOnly,
                        green: true,
                        onTap: () => setState(() => hdOnly = !hdOnly),
                      ),
                      const SizedBox(width: 8),
                      ...categories.entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _FilterPill(
                              label: entry.value,
                              selected: categoryId == entry.key,
                              onTap: () => setState(() => categoryId = entry.key),
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65312)))
                      : error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.wifi_off_rounded, color: Color(0xFFE65312), size: 48),
                                    const SizedBox(height: 12),
                                    Text(error!, textAlign: TextAlign.center, style: TextStyle(color: textColor)),
                                    const SizedBox(height: 16),
                                    FilledButton(onPressed: _loadChannels, child: const Text('Retry')),
                                  ],
                                ),
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Koi channel nahi mila', style: TextStyle(color: textColor)),
                                      TextButton(onPressed: _resetFilters, child: const Text('Reset')),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  color: const Color(0xFFE65312),
                                  onRefresh: _loadChannels,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final width = constraints.maxWidth;
                                      final columns = width >= 1100 ? 8 : (width >= 700 ? 6 : 4);
                                      final gap = width >= 700 ? 12.0 : 8.0;
                                      return GridView.builder(
                                        padding: EdgeInsets.fromLTRB(gap, gap, gap, gap + 2),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisSpacing: gap,
                                          crossAxisSpacing: gap,
                                          childAspectRatio: width >= 1100 ? 1.02 : .90,
                                        ),
                                        itemCount: filtered.length,
                                        itemBuilder: (context, index) => _ChannelCard(
                                          channel: filtered[index],
                                          isDark: dark,
                                          autofocus: index == 0,
                                          onTap: () => _openChannel(filtered[index]),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
            if (resolving)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: Color(0xFFE65312))),
              ),
          ],
        ),
      ),
    );
  }
}

class AnasTvPlayerScreen extends StatefulWidget {
  final TvChannel channel;
  final String url;
  final Map<String, String> headers;
  final String drmLicenseUrl;
  final Map<String, String> clearKeys;

  const AnasTvPlayerScreen({
    super.key,
    required this.channel,
    required this.url,
    required this.headers,
    this.drmLicenseUrl = '',
    this.clearKeys = const {},
  });

  @override
  State<AnasTvPlayerScreen> createState() => _AnasTvPlayerScreenState();
}

class _AnasTvPlayerScreenState extends State<AnasTvPlayerScreen> {
  String? _error;
  String _status = 'Starting player...';
  bool _loading = true;
  MethodChannel? _channel;
  Timer? _watchdog;

  void _created(int id) {
    if (_channel != null) return;
    final ch = MethodChannel('anas_tv/media3_player_$id');
    _channel = ch;
    if (mounted) setState(() => _status = 'Connecting stream...');

    ch.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onStateChanged') {
        final state = (call.arguments ?? 'unknown').toString();
        setState(() {
          _status = 'ExoPlayer: $state';
          _loading = state == 'idle' || state == 'buffering';
        });
        if (state == 'ready' || state == 'ended') _watchdog?.cancel();
      } else if (call.method == 'onError') {
        _watchdog?.cancel();
        setState(() {
          _loading = false;
          _status = 'Playback failed';
          _error = (call.arguments ?? 'Native player reported an error').toString();
        });
      }
    });

    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Playback timeout (25s). Stream respond nahi kar rahi.';
      });
    });

    ch.invokeMethod('play', {
      'streamUrl': widget.url,
      'headers': widget.headers,
      'drmLicenseUrl': widget.drmLicenseUrl,
      'clearKeys': widget.clearKeys,
    }).catchError((Object e) {
      if (!mounted) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = 'Native player start failed: $e';
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || _channel != null) return;
      setState(() {
        _loading = false;
        _error = 'Native player view create nahi hua.';
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width < 700) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _channel?.setMethodCallHandler(null);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PlatformViewLink(
            key: ValueKey(widget.url),
            viewType: 'anas_tv/media3_player',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (params) {
              return PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: 'anas_tv/media3_player',
                layoutDirection: TextDirection.ltr,
                creationParams: {
                  'streamUrl': widget.url,
                  'headers': widget.headers,
                  'drmLicenseUrl': widget.drmLicenseUrl,
                  'clearKeys': widget.clearKeys,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..addOnPlatformViewCreatedListener(_created)
                ..create();
            },
          ),
          if (_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFE65312)),
                  const SizedBox(height: 12),
                  Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          if (_error != null)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orange, size: 38),
                    const SizedBox(height: 12),
                    SelectableText(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to channels'),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected, green;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.green = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = green ? const Color(0xFF10B981) : const Color(0xFFE65312);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? active : (dark ? const Color(0xFF191F2E) : const Color(0xFFEAEFF8)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? active : (dark ? const Color(0xFF283148) : const Color(0xFFD9E0EE)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : (dark ? const Color(0xFFBAC4D9) : const Color(0xFF3E485E)),
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final TvChannel channel;
  final bool isDark, autofocus;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.isDark,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool focused = false, hovered = false;

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDark ? const Color(0xFF080808) : Colors.white;
    final nameColor = widget.isDark ? Colors.white : const Color(0xFF121826);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final logoSize = w * .72;
      final nameSize = (w * .145).clamp(9.0, 26.0).toDouble();
      final highlighted = focused || hovered;
      return AnimatedScale(
        scale: focused ? 1.035 : 1,
        duration: const Duration(milliseconds: 130),
        child: Material(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            autofocus: widget.autofocus,
            canRequestFocus: true,
            borderRadius: BorderRadius.circular(8),
            onFocusChange: (value) => setState(() => focused = value),
            onHover: (value) => setState(() => hovered = value),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(
                  color: highlighted ? const Color(0xFFFF8A35) : const Color(0xFFD94B0A),
                  width: focused ? 2.4 : (hovered ? 1.8 : 1.2),
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: focused
                    ? [BoxShadow(color: const Color(0xFFE65312).withOpacity(.42), blurRadius: 14, spreadRadius: 1)]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: logoSize,
                    height: logoSize,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: highlighted ? const Color(0xFFFF8A35) : const Color(0xFFD94B0A),
                          width: focused ? 2.0 : 1.2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      padding: EdgeInsets.all(w * .055),
                      child: _ChannelLogo(
                        primaryUrl: widget.channel.logo,
                        fallbackUrl: widget.channel.fallbackLogo,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: nameSize * 1.45,
                    width: double.infinity,
                    child: Center(
                      child: _ChannelMarquee(
                        text: widget.channel.name,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: nameSize,
                          height: 1.05,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ChannelMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _ChannelMarquee({required this.text, required this.style});
  @override
  State<_ChannelMarquee> createState() => _ChannelMarqueeState();
}

class _ChannelMarqueeState extends State<_ChannelMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _running = false;
  double _lastDistance = 0;
  static const double _gap = 34;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _ChannelMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _running = false;
      _lastDistance = 0;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final textWidth = painter.width;
      if (textWidth <= constraints.maxWidth || constraints.maxWidth <= 0) {
        _running = false;
        _controller.stop();
        return ClipRect(
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        );
      }
      final distance = textWidth + _gap;
      if (!_running || (_lastDistance - distance).abs() > 1) {
        _running = true;
        _lastDistance = distance;
        _controller.duration = Duration(milliseconds: ((distance / 38) * 1000).round().clamp(1800, 18000).toInt());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _running) _controller.repeat();
        });
      }
      return ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.translate(
            offset: Offset(-distance * _controller.value, 0),
            child: child,
          ),
          child: SizedBox(
            width: distance + textWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: textWidth, child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style)),
                const SizedBox(width: _gap),
                SizedBox(width: textWidth, child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _ChannelLogo extends StatefulWidget {
  final String primaryUrl, fallbackUrl;
  const _ChannelLogo({required this.primaryUrl, required this.fallbackUrl});
  @override
  State<_ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<_ChannelLogo> {
  bool fallback = false;
  @override
  Widget build(BuildContext context) {
    final url = fallback ? widget.fallbackUrl : widget.primaryUrl;
    if (url.isEmpty) return const Center(child: Icon(Icons.tv_rounded, size: 30, color: Colors.grey));
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        if (!fallback && widget.fallbackUrl.isNotEmpty && widget.fallbackUrl != widget.primaryUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => fallback = true);
          });
        }
        return const Center(child: Icon(Icons.tv_rounded, size: 30, color: Colors.grey));
      },
    );
  }
}
