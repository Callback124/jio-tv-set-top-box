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
        _openChannel(filtered[index], restoreCardIndex: index);
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

  void _openChannel(TvChannel channel, {int? restoreCardIndex}) {
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(channel: channel, isTv: widget.isTv),
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
              onTap: () => _openChannel(filtered[index], restoreCardIndex: index),
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
        _openChannel(results[index], restoreCardIndex: index);
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

  void _openChannel(TvChannel channel, {int? restoreCardIndex}) {
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(channel: channel, isTv: widget.isTv),
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
                                        _openChannel(results[index], restoreCardIndex: index),
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

class AnasTvPlayerScreen extends StatefulWidget {
  final TvChannel channel;
  final bool isTv;

  const AnasTvPlayerScreen({
    super.key,
    required this.channel,
    required this.isTv,
  });

  @override
  State<AnasTvPlayerScreen> createState() => _AnasTvPlayerScreenState();
}

class _AnasTvPlayerScreenState extends State<AnasTvPlayerScreen> {
  final FocusNode _playerFocus = FocusNode();
  final FocusNode _backFocus = FocusNode(canRequestFocus: false);

  ResolvedPlayback? _resolved;
  String? _error;
  bool _loading = true;
  bool _isExiting = false;
  MethodChannel? _channel;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _resolveAndStart();
    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Playback timeout (25s). Stream respond nahi kar rahi.';
      });
    });

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
    _channel?.setMethodCallHandler(null);
    _playerFocus.dispose();
    _backFocus.dispose();
    if (!widget.isTv) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  Future<void> _resolveAndStart() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resolved = await StreamResolver.resolve(widget.channel);
      if (!mounted) return;
      _resolved = resolved;
      _sendPlayIfReady();
    } catch (e) {
      if (!mounted) return;
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
        if (state == 'ready' || state == 'ended') _watchdog?.cancel();
      } else if (call.method == 'onError') {
        _watchdog?.cancel();
        setState(() {
          _loading = false;
          _error = (call.arguments ?? 'Native player reported an error').toString();
        });
      }
    });

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

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _watchdog?.cancel();
    if (!widget.isTv) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (widget.isTv) {
      final visible = await _channel?.invokeMethod<bool>('isControllerVisible') ?? false;
      if (visible) {
        await _channel?.invokeMethod('hideController');
        if (mounted) _playerFocus.requestFocus();
        return;
      }
    }
    await _exitPlayer();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      _handleBack();
      return KeyEventResult.handled;
    }

    int? androidKeyCode;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      androidKeyCode = 23; // KEYCODE_DPAD_CENTER
    } else if (key == LogicalKeyboardKey.arrowUp) {
      androidKeyCode = 19; // KEYCODE_DPAD_UP
    } else if (key == LogicalKeyboardKey.arrowDown) {
      androidKeyCode = 20; // KEYCODE_DPAD_DOWN
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      androidKeyCode = 21; // KEYCODE_DPAD_LEFT
    } else if (key == LogicalKeyboardKey.arrowRight) {
      androidKeyCode = 22; // KEYCODE_DPAD_RIGHT
    } else if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.space) {
      androidKeyCode = 85; // KEYCODE_MEDIA_PLAY_PAUSE
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      androidKeyCode = 90;
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      androidKeyCode = 89;
    }

    if (androidKeyCode != null) {
      _channel?.invokeMethod('dispatchKey', androidKeyCode);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              PlatformViewLink(
                key: ValueKey(widget.channel.id),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange, size: 38),
                        const SizedBox(height: 12),
                        SelectableText(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _exitPlayer,
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
                        focusNode: _backFocus,
                        onPressed: _exitPlayer,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
