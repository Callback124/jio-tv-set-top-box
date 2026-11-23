import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

class AnasTvApp extends StatefulWidget {
  const AnasTvApp({super.key});

  @override
  State<AnasTvApp> createState() => _AnasTvAppState();
}

class _AnasTvAppState extends State<AnasTvApp> {
  static const _deviceChannel = MethodChannel('anas_tv/device');
  bool _isTv = false;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSize = 500;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 128 << 20;
    _detectDeviceMode();
  }

  Future<void> _detectDeviceMode() async {
    try {
      final tv = await _deviceChannel.invokeMethod<bool>('isTv') ?? false;
      if (!mounted) return;
      setState(() => _isTv = tv);
      if (tv) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AnasTV',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE65312),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF050505),
        ),
        home: AnasTvHomePage(isTv: _isTv),
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

class ResolvedPlayback {
  final String streamUrl;
  final Map<String, String> headers;
  final String drmLicenseUrl;
  final Map<String, String> clearKeys;

  const ResolvedPlayback({
    required this.streamUrl,
    required this.headers,
    required this.drmLicenseUrl,
    required this.clearKeys,
  });
}

class StreamResolver {
  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';

  static Future<ResolvedPlayback> resolve(TvChannel channel) async {
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
            _firstFromMap(data, ['widevine_license_url', 'drm_license_url', 'license_url']) ?? '';

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
        ]) {
          if (data[field] != null) clearKeys.addAll(_parseClearKeys(data[field]));
        }
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

    if (streamUrl == null || !isHttp(streamUrl)) {
      throw Exception('Valid stream URL nahi mila');
    }

    return ResolvedPlayback(
      streamUrl: streamUrl,
      headers: requestHeaders,
      drmLicenseUrl: drmLicenseUrl,
      clearKeys: clearKeys,
    );
  }

  static Map<String, String> _parseClearKeys(dynamic raw) {
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

class _BrandCircularLoader extends StatelessWidget {
  final double size;

  const _BrandCircularLoader({this.size = 76});

  @override
  Widget build(BuildContext context) {
    final innerSize = size - 14;
    return SizedBox(
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
    );
  }
}

class AnasTvHomePage extends StatefulWidget {
  final bool isTv;

  const AnasTvHomePage({super.key, required this.isTv});

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

  static const extraUrl = 'https://api.npoint.io/9db02feba76eb297fc65';

  final List<String> _debugErrors = [];
  final ScrollController _tabScroll = ScrollController();
  final ScrollController _gridScroll = ScrollController();
  final Map<int, FocusNode> _tabNodes = {};
  final Map<int, FocusNode> _cardNodes = {};

  List<TvChannel> allChannels = [];
  List<String> filterTabs = ['ALL'];
  String selectedTab = 'ALL';
  bool loading = true;
  String? error;

  Timer? _zeroHoldTimer;
  bool _openedSearchOnHold = false;
  bool _searchOpen = false;
  double _dragDeltaX = 0;
  DateTime? _lastSubScreenReturnAt;

  int _int(dynamic value, [int fallback = 0]) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  String _category(int id) => categories[id] ?? 'General';

  FocusNode _tabNode(int index) => _tabNodes.putIfAbsent(index, () => FocusNode());
  FocusNode _cardNode(int index) => _cardNodes.putIfAbsent(index, () => FocusNode());

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
  void didUpdateWidget(covariant AnasTvHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isTv && widget.isTv && !loading && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_filteredChannels.isNotEmpty) {
          _focusCard(0);
        } else {
          _focusSelectedTab();
        }
      });
    }
  }

  @override
  void dispose() {
    _zeroHoldTimer?.cancel();
    _tabScroll.dispose();
    _gridScroll.dispose();
    for (final n in _tabNodes.values) {
      n.dispose();
    }
    for (final n in _cardNodes.values) {
      n.dispose();
    }
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
        if (response.statusCode != 200 || response.body.trim().isEmpty) continue;
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
                language: '',
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

  Future<(List<TvChannel>, List<String>)> _fetchExtra() async {
    try {
      final response = await http.get(
        Uri.parse(extraUrl),
        headers: const {'Accept': 'application/json', 'User-Agent': StreamResolver.defaultUa},
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        _debugErrors.add('npoint API HTTP ${response.statusCode}');
        return (<TvChannel>[], <String>[]);
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
      final seenGenres = <String>{};
      final apiGenres = <String>[];

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
          'ready_to_use_link',
          'channel_url',
          'stream_url',
          'mpd_url',
          'm3u8_url',
          'url',
        ]);
        if (name.isEmpty && stream.isEmpty) continue;

        final id = _int(pick(['channel_id', 'channelId', 'id', 'chid', 'channelNo']), 1000000 + i);
        final logos = _logoUrls(pick(['channel_logo', 'logoUrl', 'logo', 'tvg_logo', 'image', 'thumbnail']));
        final rawCategory = pick(['channel_genre', 'cat', 'categoryName', 'category', 'genre', 'group_title']);
        final c = _int(pick(['channelCategoryId', 'category_id', 'categoryId']));
        final l = _int(pick(['channelLanguageId', 'language_id', 'languageId']));
        final rawLanguage = pick(['languageName', 'language', 'lang']);

        final cleanGenre = rawCategory.trim();
        if (cleanGenre.isNotEmpty && cleanGenre.toLowerCase() != 'unknown') {
          final key = cleanGenre.toLowerCase();
          if (seenGenres.add(key)) {
            apiGenres.add(cleanGenre);
          }
        }

        result.add(TvChannel(
          id: id,
          name: name.isEmpty ? 'Channel $id' : name,
          logo: logos.$1,
          fallbackLogo: logos.$2,
          categoryId: c,
          category: cleanGenre,
          languageId: l,
          language: rawLanguage,
          hd: j['isHD'] == true || j['isHd'] == true || name.toUpperCase().contains('HD'),
          order: _int(pick(['channel_order', 'order']), 10000 + i),
          raw: j,
        ));
      }
      return (result, apiGenres);
    } catch (e) {
      _debugErrors.add('npoint API error: $e');
      return (<TvChannel>[], <String>[]);
    }
  }

  Future<void> _loadChannels() async {
    setState(() {
      loading = true;
      error = null;
      _debugErrors.clear();
    });
    try {
      final jioFuture = _fetchJio();
      final extraFuture = _fetchExtra();
      final jioList = await jioFuture;
      final extraResult = await extraFuture;
      final extraList = extraResult.$1;
      final apiGenres = extraResult.$2;

      final merged = <int, TvChannel>{};
      for (final channel in jioList) {
        merged.putIfAbsent(channel.id, () => channel);
      }
      for (final extra in extraList) {
        final old = merged[extra.id];
        if (old == null) {
          merged[extra.id] = extra;
        } else {
          merged[extra.id] = TvChannel(
            id: old.id,
            name: old.name.isNotEmpty ? old.name : extra.name,
            logo: old.logo.isNotEmpty ? old.logo : extra.logo,
            fallbackLogo: old.fallbackLogo.isNotEmpty ? old.fallbackLogo : extra.fallbackLogo,
            categoryId: extra.categoryId != 0 ? extra.categoryId : old.categoryId,
            category: extra.category.isNotEmpty ? extra.category : old.category,
            languageId: old.languageId != 0 ? old.languageId : extra.languageId,
            language: extra.language.isNotEmpty ? extra.language : old.language,
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

      final tabs = <String>['ALL', ...apiGenres];
      if (!mounted) return;
      setState(() {
        allChannels = sorted;
        filterTabs = tabs;
        if (!tabs.any((t) => t.toLowerCase() == selectedTab.toLowerCase())) {
          selectedTab = 'ALL';
        }
      });
      if (widget.isTv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _filteredChannels.isNotEmpty) _focusCard(0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<TvChannel> get _filteredChannels {
    if (selectedTab.toUpperCase() == 'ALL') return allChannels;
    final target = selectedTab.trim().toLowerCase();
    return allChannels
        .where((c) => c.category.trim().toLowerCase() == target)
        .toList();
  }

  int get _selectedTabIndex {
    final idx = filterTabs.indexWhere((t) => t.toLowerCase() == selectedTab.toLowerCase());
    return idx >= 0 ? idx : 0;
  }

  void _focusSelectedTab() {
    if (!widget.isTv || filterTabs.isEmpty) return;
    _tabNode(_selectedTabIndex).requestFocus();
  }

  void _selectTab(String label) {
    setState(() => selectedTab = label);
    if (_gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
    }
  }

  void _focusCard(int targetIndex) {
    final node = _cardNodes[targetIndex];
    if (node != null && node.canRequestFocus && node.context != null) {
      node.requestFocus();
      return;
    }
    if (targetIndex == 0 && _gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final n = _cardNodes[0];
        if (n != null && n.canRequestFocus) n.requestFocus();
      });
    }
  }

  KeyEventResult _handleTabKey(int tabIndex, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (tabIndex >= 0 && tabIndex < filterTabs.length) {
        _selectTab(filterTabs[tabIndex]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (tabIndex > 0) _tabNode(tabIndex - 1).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (tabIndex + 1 < filterTabs.length) _tabNode(tabIndex + 1).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_filteredChannels.isNotEmpty) _focusCard(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCardKey(int index, int columns, int totalCount, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final row = index ~/ columns;
    final col = index % columns;
    final isFirstRowLastItem = row == 0 && (col == columns - 1 || index == totalCount - 1);

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final filtered = _filteredChannels;
      if (index >= 0 && index < filtered.length) {
        _openChannel(filtered, index, restoreCardIndex: index);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row == 0 && col == 0) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      if (index > 0) {
        _focusCard(index - 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isFirstRowLastItem) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      if (index + 1 < totalCount) {
        _focusCard(index + 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      _focusCard(index - columns);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < totalCount) {
        _focusCard(index + columns);
      } else if ((row + 1) * columns < totalCount) {
        _focusCard(totalCount - 1);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isZeroKey(KeyEvent event) {
    final l = event.logicalKey;
    final p = event.physicalKey;
    return l == LogicalKeyboardKey.digit0 ||
        l == LogicalKeyboardKey.numpad0 ||
        p == PhysicalKeyboardKey.digit0 ||
        p == PhysicalKeyboardKey.numpad0;
  }

  KeyEventResult _handleGlobalTvKey(FocusNode node, KeyEvent event) {
    if (!widget.isTv || loading || error != null || allChannels.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (!_isZeroKey(event)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (!_openedSearchOnHold) {
        _zeroHoldTimer?.cancel();
        _zeroHoldTimer = Timer(const Duration(milliseconds: 500), () {
          _openedSearchOnHold = true;
          if (mounted) _openSearchScreen();
        });
      }
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      if (!_openedSearchOnHold) {
        _zeroHoldTimer?.cancel();
        _openedSearchOnHold = true;
        _openSearchScreen();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _zeroHoldTimer?.cancel();
      _openedSearchOnHold = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _focusedRestoreIndex() {
    for (final entry in _cardNodes.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    return 0;
  }

  void _openSearchScreen() {
    if (_searchOpen || allChannels.isEmpty) return;
    _searchOpen = true;
    final restoreIndex = _focusedRestoreIndex();
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 220),
          reverseTransitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          pageBuilder: (_, __, ___) => AnasTvSearchScreen(channels: allChannels, isTv: widget.isTv),
          transitionsBuilder: widget.isTv
              ? (_, __, ___, child) => child
              : (_, animation, __, child) => SlideTransition(
                    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
        ))
        .then((_) {
          _zeroHoldTimer?.cancel();
          _openedSearchOnHold = false;
          _searchOpen = false;
          _lastSubScreenReturnAt = DateTime.now();
          if (widget.isTv && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreIndex);
            });
          }
        });
  }

  void _openChannel(List<TvChannel> channels, int initialIndex, {int? restoreCardIndex}) {
    if (channels.isEmpty) return;
    final safeIdx = initialIndex.clamp(0, channels.length - 1);
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(
            channels: channels,
            initialIndex: safeIdx,
            isTv: widget.isTv,
          ),
        ))
        .then((_) {
          _lastSubScreenReturnAt = DateTime.now();
          if (widget.isTv && restoreCardIndex != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreCardIndex);
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChannels;
    final gridWidget = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = widget.isTv ? 8 : (width >= 700 ? 6 : 4);
        final spacing = widget.isTv ? 7.0 : (width >= 700 ? 10.0 : 8.0);
        return GridView.builder(
          controller: _gridScroll,
          cacheExtent: 260,
          clipBehavior: Clip.none,
          padding: widget.isTv
              ? const EdgeInsets.fromLTRB(12, 10, 12, 14)
              : EdgeInsets.fromLTRB(spacing, spacing, spacing, spacing + 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: widget.isTv ? 0.88 : 0.86,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) => RepaintBoundary(
            child: _ChannelCard(
              channel: filtered[index],
              isTv: widget.isTv,
              focusNode: widget.isTv ? _cardNode(index) : null,
              autofocus: widget.isTv && index == 0,
              onKeyEvent: widget.isTv
                  ? (node, event) => _handleCardKey(index, columns, filtered.length, event)
                  : null,
              onTap: () => _openChannel(filtered, index, restoreCardIndex: index),
            ),
          ),
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final lastReturn = _lastSubScreenReturnAt;
        if (lastReturn != null &&
            DateTime.now().difference(lastReturn) < const Duration(milliseconds: 700)) {
          return;
        }
        SystemNavigator.pop();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: widget.isTv ? _handleGlobalTvKey : null,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: !widget.isTv ? (_) => _dragDeltaX = 0 : null,
          onHorizontalDragUpdate: !widget.isTv ? (details) => _dragDeltaX += details.delta.dx : null,
          onHorizontalDragEnd: !widget.isTv
              ? (details) {
                  if ((details.primaryVelocity ?? 0) < -240 || _dragDeltaX < -75) {
                    _openSearchScreen();
                  }
                }
              : null,
          child: Scaffold(
            backgroundColor: const Color(0xFF050505),
            body: SafeArea(
              child: Column(
                children: [
                  if (!loading && error == null && filterTabs.length > 1)
                    Padding(
                      padding: EdgeInsets.only(top: widget.isTv ? 10 : 0),
                      child: Container(
                        height: widget.isTv ? 46 : 44,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFF050505),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
                          ),
                        ),
                        child: ListView.builder(
                          controller: _tabScroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: filterTabs.length,
                          itemBuilder: (context, index) {
                            final label = filterTabs[index];
                            final selected = label.toLowerCase() == selectedTab.toLowerCase();
                            return _CategoryTab(
                              label: label.toUpperCase(),
                              selected: selected,
                              isTv: widget.isTv,
                              focusNode: widget.isTv ? _tabNode(index) : null,
                              onKeyEvent:
                                  widget.isTv ? (node, event) => _handleTabKey(index, event) : null,
                              onTap: () => _selectTab(label),
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: ClipRect(
                      child: loading
                          ? const Center(child: _BrandCircularLoader(size: 80))
                          : error != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.wifi_off_rounded, color: Color(0xFFE65312), size: 48),
                                        const SizedBox(height: 12),
                                        Text(error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white)),
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
                                          const Text('Koi channel nahi mila',
                                              style: TextStyle(color: Colors.white)),
                                          TextButton(
                                            onPressed: () => setState(() => selectedTab = 'ALL'),
                                            child: const Text('Show All'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : widget.isTv
                                      ? gridWidget
                                      : RefreshIndicator(
                                          color: const Color(0xFFE65312),
                                          onRefresh: _loadChannels,
                                          child: gridWidget,
                                        ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final bool isTv;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.isTv,
    required this.onTap,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final showTvFocus = widget.isTv && focused;

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.isTv,
      onKeyEvent: widget.onKeyEvent,
      onFocusChange: (v) {
        if (widget.isTv) {
          setState(() => focused = v);
          if (v) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 120),
            );
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, widget.isTv ? 4 : 0, 16, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: showTvFocus ? const Color(0xFF23262F) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFFE65312) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 0.35,
              fontWeight: active || showTvFocus ? FontWeight.w700 : FontWeight.w600,
              color: active
                  ? const Color(0xFFE65312)
                  : (showTvFocus ? Colors.white : const Color(0xFFD0D4DC)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusSearchGridIntent extends Intent {
  const _FocusSearchGridIntent();
}

class AnasTvSearchScreen extends StatefulWidget {
  final List<TvChannel> channels;
  final bool isTv;

  const AnasTvSearchScreen({
    super.key,
    required this.channels,
    required this.isTv,
  });

  @override
  State<AnasTvSearchScreen> createState() => _AnasTvSearchScreenState();
}

class _AnasTvSearchScreenState extends State<AnasTvSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocus;
  final ScrollController _gridScroll = ScrollController();
  final Map<int, FocusNode> _cardNodes = {};

  String _query = '';
  bool _isExiting = false;
  bool _ignoreInitialZeroKeys = false;
  late final DateTime _openedAt = DateTime.now();
  Timer? _zeroGuardTimer;
  double _dragDeltaX = 0;

  FocusNode _cardNode(int index) => _cardNodes.putIfAbsent(index, () => FocusNode());

  bool _isZeroKey(KeyEvent event) {
    final l = event.logicalKey;
    final p = event.physicalKey;
    return l == LogicalKeyboardKey.digit0 ||
        l == LogicalKeyboardKey.numpad0 ||
        p == PhysicalKeyboardKey.digit0 ||
        p == PhysicalKeyboardKey.numpad0;
  }

  void _reopenSearchKeyboard() {
    _ignoreInitialZeroKeys = false;
    _zeroGuardTimer?.cancel();
    _searchFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  @override
  void initState() {
    super.initState();
    _ignoreInitialZeroKeys = widget.isTv;
    if (widget.isTv) {
      _zeroGuardTimer = Timer(const Duration(milliseconds: 1200), () {
        _ignoreInitialZeroKeys = false;
      });
    }
    _searchFocus = FocusNode(
      onKeyEvent: (node, event) {
        if (!widget.isTv) return KeyEventResult.ignored;
        if (_isZeroKey(event) && _ignoreInitialZeroKeys) {
          if (event is KeyUpEvent) {
            _ignoreInitialZeroKeys = false;
            _zeroGuardTimer?.cancel();
          }
          return KeyEventResult.handled;
        }
        if (_ignoreInitialZeroKeys && event is KeyDownEvent && !_isZeroKey(event)) {
          _ignoreInitialZeroKeys = false;
          _zeroGuardTimer?.cancel();
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (event is KeyDownEvent) {
            _reopenSearchKeyboard();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _zeroGuardTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _gridScroll.dispose();
    for (final n in _cardNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  List<TvChannel> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.channels;
    final starts = <TvChannel>[];
    final contains = <TvChannel>[];
    for (final c in widget.channels) {
      final lower = c.name.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(c);
      } else if (lower.contains(q)) {
        contains.add(c);
      }
    }
    return [...starts, ...contains];
  }

  void _focusCard(int targetIndex) {
    final node = _cardNodes[targetIndex];
    if (node != null && node.canRequestFocus && node.context != null) {
      node.requestFocus();
      return;
    }
    if (targetIndex == 0 && _gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final n = _cardNodes[0];
        if (n != null && n.canRequestFocus) n.requestFocus();
      });
    }
  }

  KeyEventResult _handleCardKey(int index, int columns, int totalCount, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final row = index ~/ columns;
    final col = index % columns;
    final isFirstRowLastItem = row == 0 && (col == columns - 1 || index == totalCount - 1);

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final results = _results;
      if (index >= 0 && index < results.length) {
        _openChannel(results, index, restoreCardIndex: index);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row == 0 && col == 0) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (index > 0) _focusCard(index - 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isFirstRowLastItem) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (index + 1 < totalCount) _focusCard(index + 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      _focusCard(index - columns);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < totalCount) {
        _focusCard(index + columns);
      } else if ((row + 1) * columns < totalCount) {
        _focusCard(totalCount - 1);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openChannel(List<TvChannel> channels, int initialIndex, {int? restoreCardIndex}) {
    if (channels.isEmpty) return;
    final safeIdx = initialIndex.clamp(0, channels.length - 1);
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(
            channels: channels,
            initialIndex: safeIdx,
            isTv: widget.isTv,
          ),
        ))
        .then((_) {
          if (widget.isTv && restoreCardIndex != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreCardIndex);
            });
          }
        });
  }

  void _exitSearch() {
    if (_isExiting) return;
    _isExiting = true;
    FocusScope.of(context).unfocus();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSearch();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: !widget.isTv ? (_) => _dragDeltaX = 0 : null,
        onHorizontalDragUpdate: !widget.isTv ? (details) => _dragDeltaX += details.delta.dx : null,
        onHorizontalDragEnd: !widget.isTv
            ? (details) {
                if ((details.primaryVelocity ?? 0) > 260 || _dragDeltaX > 80) {
                  _exitSearch();
                }
              }
            : null,
        child: Scaffold(
          backgroundColor: const Color(0xFF050505),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: widget.isTv ? 10 : 0),
                  child: Container(
                    height: widget.isTv ? 46 : 44,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF050505),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Shortcuts(
                      shortcuts: widget.isTv
                          ? const <ShortcutActivator, Intent>{
                              SingleActivator(LogicalKeyboardKey.arrowDown):
                                  _FocusSearchGridIntent(),
                            }
                          : const <ShortcutActivator, Intent>{},
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          _FocusSearchGridIntent: CallbackAction<_FocusSearchGridIntent>(
                            onInvoke: (_) {
                              if (_results.isNotEmpty) _focusCard(0);
                              return null;
                            },
                          ),
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, widget.isTv ? 4 : 0, 24, 0),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            autofocus: true,
                            textAlign: TextAlign.center,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                            cursorColor: const Color(0xFFE65312),
                            textInputAction: TextInputAction.search,
                            onTap: widget.isTv ? _reopenSearchKeyboard : null,
                            onSubmitted: (_) {
                              if (widget.isTv && _results.isNotEmpty) {
                                _focusCard(0);
                              }
                            },
                            inputFormatters: widget.isTv
                                ? [
                                    TextInputFormatter.withFunction((oldValue, newValue) {
                                      if (_ignoreInitialZeroKeys &&
                                          DateTime.now().difference(_openedAt) <
                                              const Duration(milliseconds: 1200) &&
                                          oldValue.text.isEmpty &&
                                          RegExp(r'^0+$').hasMatch(newValue.text)) {
                                        return oldValue;
                                      }
                                      if (newValue.text.isNotEmpty &&
                                          !RegExp(r'^0+$').hasMatch(newValue.text)) {
                                        _ignoreInitialZeroKeys = false;
                                      }
                                      return newValue;
                                    }),
                                  ]
                                : null,
                            decoration: const InputDecoration(
                              hintText: 'Search...',
                              hintStyle: TextStyle(
                                color: Color(0xFF8B909E),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              setState(() => _query = value);
                              if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: results.isEmpty
                        ? const Center(
                            child: Text(
                              'Koi channel nahi mila',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final columns = widget.isTv ? 8 : (width >= 700 ? 6 : 4);
                              final spacing = widget.isTv ? 7.0 : (width >= 700 ? 10.0 : 8.0);
                              return GridView.builder(
                                controller: _gridScroll,
                                cacheExtent: 260,
                                clipBehavior: Clip.none,
                                padding: widget.isTv
                                    ? const EdgeInsets.fromLTRB(12, 10, 12, 14)
                                    : EdgeInsets.fromLTRB(spacing, spacing, spacing, spacing + 8),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: spacing,
                                  crossAxisSpacing: spacing,
                                  childAspectRatio: widget.isTv ? 0.88 : 0.86,
                                ),
                                itemCount: results.length,
                                itemBuilder: (context, index) => RepaintBoundary(
                                  child: _ChannelCard(
                                    channel: results[index],
                                    isTv: widget.isTv,
                                    focusNode: widget.isTv ? _cardNode(index) : null,
                                    onKeyEvent: widget.isTv
                                        ? (node, event) =>
                                            _handleCardKey(index, columns, results.length, event)
                                        : null,
                                    onTap: () =>
                                        _openChannel(results, index, restoreCardIndex: index),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StbProgram {
  final String title;
  final String timeLabel;
  final String description;
  final String posterUrl;
  final double progress;

  const _StbProgram({
    required this.title,
    required this.timeLabel,
    required this.description,
    required this.posterUrl,
    required this.progress,
  });
}

class _ChannelEpg {
  final _StbProgram live;
  final _StbProgram next;

  const _ChannelEpg({required this.live, required this.next});
}

class _HindiTrendingItem {
  final String badge;
  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;

  const _HindiTrendingItem({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
  });
}

class _EpgService {
  static final Map<int, _ChannelEpg> _cache = {};
  static final math.Random _rng = math.Random();

  static const List<_HindiTrendingItem> _trendingPool = [
    _HindiTrendingItem(
      badge: 'LIVE CRICKET',
      title: 'IND vs AUS Live Match',
      subtitle: 'Hindi Commentary • Live',
      accent: Color(0xFF1565C0),
      icon: Icons.sports_cricket_rounded,
    ),
    _HindiTrendingItem(
      badge: 'WORLD PREMIERE',
      title: 'Stree 2 (Hindi)',
      subtitle: 'Superhit Premiere Movie',
      accent: Color(0xFFC62828),
      icon: Icons.movie_creation_rounded,
    ),
    _HindiTrendingItem(
      badge: 'HINDI TRENDING',
      title: 'Taarak Mehta Ka Ooltah...',
      subtitle: 'Top Trending Comedy Show',
      accent: Color(0xFFE65312),
      icon: Icons.trending_up_rounded,
    ),
    _HindiTrendingItem(
      badge: 'PREMIERE MOVIE',
      title: 'Bhool Bhulaiyaa 3',
      subtitle: 'Blockbuster Hindi HD',
      accent: Color(0xFF6A1B9A),
      icon: Icons.local_movies_rounded,
    ),
    _HindiTrendingItem(
      badge: 'HINDI TRENDING',
      title: 'Bigg Boss Special',
      subtitle: 'Live Reality Show',
      accent: Color(0xFFD84315),
      icon: Icons.whatshot_rounded,
    ),
    _HindiTrendingItem(
      badge: 'CRICKET LIVE',
      title: 'T20 Cricket Highlights',
      subtitle: 'Hindi Sports Trending',
      accent: Color(0xFF00695C),
      icon: Icons.sports_score_rounded,
    ),
    _HindiTrendingItem(
      badge: 'BLOCKBUSTER',
      title: 'Jawan • Hindi Action',
      subtitle: 'Cinema Premiere',
      accent: Color(0xFFB71C1C),
      icon: Icons.star_rounded,
    ),
    _HindiTrendingItem(
      badge: 'HINDI LIVE',
      title: 'The Kapil Sharma Show',
      subtitle: 'Trending Weekend Show',
      accent: Color(0xFF283593),
      icon: Icons.theater_comedy_rounded,
    ),
  ];

  static _HindiTrendingItem pickRandomTrending([_HindiTrendingItem? avoid]) {
    if (_trendingPool.length <= 1) return _trendingPool.first;
    _HindiTrendingItem picked;
    do {
      picked = _trendingPool[_rng.nextInt(_trendingPool.length)];
    } while (avoid != null && picked.title == avoid.title);
    return picked;
  }

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

  static _ChannelEpg fallbackFor(TvChannel ch) {
    final now = DateTime.now();
    final slotStartMin = now.minute < 30 ? 0 : 30;
    final liveStart = DateTime(now.year, now.month, now.day, now.hour, slotStartMin);
    final liveEnd = liveStart.add(const Duration(minutes: 30));
    final nextEnd = liveEnd.add(const Duration(minutes: 30));
    final elapsed = now.difference(liveStart).inSeconds;
    final progress = (elapsed / 1800.0).clamp(0.06, 0.96);
    final day = _weekdayShort(now.weekday);
    final cat = ch.category.toLowerCase();

    late final String liveTitle;
    late final String liveDesc;
    late final String nextTitle;
    late final String nextDesc;

    if (cat.contains('sport')) {
      liveTitle = '${ch.name} Live Match & Analysis';
      liveDesc = 'Live stadium action, pitch insights, Hindi commentary aur real-time score updates.';
      nextTitle = 'Post Match & Trending Highlights';
      nextDesc = 'Match ke best moments, top wickets aur expert panel analysis.';
    } else if (cat.contains('movie')) {
      liveTitle = '${ch.name} Premiere Feature Film';
      liveDesc = 'Aaj ki blockbuster feature movie HD picture quality aur surround audio ke saath.';
      nextTitle = 'Mega Night Cinema Special';
      nextDesc = 'Agli superhit family entertainer film non-stop broadcasting ke saath.';
    } else if (cat.contains('news')) {
      liveTitle = 'Breaking News & Live Bulletin';
      liveDesc = 'Desh aur duniya ki sabse badi khabrein aur live ground reports.';
      nextTitle = 'Prime Debate & Top Headlines';
      nextDesc = 'Din bhar ki badi khabron par vishesh charcha aur tezi se updates.';
    } else if (cat.contains('kid')) {
      liveTitle = '${ch.name} Cartoon Adventure';
      liveDesc = 'Bachchon ka pasandida animated show masti aur comedy ke saath.';
      nextTitle = 'Super Hero Kids Hour';
      nextDesc = 'Naya episode action aur fun-filled adventures se bhara hua.';
    } else if (cat.contains('music')) {
      liveTitle = 'Top Trending Hindi Hits';
      liveDesc = 'Non-stop Bollywood chartbusters aur latest trending music videos.';
      nextTitle = 'Retro & Romantic Special';
      nextDesc = 'Sadaabahar superhit gaane aur viewers choice playlist.';
    } else {
      liveTitle = '${ch.name} Prime Show Live';
      liveDesc = '${ch.name} par abhi dekhein popular family show aur live entertainment broadcast.';
      nextTitle = '${ch.name} Next Special Episode';
      nextDesc = 'Agle slot mein dekhein naya drama, twist aur special episode presentation.';
    }

    return _ChannelEpg(
      live: _StbProgram(
        title: liveTitle,
        timeLabel: '$day : ${_fmtTime(liveStart)} - ${_fmtTime(liveEnd)}',
        description: liveDesc,
        posterUrl: ch.logo,
        progress: progress,
      ),
      next: _StbProgram(
        title: nextTitle,
        timeLabel: '$day : ${_fmtTime(liveEnd)} - ${_fmtTime(nextEnd)}',
        description: nextDesc,
        posterUrl: ch.logo,
        progress: 0.0,
      ),
    );
  }

  static Future<_ChannelEpg> fetch(TvChannel ch) async {
    final cached = _cache[ch.id];
    if (cached != null) return cached;

    if (ch.id >= 1000000) {
      return fallbackFor(ch);
    }

    try {
      final url = 'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get?channel_id=${ch.id}&offset=0';
      final response = await http
          .get(Uri.parse(url), headers: _AnasTvHomePageState.headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return fallbackFor(ch);
      }
      final decoded = jsonDecode(response.body);
      final List epgList = decoded is Map && decoded['epg'] is List ? decoded['epg'] as List : [];
      if (epgList.isEmpty) return fallbackFor(ch);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      int currentIdx = -1;
      for (var i = 0; i < epgList.length; i++) {
        final row = epgList[i];
        if (row is! Map) continue;
        final s = _parseEpochMs(row['startEpoch']);
        final e = _parseEpochMs(row['endEpoch']);
        if (s > 0 && e > s && nowMs >= s && nowMs < e) {
          currentIdx = i;
          break;
        }
      }
      if (currentIdx < 0) return fallbackFor(ch);

      _StbProgram toProg(Map raw, {bool computeProgress = false}) {
        final sMs = _parseEpochMs(raw['startEpoch']);
        final eMs = _parseEpochMs(raw['endEpoch']);
        final sDt = DateTime.fromMillisecondsSinceEpoch(sMs);
        final eDt = DateTime.fromMillisecondsSinceEpoch(eMs);
        final prog = computeProgress && eMs > sMs
            ? ((nowMs - sMs) / (eMs - sMs)).clamp(0.05, 0.98)
            : 0.0;
        final rawPoster = (raw['episodePoster'] ?? '').toString().trim();
        final posterUrl = rawPoster.isEmpty
            ? ch.logo
            : (rawPoster.startsWith('http')
                ? rawPoster
                : 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/$rawPoster');
        final title = (raw['showname'] ?? '${ch.name} Live').toString().trim();
        final desc = (raw['description'] ?? '${ch.name} live television broadcast.').toString().trim();
        return _StbProgram(
          title: title.isEmpty ? '${ch.name} Live' : title,
          timeLabel: '${_weekdayShort(sDt.weekday)} : ${_fmtTime(sDt)} - ${_fmtTime(eDt)}',
          description: desc.isEmpty ? '${ch.name} live television broadcast.' : desc,
          posterUrl: posterUrl,
          progress: prog,
        );
      }

      final liveMap = Map<String, dynamic>.from(epgList[currentIdx] as Map);
      final liveProg = toProg(liveMap, computeProgress: true);
      final _StbProgram nextProg;
      if (currentIdx + 1 < epgList.length && epgList[currentIdx + 1] is Map) {
        nextProg = toProg(Map<String, dynamic>.from(epgList[currentIdx + 1] as Map));
      } else {
        nextProg = fallbackFor(ch).next;
      }

      final result = _ChannelEpg(live: liveProg, next: nextProg);
      _cache[ch.id] = result;
      return result;
    } catch (_) {
      return fallbackFor(ch);
    }
  }

  static int _parseEpochMs(dynamic val) {
    final n = int.tryParse(val?.toString() ?? '') ?? 0;
    if (n <= 0) return 0;
    return n < 100000000000 ? n * 1000 : n;
  }
}

class AnasTvPlayerScreen extends StatefulWidget {
  final List<TvChannel> channels;
  final int initialIndex;
  final bool isTv;

  const AnasTvPlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.isTv,
  });

  @override
  State<AnasTvPlayerScreen> createState() => _AnasTvPlayerScreenState();
}

enum _StbPickerKind { audio, quality, stretch }

class _AnasTvPlayerScreenState extends State<AnasTvPlayerScreen> {
  final FocusNode _playerFocus = FocusNode();

  late int _playingIndex;
  late int _previewIndex;
  late _ChannelEpg _previewEpg;
  late _HindiTrendingItem _trendingItem;

  ResolvedPlayback? _resolved;
  String? _error;
  bool _loading = true;
  bool _isPaused = false;
  bool _isExiting = false;
  bool _bannerVisible = true;
  bool _showNextProgram = false;
  bool _optionsMode = false;
  int _selectedOptionIdx = 0;

  _StbPickerKind? _openPicker;
  List<Map<String, dynamic>> _pickerItems = [];
  int _pickerFocusedIdx = 0;
  bool _pickerLoading = false;

  String _resizeMode = 'fill';
  String _selectedAudioLabel = 'Default';
  String _selectedQualityLabel = 'Auto (Best)';

  MethodChannel? _channel;
  Timer? _watchdog;
  Timer? _bannerAutoHideTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _playRequestSeq = 0;

  TvChannel get _playingChannel => widget.channels[_playingIndex];
  TvChannel get _previewChannel => widget.channels[_previewIndex];

  @override
  void initState() {
    super.initState();
    _playingIndex = widget.initialIndex.clamp(0, widget.channels.length - 1);
    _previewIndex = _playingIndex;
    _previewEpg = _EpgService.fallbackFor(_previewChannel);
    _trendingItem = _EpgService.pickRandomTrending();

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadPreviewEpg(_previewChannel);
    _startChannelStream(_playingIndex);
    _scheduleBannerAutoHide();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (widget.isTv && mounted) {
        _playerFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _bannerAutoHideTimer?.cancel();
    _clockTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    _playerFocus.dispose();
    if (!widget.isTv) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  void _scheduleBannerAutoHide() {
    _bannerAutoHideTimer?.cancel();
    if (_openPicker != null || _error != null) return;
    _bannerAutoHideTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _openPicker != null || _error != null) return;
      setState(() {
        _bannerVisible = false;
        _optionsMode = false;
        _showNextProgram = false;
        _previewIndex = _playingIndex;
        _loadPreviewEpg(_playingChannel);
      });
    });
  }

  void _showBanner({bool resetToPlaying = false, bool openOptions = false}) {
    setState(() {
      if (!_bannerVisible || resetToPlaying) {
        _trendingItem = _EpgService.pickRandomTrending(_trendingItem);
      }
      if (resetToPlaying) {
        _previewIndex = _playingIndex;
        _loadPreviewEpg(_playingChannel);
      }
      _bannerVisible = true;
      _optionsMode = openOptions;
      if (openOptions) _selectedOptionIdx = _selectedOptionIdx.clamp(0, 3);
    });
    _scheduleBannerAutoHide();
  }

  Future<void> _loadPreviewEpg(TvChannel target) async {
    setState(() => _previewEpg = _EpgService.fallbackFor(target));
    final fetched = await _EpgService.fetch(target);
    if (!mounted || _previewChannel.id != target.id) return;
    setState(() => _previewEpg = fetched);
  }

  Future<void> _startChannelStream(int targetIndex) async {
    final reqId = ++_playRequestSeq;
    final target = widget.channels[targetIndex];

    _watchdog?.cancel();
    setState(() {
      _playingIndex = targetIndex;
      _previewIndex = targetIndex;
      _loading = true;
      _error = null;
      _isPaused = false;
      _optionsMode = false;
      _openPicker = null;
      _selectedAudioLabel = 'Default';
      _selectedQualityLabel = 'Auto (Best)';
    });
    _loadPreviewEpg(target);

    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || reqId != _playRequestSeq || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Playback timeout (25s). Stream respond nahi kar rahi.';
      });
    });

    try {
      final resolved = await StreamResolver.resolve(target);
      if (!mounted || reqId != _playRequestSeq) return;
      _resolved = resolved;
      _sendPlayIfReady();
    } catch (e) {
      if (!mounted || reqId != _playRequestSeq) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _created(int id) {
    if (_channel != null) return;
    final ch = MethodChannel('anas_tv/media3_player_$id');
    _channel = ch;

    ch.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onStateChanged') {
        final state = (call.arguments ?? 'unknown').toString();
        setState(() => _loading = state == 'idle' || state == 'buffering');
        if (state == 'ready' || state == 'ended') {
          _watchdog?.cancel();
          _channel?.invokeMethod('setResizeMode', _resizeMode);
        }
      } else if (call.method == 'onError') {
        _watchdog?.cancel();
        setState(() {
          _loading = false;
          _error = (call.arguments ?? 'Native player reported an error').toString();
        });
      }
    });

    ch.invokeMethod('setResizeMode', _resizeMode);
    _sendPlayIfReady();
  }

  void _sendPlayIfReady() {
    final ch = _channel;
    final pb = _resolved;
    if (ch == null || pb == null) return;

    ch.invokeMethod('play', {
      'streamUrl': pb.streamUrl,
      'headers': pb.headers,
      'drmLicenseUrl': pb.drmLicenseUrl,
      'clearKeys': pb.clearKeys,
    }).catchError((Object e) {
      if (!mounted) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = 'Native player start failed: $e';
      });
    });
  }

  void _stepPreviewChannel(int delta) {
    if (widget.channels.isEmpty) return;
    final nextIdx = (_previewIndex + delta + widget.channels.length) % widget.channels.length;
    setState(() {
      _bannerVisible = true;
      _optionsMode = false;
      _previewIndex = nextIdx;
      _trendingItem = _EpgService.pickRandomTrending(_trendingItem);
    });
    _loadPreviewEpg(widget.channels[nextIdx]);
    _scheduleBannerAutoHide();
  }

  Future<void> _openTrackPicker(_StbPickerKind kind) async {
    _bannerAutoHideTimer?.cancel();
    setState(() {
      _bannerVisible = true;
      _optionsMode = true;
      _openPicker = kind;
      _pickerLoading = true;
      _pickerItems = [];
      _pickerFocusedIdx = 0;
    });

    List<Map<String, dynamic>> items = [];
    if (kind == _StbPickerKind.stretch) {
      items = [
        {'id': 'fill', 'label': 'Stretched (Full Screen)', 'selected': _resizeMode == 'fill'},
        {'id': 'fit', 'label': 'Fit (Original Aspect)', 'selected': _resizeMode == 'fit'},
        {'id': 'zoom', 'label': 'Zoom (Fill & Crop)', 'selected': _resizeMode == 'zoom'},
      ];
    } else if (kind == _StbPickerKind.audio) {
      try {
        final raw = await _channel?.invokeMethod<List<dynamic>>('getAudioTracks') ?? [];
        items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
      if (items.isEmpty) {
        items = [
          {'groupIndex': -1, 'trackIndex': -1, 'label': 'Default Stream Audio', 'selected': true},
        ];
      }
    } else if (kind == _StbPickerKind.quality) {
      try {
        final raw = await _channel?.invokeMethod<List<dynamic>>('getVideoQualities') ?? [];
        items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
      if (items.isEmpty) {
        items = [
          {'groupIndex': -1, 'trackIndex': -1, 'label': 'Auto (Best)', 'selected': true},
        ];
      }
    }

    if (!mounted || _openPicker != kind) return;
    final selectedIdx = items.indexWhere((e) => e['selected'] == true);
    setState(() {
      _pickerItems = items;
      _pickerFocusedIdx = selectedIdx >= 0 ? selectedIdx : 0;
      _pickerLoading = false;
    });
  }

  Future<void> _applyPickerSelection(int idx) async {
    if (idx < 0 || idx >= _pickerItems.length || _openPicker == null) return;
    final kind = _openPicker!;
    final item = _pickerItems[idx];

    if (kind == _StbPickerKind.stretch) {
      final mode = (item['id'] ?? 'fill').toString();
      await _channel?.invokeMethod('setResizeMode', mode);
      if (!mounted) return;
      setState(() {
        _resizeMode = mode;
        _openPicker = null;
      });
    } else if (kind == _StbPickerKind.audio) {
      final g = (item['groupIndex'] as num?)?.toInt() ?? -1;
      final t = (item['trackIndex'] as num?)?.toInt() ?? -1;
      await _channel?.invokeMethod('setAudioTrack', {'groupIndex': g, 'trackIndex': t});
      if (!mounted) return;
      setState(() {
        _selectedAudioLabel = (item['label'] ?? 'Audio').toString();
        _openPicker = null;
      });
    } else if (kind == _StbPickerKind.quality) {
      final g = (item['groupIndex'] as num?)?.toInt() ?? -1;
      final t = (item['trackIndex'] as num?)?.toInt() ?? -1;
      await _channel?.invokeMethod('setVideoQuality', {'groupIndex': g, 'trackIndex': t});
      if (!mounted) return;
      setState(() {
        _selectedQualityLabel = (item['label'] ?? 'Auto').toString();
        _openPicker = null;
      });
    }
    _scheduleBannerAutoHide();
  }

  Future<void> _togglePlayPause() async {
    final nextPaused = !_isPaused;
    await _channel?.invokeMethod(nextPaused ? 'pause' : 'resume');
    if (!mounted) return;
    setState(() => _isPaused = nextPaused);
    _scheduleBannerAutoHide();
  }

  void _triggerOption(int optionIdx) {
    setState(() => _selectedOptionIdx = optionIdx);
    switch (optionIdx) {
      case 0:
        _openTrackPicker(_StbPickerKind.audio);
        break;
      case 1:
        _openTrackPicker(_StbPickerKind.quality);
        break;
      case 2:
        _openTrackPicker(_StbPickerKind.stretch);
        break;
      case 3:
        _togglePlayPause();
        break;
    }
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _watchdog?.cancel();
    _bannerAutoHideTimer?.cancel();
    if (!widget.isTv) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (_openPicker != null) {
      setState(() => _openPicker = null);
      _scheduleBannerAutoHide();
      return;
    }
    if (_optionsMode) {
      setState(() => _optionsMode = false);
      _scheduleBannerAutoHide();
      return;
    }
    if (_bannerVisible && _error == null) {
      setState(() {
        _bannerVisible = false;
        _showNextProgram = false;
        _previewIndex = _playingIndex;
        _loadPreviewEpg(_playingChannel);
      });
      _bannerAutoHideTimer?.cancel();
      return;
    }
    await _exitPlayer();
  }

  bool _isMenuKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.contextMenu ||
      key == LogicalKeyboardKey.info ||
      key == LogicalKeyboardKey.guide ||
      key == LogicalKeyboardKey.f1 ||
      key == LogicalKeyboardKey.keyM ||
      key == LogicalKeyboardKey.appSwitch;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.isTv) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _showBanner(openOptions: true);
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _handleBack();
      return KeyEventResult.handled;
    }

    if (_openPicker != null) {
      if (key == LogicalKeyboardKey.arrowUp && _pickerItems.isNotEmpty) {
        setState(() {
          _pickerFocusedIdx = (_pickerFocusedIdx - 1 + _pickerItems.length) % _pickerItems.length;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && _pickerItems.isNotEmpty) {
        setState(() {
          _pickerFocusedIdx = (_pickerFocusedIdx + 1) % _pickerItems.length;
        });
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          event is KeyDownEvent) {
        _applyPickerSelection(_pickerFocusedIdx);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_isMenuKey(key) && event is KeyDownEvent) {
      if (_bannerVisible && _optionsMode) {
        setState(() => _optionsMode = false);
        _scheduleBannerAutoHide();
      } else {
        _showBanner(openOptions: true);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _togglePlayPause();
        _showBanner();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.channelUp) {
      _stepPreviewChannel(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      _stepPreviewChannel(-1);
      return KeyEventResult.handled;
    }

    if (_optionsMode) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() => _selectedOptionIdx = (_selectedOptionIdx - 1 + 4) % 4);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        setState(() => _selectedOptionIdx = (_selectedOptionIdx + 1) % 4);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _optionsMode = false);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          event is KeyDownEvent) {
        _triggerOption(_selectedOptionIdx);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _stepPreviewChannel(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _stepPreviewChannel(1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
      }
      setState(() => _showNextProgram = false);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
      }
      setState(() => _showNextProgram = true);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if ((key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent) {
      if (_error != null) {
        _startChannelStream(_previewIndex);
        return KeyEventResult.handled;
      }
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
      } else if (_previewIndex != _playingIndex) {
        _startChannelStream(_previewIndex);
        _scheduleBannerAutoHide();
      } else {
        _showBanner(openOptions: true);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _clockHeaderText() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h24 = _now.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final min = _now.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'pm' : 'am';
    return '$h12:$min $ampm | ${months[_now.month - 1]} ${_now.day}';
  }

  String _resizeModeShort() {
    switch (_resizeMode) {
      case 'fit':
        return 'Fit';
      case 'zoom':
        return 'Zoom';
      default:
        return 'Stretched';
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewCh = _previewChannel;
    final isPreviewDifferent = _previewIndex != _playingIndex;
    final activeProgram = _showNextProgram ? _previewEpg.next : _previewEpg.live;
    final screenW = MediaQuery.sizeOf(context).width;
    final compactLayout = screenW < 720;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _playerFocus,
          autofocus: widget.isTv,
          onKeyEvent: widget.isTv ? _onKeyEvent : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_openPicker != null) {
                setState(() => _openPicker = null);
                _scheduleBannerAutoHide();
              } else if (_bannerVisible) {
                setState(() {
                  _bannerVisible = false;
                  _optionsMode = false;
                });
                _bannerAutoHideTimer?.cancel();
              } else {
                _showBanner(resetToPlaying: true);
              }
            },
            onLongPress: () => _showBanner(openOptions: true),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlatformViewLink(
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
                      creationParams: const <String, dynamic>{},
                      creationParamsCodec: const StandardMessageCodec(),
                      onFocus: () => params.onFocusChanged(true),
                    )
                      ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                      ..addOnPlatformViewCreatedListener(_created)
                      ..create();
                  },
                ),
                if (_loading) const Center(child: _BrandCircularLoader(size: 84)),
                if (_error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xE6101218),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x40FFFFFF)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFE65312), size: 38),
                          const SizedBox(height: 10),
                          SelectableText(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65312)),
                                onPressed: () => _startChannelStream(_previewIndex),
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _exitPlayer,
                                child: const Text('Back to channels'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_bannerVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        compactLayout ? 14 : 24,
                        compactLayout ? 10 : 14,
                        compactLayout ? 14 : 24,
                        18,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xBF000000), Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            if (!widget.isTv) ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _exitPlayer,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _clockHeaderText(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (_isPaused)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65312),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'PAUSED',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_bannerVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _scheduleBannerAutoHide,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          compactLayout ? 12 : 22,
                          14,
                          compactLayout ? 12 : 22,
                          compactLayout ? 10 : 14,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00090B10),
                              Color(0xD60C0E14),
                              Color(0xF208090D),
                            ],
                            stops: [0.0, 0.18, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _stepPreviewChannel(-1),
                                    borderRadius: BorderRadius.circular(14),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_previewIndex + 101}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      previewCh.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => _stepPreviewChannel(1),
                                    borderRadius: BorderRadius.circular(14),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                  if (isPreviewDifferent) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _startChannelStream(_previewIndex),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE65312),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          widget.isTv ? 'OK to Watch' : 'Watch Channel',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (previewCh.hd) ...[
                                    _StbBadge(text: 'HD'),
                                    const SizedBox(width: 6),
                                  ],
                                  _StbBadge(text: _resizeModeShort().toUpperCase()),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showBanner(openOptions: !_optionsMode),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _optionsMode
                                            ? const Color(0xFFE65312)
                                            : Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.tune_rounded,
                                            size: 13,
                                            color: _optionsMode ? Colors.white : Colors.black,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Options',
                                            style: TextStyle(
                                              color: _optionsMode ? Colors.white : Colors.black,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (!compactLayout) ...[
                                    _HindiTrendingCard(
                                      item: _trendingItem,
                                      onTap: () {
                                        setState(() {
                                          _trendingItem = _EpgService.pickRandomTrending(_trendingItem);
                                        });
                                        _scheduleBannerAutoHide();
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _optionsMode = false;
                                            _showNextProgram = false;
                                          });
                                          _scheduleBannerAutoHide();
                                        },
                                        child: Icon(
                                          Icons.arrow_drop_up_rounded,
                                          size: 22,
                                          color: !_showNextProgram && !_optionsMode
                                              ? const Color(0xFFE65312)
                                              : Colors.white54,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _optionsMode = false;
                                            _showNextProgram = true;
                                          });
                                          _scheduleBannerAutoHide();
                                        },
                                        child: Icon(
                                          Icons.arrow_drop_down_rounded,
                                          size: 22,
                                          color: _showNextProgram && !_optionsMode
                                              ? const Color(0xFFE65312)
                                              : Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: compactLayout ? 86 : 112,
                                    height: compactLayout ? 56 : 68,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isPreviewDifferent
                                            ? const Color(0xFFE65312)
                                            : Colors.white24,
                                        width: isPreviewDifferent ? 2 : 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    padding: const EdgeInsets.all(6),
                                    child: _ChannelLogo(
                                      primaryUrl: previewCh.logo,
                                      fallbackUrl: previewCh.fallbackLogo,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _optionsMode
                                        ? _buildStbOptionsBar()
                                        : _buildStbProgramDetails(activeProgram),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  value: _showNextProgram ? 0.0 : _previewEpg.live.progress,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                                ),
                              ),
                              if (!_optionsMode) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _showNextProgram
                                            ? const Color(0xFF2B303B)
                                            : const Color(0xFFE65312),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _showNextProgram ? 'NOW' : 'NEXT',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _showNextProgram
                                            ? '${_previewEpg.live.title}  (${_previewEpg.live.timeLabel})'
                                            : '${_previewEpg.next.title}  (${_previewEpg.next.timeLabel})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (compactLayout) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _trendingItem.accent.withValues(alpha: 0.85),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _trendingItem.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_openPicker != null) _buildStbTrackPickerOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStbProgramDetails(_StbProgram program) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _showNextProgram ? const Color(0xFF1E88E5) : const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _showNextProgram ? 'UP NEXT' : 'LIVE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                program.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          program.timeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD5D8E0),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          program.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFB6BAC4),
            fontSize: 11.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildStbOptionsBar() {
    final options = [
      (Icons.audiotrack_rounded, 'Audio', _selectedAudioLabel),
      (Icons.hd_rounded, 'Quality', _selectedQualityLabel),
      (Icons.aspect_ratio_rounded, 'Stretch', _resizeModeShort()),
      (_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, _isPaused ? 'Play' : 'Pause', _isPaused ? 'Resume' : 'Pause'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(options.length, (i) {
        final selected = _selectedOptionIdx == i;
        final item = options[i];
        return Padding(
          padding: const EdgeInsets.only(right: 18),
          child: InkWell(
            onTap: () => _triggerOption(i),
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  width: selected ? 44 : 38,
                  height: selected ? 44 : 38,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFE65312) : const Color(0xCC222630),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 1.8 : 1,
                    ),
                  ),
                  child: Icon(
                    item.$1,
                    color: Colors.white,
                    size: selected ? 22 : 19,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFBFC4CF),
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  item.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? const Color(0xFFFFB74D) : Colors.white54,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
      ),
    );
  }

  Widget _buildStbTrackPickerOverlay() {
    final kind = _openPicker!;
    final title = kind == _StbPickerKind.audio
        ? 'Audio Track'
        : kind == _StbPickerKind.quality
            ? 'Video Quality'
            : 'Screen Stretch Mode';

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xF511141C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (!widget.isTv)
                    InkWell(
                      onTap: () {
                        setState(() => _openPicker = null);
                        _scheduleBannerAutoHide();
                      },
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_pickerLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFE65312), strokeWidth: 2.5),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _pickerItems.length,
                    itemBuilder: (context, idx) {
                      final item = _pickerItems[idx];
                      final focused = idx == _pickerFocusedIdx;
                      final active = item['selected'] == true;
                      return InkWell(
                        onTap: () => _applyPickerSelection(idx),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: focused
                                ? const Color(0xFFE65312)
                                : const Color(0xFF1A1E29),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (item['label'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: focused || active ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (active)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: focused ? Colors.white : const Color(0xFFE65312),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StbBadge extends StatelessWidget {
  final String text;
  const _StbBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _HindiTrendingCard extends StatelessWidget {
  final _HindiTrendingItem item;
  final VoidCallback onTap;

  const _HindiTrendingCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 158,
        height: 70,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              item.accent.withValues(alpha: 0.92),
              const Color(0xFF10131A),
            ],
          ),
          border: Border.all(color: Colors.white24, width: 0.9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(item.icon, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.badge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final TvChannel channel;
  final bool isTv;
  final bool autofocus;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.isTv,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool focused = false;
  bool hovered = false;

  void _ensureVisible() {
    final ro = context.findRenderObject();
    if (ro == null || !ro.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;
    final pos = scrollable.position;
    final topOffset = viewport.getOffsetToReveal(ro, 0.0).offset - 14.0;
    final bottomOffset = viewport.getOffsetToReveal(ro, 1.0).offset + 14.0;
    if (pos.pixels < bottomOffset) {
      pos.animateTo(
        bottomOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    } else if (pos.pixels > topOffset) {
      pos.animateTo(
        topOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTvFocus = widget.isTv && (focused || hovered);
    final cardColor = showTvFocus ? const Color(0xFFE65312) : const Color(0xFF080808);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final logoSize = math.min(w * 0.68, h * 0.65);
      final nameSize = (w * 0.13).clamp(9.0, 16.0).toDouble();
      return AnimatedScale(
        scale: showTvFocus ? 1.16 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOut,
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: widget.isTv,
          onKeyEvent: widget.onKeyEvent,
          onFocusChange: (value) {
            if (widget.isTv) {
              setState(() => focused = value);
              if (value) _ensureVisible();
            }
          },
          child: MouseRegion(
            onEnter: (_) {
              if (widget.isTv) setState(() => hovered = true);
            },
            onExit: (_) {
              if (widget.isTv) setState(() => hovered = false);
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
                decoration: BoxDecoration(
                  color: cardColor,
                  border: showTvFocus
                      ? null
                      : Border.all(color: const Color(0xFFD94B0A), width: 1.1),
                  borderRadius: BorderRadius.circular(8),
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
                            color: showTvFocus ? Colors.white : const Color(0xFFD94B0A),
                            width: 1.1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        padding: EdgeInsets.all(logoSize * 0.08),
                        child: _ChannelLogo(
                          primaryUrl: widget.channel.logo,
                          fallbackUrl: widget.channel.fallbackLogo,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: nameSize * 1.38,
                      width: double.infinity,
                      child: Center(
                        child: _ChannelMarquee(
                          text: widget.channel.name,
                          animate: !widget.isTv || showTvFocus,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: nameSize,
                            height: 1.05,
                            fontWeight: showTvFocus ? FontWeight.w700 : FontWeight.w500,
                            fontFamily: 'Roboto',
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
  final bool animate;

  const _ChannelMarquee({
    required this.text,
    required this.style,
    this.animate = true,
  });

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
    if (oldWidget.text != widget.text || (!widget.animate && _running)) {
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
    if (!widget.animate) {
      return Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: widget.style,
      );
    }

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
    if (url.isEmpty) return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Colors.grey));
    return Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: 160,
      cacheHeight: 160,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        if (!fallback && widget.fallbackUrl.isNotEmpty && widget.fallbackUrl != widget.primaryUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => fallback = true);
          });
        }
        return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Colors.grey));
      },
    );
  }
}
