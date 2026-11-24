import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'pc_models.dart';
import 'pc_mpv_player_view.dart';
import 'pc_shaka_player_view.dart';
import 'pc_trace_log.dart';

class AnasTvPcApp extends StatelessWidget {
  const AnasTvPcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const AnasTvPcHomePage(),
    );
  }
}

class AnasTvPcHomePage extends StatefulWidget {
  const AnasTvPcHomePage({super.key});

  @override
  State<AnasTvPcHomePage> createState() => _AnasTvPcHomePageState();
}

class _AnasTvPcHomePageState extends State<AnasTvPcHomePage> {
  static const extraUrl = 'https://api.npoint.io/9db02feba76eb297fc65';
  static const jioHeaders = PcEpgService.jioHeaders;

  final ScrollController _tabScroll = ScrollController();
  final ScrollController _gridScroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _pageFocus = FocusNode();

  List<PcChannel> allChannels = [];
  List<String> filterTabs = const ['ALL'];
  String selectedTab = 'ALL';
  String _searchQuery = '';
  bool loading = true;
  String? error;
  final List<String> _debugErrors = [];

  String _typedDigits = '';
  String? _digitOsdError;
  Timer? _digitCommitTimer;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _digitCommitTimer?.cancel();
    _tabScroll.dispose();
    _gridScroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  int _int(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  String _category(int id) {
    switch (id) {
      case 5:
        return 'Entertainment';
      case 6:
        return 'Movies';
      case 7:
        return 'Kids';
      case 8:
        return 'Sports';
      case 9:
        return 'Lifestyle';
      case 10:
        return 'Infotainment';
      case 12:
        return 'News';
      case 13:
        return 'Music';
      case 15:
        return 'Devotional';
      case 16:
        return 'Business';
      case 17:
        return 'Educational';
      case 18:
        return 'Shopping';
      case 19:
        return 'JioDarshan';
      default:
        return 'Entertainment';
    }
  }

  (String, String) _logoUrls(String raw) {
    var clean = raw.trim().replaceAll(r'\/', '/');
    if (clean.isEmpty || clean == 'null') return ('', '');
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return (clean, clean);
    }
    if (clean.startsWith('//')) {
      final url = 'https:$clean';
      return (url, url);
    }
    final withoutLeading = clean.startsWith('/') ? clean.substring(1) : clean;
    final cleanPath = withoutLeading.replaceFirst(RegExp(r'^images/'), '');
    final p1 = 'https://jiotvimages.cdn.jio.com/dare_images/images/$cleanPath';
    final p2 = 'https://jiotv.catchup.cdn.jio.com/dare_images/images/$cleanPath';
    return (p1, p2);
  }

  Future<List<PcChannel>> _fetchJio() async {
    const urls = [
      'https://jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
      'https://jiotv.data.cdn.jio.com/apis/v3.0/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: jioHeaders)
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
              return PcChannel(
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

  Future<(List<PcChannel>, List<String>)> _fetchExtra() async {
    try {
      final response = await http.get(
        Uri.parse(extraUrl),
        headers: const {'Accept': 'application/json', 'User-Agent': PcStreamResolver.defaultUa},
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        _debugErrors.add('npoint API HTTP ${response.statusCode}');
        return (<PcChannel>[], <String>[]);
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

      final result = <PcChannel>[];
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
        var rawLogo = pick([
          'channel_logo',
          'channelLogo',
          'logo_url',
          'logoUrl',
          'logo',
          'tvg_logo',
          'tvgLogo',
          'image',
          'channel_image',
          'channel_img',
          'img',
          'icon',
          'poster',
          'thumbnail',
          'pic',
        ]);
        if (rawLogo.isEmpty) {
          for (final entry in j.entries) {
            final k = entry.key.toLowerCase();
            if (k.contains('logo') || k.contains('icon') || k.contains('img') || k.contains('image')) {
              final v = (entry.value ?? '').toString().trim();
              if (v.isNotEmpty && v != 'null') {
                rawLogo = v;
                break;
              }
            }
          }
        }
        final logos = _logoUrls(rawLogo);
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

        result.add(PcChannel(
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
      return (<PcChannel>[], <String>[]);
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

      final merged = <int, PcChannel>{};
      for (final channel in jioList) {
        merged.putIfAbsent(channel.id, () => channel);
      }
      for (final extra in extraList) {
        final old = merged[extra.id];
        if (old == null) {
          merged[extra.id] = extra;
        } else {
          merged[extra.id] = PcChannel(
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

      final exactEpgMap = <String, PcChannel>{};
      final sdEpgMap = <String, PcChannel>{};
      final langSdEpgMap = <String, PcChannel>{};
      final baseEpgMap = <String, PcChannel>{};
      final langBaseEpgMap = <String, PcChannel>{};
      final exactLogoMap = <String, PcChannel>{};
      final sdLogoMap = <String, PcChannel>{};
      final langSdLogoMap = <String, PcChannel>{};
      final baseLogoMap = <String, PcChannel>{};
      final langBaseLogoMap = <String, PcChannel>{};

      void putLogoCandidate(Map<String, PcChannel> map, String key, PcChannel ch) {
        if (key.isEmpty) return;
        final cur = map[key];
        if (cur == null || (cur.id >= 1000000 && ch.id < 1000000)) {
          map[key] = ch;
        }
      }

      for (final ch in sorted) {
        final ek = PcChannelMatcher.exactKey(ch.name);
        final sk = PcChannelMatcher.sdEquivKey(ch.name);
        final lk = PcChannelMatcher.langNeutralSdKey(ch.name);
        final bk = PcChannelMatcher.baseKey(ch.name);
        final lbk = PcChannelMatcher.langNeutralBaseKey(ch.name);
        if (ch.id < 1000000) {
          if (ek.isNotEmpty) exactEpgMap.putIfAbsent(ek, () => ch);
          if (sk.isNotEmpty) sdEpgMap.putIfAbsent(sk, () => ch);
          if (lk.isNotEmpty) langSdEpgMap.putIfAbsent(lk, () => ch);
          if (bk.isNotEmpty) baseEpgMap.putIfAbsent(bk, () => ch);
          if (lbk.isNotEmpty) langBaseEpgMap.putIfAbsent(lbk, () => ch);
        }
        if (ch.logo.trim().isNotEmpty) {
          putLogoCandidate(exactLogoMap, ek, ch);
          putLogoCandidate(sdLogoMap, sk, ch);
          putLogoCandidate(langSdLogoMap, lk, ch);
          putLogoCandidate(baseLogoMap, bk, ch);
          putLogoCandidate(langBaseLogoMap, lbk, ch);
        }
      }

      PcChannel? findMatch(
        PcChannel target,
        Map<String, PcChannel> exactMap,
        Map<String, PcChannel> sdMap,
        Map<String, PcChannel> langSdMap,
        Map<String, PcChannel> baseMap,
        Map<String, PcChannel> langBaseMap,
      ) {
        final ek = PcChannelMatcher.exactKey(target.name);
        final sk = PcChannelMatcher.sdEquivKey(target.name);
        final lk = PcChannelMatcher.langNeutralSdKey(target.name);
        final bk = PcChannelMatcher.baseKey(target.name);
        final lbk = PcChannelMatcher.langNeutralBaseKey(target.name);
        for (final m in [
          exactMap[ek],
          sdMap[sk],
          langSdMap[lk],
          baseMap[bk],
          langBaseMap[lbk],
        ]) {
          if (m != null && m.id != target.id) return m;
        }
        return null;
      }

      final enriched = List<PcChannel>.generate(sorted.length, (index) {
        final ch = sorted[index];
        final epgDonor = ch.id >= 1000000
            ? findMatch(ch, exactEpgMap, sdEpgMap, langSdEpgMap, baseEpgMap, langBaseEpgMap)
            : null;
        final logoDonor =
            findMatch(ch, exactLogoMap, sdLogoMap, langSdLogoMap, baseLogoMap, langBaseLogoMap);

        var nextLogo = ch.logo;
        var nextFallback = ch.fallbackLogo;
        if (nextLogo.trim().isEmpty && logoDonor != null) {
          nextLogo = logoDonor.logo;
          nextFallback = logoDonor.fallbackLogo.isNotEmpty ? logoDonor.fallbackLogo : logoDonor.logo;
        } else if (nextLogo.contains('://www.sonypicturesnetworks.com/')) {
          nextFallback = nextLogo.replaceFirst(
            '://www.sonypicturesnetworks.com/',
            '://sonypicturesnetworks.com/',
          );
        }

        return ch.copyWith(
          channelNumber: 101 + index,
          logo: nextLogo,
          fallbackLogo: nextFallback,
          epgChannelId: epgDonor?.id,
          epgChannelName: epgDonor?.name,
        );
      });

      PcEpgService.registerChannels(enriched);

      final tabs = <String>['ALL', ...apiGenres];
      if (!mounted) return;
      setState(() {
        allChannels = enriched;
        filterTabs = tabs;
        if (!tabs.any((t) => t.toLowerCase() == selectedTab.toLowerCase())) {
          selectedTab = 'ALL';
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<PcChannel> get _filteredChannels {
    Iterable<PcChannel> list = allChannels;
    if (selectedTab.toUpperCase() != 'ALL') {
      final target = selectedTab.trim().toLowerCase();
      list = list.where((c) => c.category.trim().toLowerCase() == target);
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where(
        (c) => c.name.toLowerCase().contains(q) || '${c.channelNumber}'.contains(q),
      );
    }
    return list.toList();
  }

  String? _digitFromKeyEvent(KeyEvent event) {
    final l = event.logicalKey;
    final p = event.physicalKey;
    if (l == LogicalKeyboardKey.digit0 || l == LogicalKeyboardKey.numpad0 || p == PhysicalKeyboardKey.digit0 || p == PhysicalKeyboardKey.numpad0) return '0';
    if (l == LogicalKeyboardKey.digit1 || l == LogicalKeyboardKey.numpad1 || p == PhysicalKeyboardKey.digit1 || p == PhysicalKeyboardKey.numpad1) return '1';
    if (l == LogicalKeyboardKey.digit2 || l == LogicalKeyboardKey.numpad2 || p == PhysicalKeyboardKey.digit2 || p == PhysicalKeyboardKey.numpad2) return '2';
    if (l == LogicalKeyboardKey.digit3 || l == LogicalKeyboardKey.numpad3 || p == PhysicalKeyboardKey.digit3 || p == PhysicalKeyboardKey.numpad3) return '3';
    if (l == LogicalKeyboardKey.digit4 || l == LogicalKeyboardKey.numpad4 || p == PhysicalKeyboardKey.digit4 || p == PhysicalKeyboardKey.numpad4) return '4';
    if (l == LogicalKeyboardKey.digit5 || l == LogicalKeyboardKey.numpad5 || p == PhysicalKeyboardKey.digit5 || p == PhysicalKeyboardKey.numpad5) return '5';
    if (l == LogicalKeyboardKey.digit6 || l == LogicalKeyboardKey.numpad6 || p == PhysicalKeyboardKey.digit6 || p == PhysicalKeyboardKey.numpad6) return '6';
    if (l == LogicalKeyboardKey.digit7 || l == LogicalKeyboardKey.numpad7 || p == PhysicalKeyboardKey.digit7 || p == PhysicalKeyboardKey.numpad7) return '7';
    if (l == LogicalKeyboardKey.digit8 || l == LogicalKeyboardKey.numpad8 || p == PhysicalKeyboardKey.digit8 || p == PhysicalKeyboardKey.numpad8) return '8';
    if (l == LogicalKeyboardKey.digit9 || l == LogicalKeyboardKey.numpad9 || p == PhysicalKeyboardKey.digit9 || p == PhysicalKeyboardKey.numpad9) return '9';
    return null;
  }

  String? get _homeDigitPreviewName {
    final numVal = int.tryParse(_typedDigits);
    if (numVal == null) return null;
    final pool = allChannels.isNotEmpty ? allChannels : _filteredChannels;
    final idx = pcResolveChannelIndexByNumber(pool, numVal);
    return idx != null ? pool[idx].name : null;
  }

  void _commitHomeTypedChannel() {
    _digitCommitTimer?.cancel();
    final digits = _typedDigits;
    if (digits.isEmpty) return;
    final number = int.tryParse(digits);
    final pool = allChannels.isNotEmpty ? allChannels : _filteredChannels;
    final idx = number != null ? pcResolveChannelIndexByNumber(pool, number) : null;
    if (idx == null || idx < 0 || idx >= pool.length) {
      setState(() {
        _typedDigits = '';
        _digitOsdError = 'No CH $digits';
      });
      _digitCommitTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _digitOsdError = null);
      });
      return;
    }
    setState(() {
      _typedDigits = '';
      _digitOsdError = null;
    });
    _openChannelPlayer(pool, idx);
  }

  void _openChannelPlayer(List<PcChannel> list, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnasTvPcPlayerScreen(
          channels: list,
          allChannels: allChannels,
          initialIndex: index,
        ),
      ),
    ).then((_) {
      if (mounted && !_searchFocus.hasFocus) {
        _pageFocus.requestFocus();
      }
    });
  }

  KeyEventResult _handlePageKey(FocusNode node, KeyEvent event) {
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final digit = _digitFromKeyEvent(event);
    if (digit != null) {
      _digitCommitTimer?.cancel();
      final nextDigits = _typedDigits.length >= 4 ? digit : '$_typedDigits$digit';
      setState(() {
        _typedDigits = nextDigits;
        _digitOsdError = null;
      });
      _digitCommitTimer = Timer(const Duration(milliseconds: 1450), _commitHomeTypedChannel);
      return KeyEventResult.handled;
    }

    if (_typedDigits.isNotEmpty &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      _commitHomeTypedChannel();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final channels = _filteredChannels;
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Focus(
        focusNode: _pageFocus,
        autofocus: true,
        onKeyEvent: _handlePageKey,
        child: Stack(
          children: [
            Column(
              children: [
                // Desktop top bar
                Container(
                  color: const Color(0xFF0A0C12),
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
                  child: Row(
                    children: [
                      const Text(
                        'AnasTV',
                        style: TextStyle(
                          fontFamily: 'Anton',
                          color: Colors.white,
                          fontSize: 28,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65312).withValues(alpha: 0.16),
                          border: Border.all(color: const Color(0xFFE65312), width: 1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'PC • SHAKA WEB',
                          style: TextStyle(
                            color: Color(0xFFFF8F5C),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Search channel name or number...',
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                          _pageFocus.requestFocus();
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFF141822),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFFE65312)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (allChannels.isNotEmpty)
                        Text(
                          '${channels.length} CH',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Reload channels',
                        onPressed: _loadChannels,
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 21),
                      ),
                    ],
                  ),
                ),

                // Category Tabs
                Container(
                  color: const Color(0xFF0A0C12),
                  height: 44,
                  child: ListView.separated(
                    controller: _tabScroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                    itemCount: filterTabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, idx) {
                      final label = filterTabs[idx];
                      final active = label.toLowerCase() == selectedTab.toLowerCase();
                      return _PcTabPill(
                        label: label,
                        active: active,
                        onTap: () {
                          setState(() => selectedTab = label);
                          if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                        },
                      );
                    },
                  ),
                ),

                Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),

                // Channel Grid
                Expanded(
                  child: loading
                      ? const Center(child: PcBrandCircularLoader(size: 84))
                      : error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.cloud_off_rounded, color: Color(0xFFE65312), size: 46),
                                    const SizedBox(height: 12),
                                    Text(
                                      error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65312)),
                                      onPressed: _loadChannels,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : channels.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No matching channels found.',
                                    style: TextStyle(color: Colors.white54, fontSize: 15),
                                  ),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final w = constraints.maxWidth;
                                    final cols = (w / 145).floor().clamp(3, 12);
                                    return Scrollbar(
                                      controller: _gridScroll,
                                      thumbVisibility: true,
                                      child: GridView.builder(
                                        controller: _gridScroll,
                                        padding: const EdgeInsets.all(18),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          childAspectRatio: 0.96,
                                        ),
                                        itemCount: channels.length,
                                        itemBuilder: (_, idx) {
                                          final ch = channels[idx];
                                          return _PcChannelCard(
                                            channel: ch,
                                            onTap: () => _openChannelPlayer(channels, idx),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),

            if (_typedDigits.isNotEmpty || _digitOsdError != null)
              Positioned(
                top: 66,
                right: 26,
                child: PcStbChannelNumberOsd(
                  digits: _typedDigits,
                  previewChannelName: _homeDigitPreviewName,
                  errorMessage: _digitOsdError,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PcTabPill extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PcTabPill({required this.label, required this.active, required this.onTap});

  @override
  State<_PcTabPill> createState() => _PcTabPillState();
}

class _PcTabPillState extends State<_PcTabPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: widget.active
                ? const Color(0xFFE65312)
                : _hovered
                    ? const Color(0xFF1F2533)
                    : const Color(0xFF131722),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.active
                  ? const Color(0xFFFF8F5C)
                  : _hovered
                      ? Colors.white30
                      : Colors.white12,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PcChannelCard extends StatefulWidget {
  final PcChannel channel;
  final VoidCallback onTap;

  const _PcChannelCard({required this.channel, required this.onTap});

  @override
  State<_PcChannelCard> createState() => _PcChannelCardState();
}

class _PcChannelCardState extends State<_PcChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: LayoutBuilder(builder: (context, c) {
          final logoSize = math.min(c.maxWidth * 0.65, c.maxHeight * 0.62);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.fromLTRB(6, 7, 6, 6),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF1B202C) : const Color(0xFF0D1017),
              border: Border.all(
                color: _hovered ? Colors.white : const Color(0xFFD94B0A),
                width: _hovered ? 1.5 : 1.1,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF5CCFE0),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _hovered ? Colors.white : const Color(0xFFD94B0A),
                        width: 1.1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    padding: EdgeInsets.all(logoSize * 0.08),
                    child: PcChannelLogo(
                      primaryUrl: widget.channel.logo,
                      fallbackUrl: widget.channel.fallbackLogo,
                    ),
                  ),
                ),
                Text(
                  '${widget.channel.channelNumber}  ${widget.channel.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: _hovered ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

enum _PcPickerKind { audio, quality, stretch }

class AnasTvPcPlayerScreen extends StatefulWidget {
  final List<PcChannel> channels;
  final List<PcChannel>? allChannels;
  final int initialIndex;

  const AnasTvPcPlayerScreen({
    super.key,
    required this.channels,
    this.allChannels,
    required this.initialIndex,
  });

  @override
  State<AnasTvPcPlayerScreen> createState() => _AnasTvPcPlayerScreenState();
}

class _AnasTvPcPlayerScreenState extends State<AnasTvPcPlayerScreen> {
  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xCC000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  final FocusNode _playerFocus = FocusNode();
  late final PcShakaPlayerController _shaka;
  PcMpvPlayerController? _mpv;
  bool _useMpvEngine = false;
  bool _fallbackInProgress = false;
  bool _closing = false;
  PcResolvedPlayback? _lastResolvedPlayback;
  late List<PcChannel> _channels;

  late int _playingIndex;
  late int _previewIndex;
  late List<PcProgram> _previewPrograms;
  int _programIndex = 0;

  bool _loading = true;
  bool _isPaused = false;
  bool _muted = false;
  String _resizeMode = 'fill';
  String? _error;

  bool _bannerVisible = true;
  bool _optionsMode = false;
  _PcPickerKind? _openPicker;

  List<Map<String, dynamic>> _videoTracks = [];
  List<Map<String, dynamic>> _audioTracks = [];

  Timer? _watchdog;
  Timer? _bannerAutoHideTimer;
  Timer? _clockTimer;
  Timer? _epgDebounceTimer;
  Timer? _digitCommitTimer;
  String _typedDigits = '';
  String? _digitOsdError;
  DateTime _now = DateTime.now();
  int _playRequestSeq = 0;
  int _lookaheadSeq = 0;

  PcChannel get _playingChannel => _channels[_playingIndex];
  PcChannel get _previewChannel => _channels[_previewIndex];

  PcProgram get _activeProgram {
    if (_previewPrograms.isEmpty) {
      return PcEpgService.fallback48h(_previewChannel).first;
    }
    final idx = _programIndex.clamp(0, _previewPrograms.length - 1);
    return _previewPrograms[idx];
  }

  @override
  void initState() {
    super.initState();
    _channels = widget.channels;
    _playingIndex = widget.initialIndex.clamp(0, _channels.length - 1);
    _previewIndex = _playingIndex;
    _previewPrograms =
        PcEpgService.cachedFor(_previewChannel.id) ?? PcEpgService.fallback48h(_previewChannel);

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _shaka = PcShakaPlayerController(
      onViewReady: () {
        if (mounted) setState(() {});
      },
      onStateChanged: (state) {
        if (!mounted || _useMpvEngine) return;
        final isBuffering = state == 'idle' || state == 'buffering';
        if (_loading != isBuffering) setState(() => _loading = isBuffering);
        if (state == 'ready' || state == 'ended') _watchdog?.cancel();
      },
      onTracksChanged: (videos, audios) {
        if (!mounted || _useMpvEngine) return;
        setState(() {
          _videoTracks = videos;
          _audioTracks = audios;
        });
      },
      onHevcUnsupported: (diag) {
        PcTraceLog.write('ui: onHevcUnsupported channel=${_playingChannel.name} diag=$diag');
        if (!mounted || _closing || _useMpvEngine || _fallbackInProgress) return;
        _fallbackToMpv();
      },
      onError: (msg) {
        if (!mounted || _useMpvEngine) return;
        _watchdog?.cancel();
        setState(() {
          _loading = false;
          _error = msg;
        });
      },
    );

    _shaka.init();
    _loadPreviewAndNeighbors(_previewIndex, immediateFetch: true);
    _startChannelStream(_playingIndex, showBanner: true);
  }

  PcMpvPlayerController _ensureMpv() {
    final existing = _mpv;
    if (existing != null) return existing;
    final ctrl = PcMpvPlayerController(
      onViewReady: () {
        if (mounted) setState(() {});
      },
      onStateChanged: (state) {
        if (!mounted || !_useMpvEngine) return;
        final isBuffering = state == 'idle' || state == 'buffering';
        if (_loading != isBuffering) setState(() => _loading = isBuffering);
        if (state == 'ready' || state == 'ended') _watchdog?.cancel();
      },
      onTracksChanged: (videos, audios) {
        if (!mounted || !_useMpvEngine) return;
        setState(() {
          _videoTracks = videos;
          _audioTracks = audios;
        });
      },
      onError: (msg) {
        if (!mounted || !_useMpvEngine) return;
        _watchdog?.cancel();
        setState(() {
          _loading = false;
          _error = msg;
        });
      },
    );
    _mpv = ctrl;
    return ctrl;
  }

  Future<void> _fallbackToMpv() async {
    final resolved = _lastResolvedPlayback;
    if (!mounted || _closing || _useMpvEngine || _fallbackInProgress || resolved == null) return;
    _fallbackInProgress = true;
    final reqSeq = _playRequestSeq;
    PcTraceLog.write('ui: _fallbackToMpv start url=${resolved.streamUrl}');
    try {
      await _shaka.stop().catchError((_) {});
      if (!mounted || _closing || reqSeq != _playRequestSeq) return;

      final mpv = _ensureMpv();
      await mpv.init();
      if (!mounted || _closing || reqSeq != _playRequestSeq) return;

      mpv.setResizeMode(_resizeMode);
      await mpv.setVolume(1.0, muted: _muted);
      setState(() {
        _useMpvEngine = true;
        _loading = true;
        _error = null;
        _videoTracks = [];
        _audioTracks = [];
      });

      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 28), () {
        if (!mounted || reqSeq != _playRequestSeq || !_loading) return;
        setState(() {
          _loading = false;
          _error = 'HEVC playback timeout (28s). Stream respond nahi kar rahi.';
        });
      });

      await mpv.play(resolved);
    } catch (e) {
      PcTraceLog.write('ui: _fallbackToMpv error $e');
      if (!mounted || reqSeq != _playRequestSeq) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = 'HEVC playback failed: $e';
      });
    } finally {
      _fallbackInProgress = false;
    }
  }

  void _closePlayer() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _lookaheadSeq++;
    _watchdog?.cancel();
    _bannerAutoHideTimer?.cancel();
    _clockTimer?.cancel();
    _epgDebounceTimer?.cancel();
    _digitCommitTimer?.cancel();
    _playerFocus.dispose();
    _shaka.dispose();
    _mpv?.dispose();
    super.dispose();
  }

  void _scheduleBannerAutoHide() {
    _bannerAutoHideTimer?.cancel();
    if (_openPicker != null || _error != null) return;
    _bannerAutoHideTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || _openPicker != null || _error != null) return;
      setState(() {
        _bannerVisible = false;
        _optionsMode = false;
        _programIndex = 0;
        _previewIndex = _playingIndex;
      });
    });
  }

  void _showBanner({bool resetToPlaying = false, bool openOptions = false}) {
    setState(() {
      if (resetToPlaying) {
        _previewIndex = _playingIndex;
        _programIndex = 0;
      }
      _bannerVisible = true;
      _optionsMode = openOptions;
    });
    if (resetToPlaying) {
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
    }
    _scheduleBannerAutoHide();
  }

  void _loadPreviewAndNeighbors(int targetIdx, {bool immediateFetch = false}) {
    _epgDebounceTimer?.cancel();
    final seq = ++_lookaheadSeq;
    final target = _channels[targetIdx];

    final cached = PcEpgService.cachedFor(target.id);
    setState(() {
      _previewPrograms =
          (cached != null && cached.isNotEmpty) ? cached : PcEpgService.fallback48h(target);
      _programIndex = 0;
    });

    Future<void> syncCurrent() async {
      if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
      var programs = (cached != null && cached.isNotEmpty)
          ? cached
          : await PcEpgService.fetchOffset(target, offset: 0);
      if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
      if (programs.length < 2 && !PcEpgService.hasOffset(target.id, 1)) {
        programs = await PcEpgService.fetchOffset(target, offset: 1);
        if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
      }
      if (programs.isNotEmpty) {
        setState(() {
          _previewPrograms = programs;
          if (_programIndex >= programs.length) _programIndex = 0;
        });
      }
    }

    if (immediateFetch || (cached != null && cached.isNotEmpty)) {
      syncCurrent();
    } else {
      _epgDebounceTimer = Timer(const Duration(milliseconds: 140), syncCurrent);
    }
  }

  Future<void> _startChannelStream(int targetIndex, {bool showBanner = false}) async {
    final reqId = ++_playRequestSeq;
    final target = _channels[targetIndex];
    _watchdog?.cancel();
    _lastResolvedPlayback = null;
    _fallbackInProgress = false;
    if (_useMpvEngine) {
      await _mpv?.stop().catchError((_) {});
    }

    setState(() {
      _playingIndex = targetIndex;
      _previewIndex = targetIndex;
      _programIndex = 0;
      _useMpvEngine = false;
      _loading = true;
      _error = null;
      _isPaused = false;
      _bannerVisible = showBanner;
      _optionsMode = false;
      _openPicker = null;
      _videoTracks = [];
      _audioTracks = [];
    });

    _loadPreviewAndNeighbors(targetIndex, immediateFetch: true);
    if (showBanner) _scheduleBannerAutoHide();

    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || reqId != _playRequestSeq || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Playback timeout (25s). Stream respond nahi kar rahi.';
      });
    });

    try {
      final resolved = await PcStreamResolver.resolve(target);
      if (!mounted || reqId != _playRequestSeq) return;
      _lastResolvedPlayback = resolved;
      _shaka.play(resolved);
    } catch (e) {
      if (!mounted || reqId != _playRequestSeq) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _clockHeaderText() {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dt = _now;
    final day = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day, ${dt.day} ${months[(dt.month - 1).clamp(0, 11)]}  •  $h12:$m $period';
  }

  String? _digitFromKeyEvent(KeyEvent event) {
    final l = event.logicalKey;
    final p = event.physicalKey;
    if (l == LogicalKeyboardKey.digit0 || l == LogicalKeyboardKey.numpad0 || p == PhysicalKeyboardKey.digit0 || p == PhysicalKeyboardKey.numpad0) return '0';
    if (l == LogicalKeyboardKey.digit1 || l == LogicalKeyboardKey.numpad1 || p == PhysicalKeyboardKey.digit1 || p == PhysicalKeyboardKey.numpad1) return '1';
    if (l == LogicalKeyboardKey.digit2 || l == LogicalKeyboardKey.numpad2 || p == PhysicalKeyboardKey.digit2 || p == PhysicalKeyboardKey.numpad2) return '2';
    if (l == LogicalKeyboardKey.digit3 || l == LogicalKeyboardKey.numpad3 || p == PhysicalKeyboardKey.digit3 || p == PhysicalKeyboardKey.numpad3) return '3';
    if (l == LogicalKeyboardKey.digit4 || l == LogicalKeyboardKey.numpad4 || p == PhysicalKeyboardKey.digit4 || p == PhysicalKeyboardKey.numpad4) return '4';
    if (l == LogicalKeyboardKey.digit5 || l == LogicalKeyboardKey.numpad5 || p == PhysicalKeyboardKey.digit5 || p == PhysicalKeyboardKey.numpad5) return '5';
    if (l == LogicalKeyboardKey.digit6 || l == LogicalKeyboardKey.numpad6 || p == PhysicalKeyboardKey.digit6 || p == PhysicalKeyboardKey.numpad6) return '6';
    if (l == LogicalKeyboardKey.digit7 || l == LogicalKeyboardKey.numpad7 || p == PhysicalKeyboardKey.digit7 || p == PhysicalKeyboardKey.numpad7) return '7';
    if (l == LogicalKeyboardKey.digit8 || l == LogicalKeyboardKey.numpad8 || p == PhysicalKeyboardKey.digit8 || p == PhysicalKeyboardKey.numpad8) return '8';
    if (l == LogicalKeyboardKey.digit9 || l == LogicalKeyboardKey.numpad9 || p == PhysicalKeyboardKey.digit9 || p == PhysicalKeyboardKey.numpad9) return '9';
    return null;
  }

  String? get _playerDigitPreviewName {
    final numVal = int.tryParse(_typedDigits);
    if (numVal == null) return null;
    final idx = pcResolveChannelIndexByNumber(_channels, numVal);
    if (idx != null) return _channels[idx].name;
    final full = widget.allChannels;
    if (full != null) {
      final fIdx = pcResolveChannelIndexByNumber(full, numVal);
      if (fIdx != null) return full[fIdx].name;
    }
    return null;
  }

  void _commitPlayerTypedChannel() {
    _digitCommitTimer?.cancel();
    final digits = _typedDigits;
    if (digits.isEmpty) return;
    final numVal = int.tryParse(digits);
    int? targetIdx = numVal != null ? pcResolveChannelIndexByNumber(_channels, numVal) : null;
    if (targetIdx == null && numVal != null && widget.allChannels != null) {
      final full = widget.allChannels!;
      final fIdx = pcResolveChannelIndexByNumber(full, numVal);
      if (fIdx != null) {
        _channels = full;
        targetIdx = fIdx;
      }
    }
    if (targetIdx == null) {
      setState(() {
        _typedDigits = '';
        _digitOsdError = 'No CH $digits';
      });
      _digitCommitTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _digitOsdError = null);
      });
      return;
    }
    setState(() {
      _typedDigits = '';
      _digitOsdError = null;
    });
    _startChannelStream(targetIdx, showBanner: true);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    final digit = _digitFromKeyEvent(event);
    if (digit != null) {
      _digitCommitTimer?.cancel();
      final nextDigits = _typedDigits.length >= 4 ? digit : '$_typedDigits$digit';
      setState(() {
        _typedDigits = nextDigits;
        _digitOsdError = null;
      });
      _digitCommitTimer = Timer(const Duration(milliseconds: 1450), _commitPlayerTypedChannel);
      return KeyEventResult.handled;
    }

    if (_typedDigits.isNotEmpty &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      _commitPlayerTypedChannel();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      if (_openPicker != null) {
        setState(() => _openPicker = null);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      if (_optionsMode) {
        setState(() => _optionsMode = false);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      _closePlayer();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      final next = (_playingIndex + 1) % _channels.length;
      _startChannelStream(next, showBanner: true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      final next = (_playingIndex - 1 + _channels.length) % _channels.length;
      _startChannelStream(next, showBanner: true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      final next = (_previewIndex + 1) % _channels.length;
      setState(() {
        _bannerVisible = true;
        _optionsMode = false;
        _previewIndex = next;
        _programIndex = 0;
      });
      _loadPreviewAndNeighbors(next);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      final prev = (_previewIndex - 1 + _channels.length) % _channels.length;
      setState(() {
        _bannerVisible = true;
        _optionsMode = false;
        _previewIndex = prev;
        _programIndex = 0;
      });
      _loadPreviewAndNeighbors(prev);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown && _previewPrograms.isNotEmpty) {
      final next = (_programIndex + 1).clamp(0, _previewPrograms.length - 1);
      setState(() {
        _bannerVisible = true;
        _programIndex = next;
      });
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp && _previewPrograms.isNotEmpty) {
      final prev = (_programIndex - 1).clamp(0, _previewPrograms.length - 1);
      setState(() {
        _bannerVisible = true;
        _programIndex = prev;
      });
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (_previewIndex != _playingIndex) {
        _startChannelStream(_previewIndex, showBanner: true);
      } else {
        setState(() => _isPaused = !_isPaused);
        if (_useMpvEngine) {
          _mpv?.setPaused(_isPaused);
        } else {
          _shaka.setPaused(_isPaused);
        }
        _showBanner();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyM) {
      setState(() => _muted = !_muted);
      if (_useMpvEngine) {
        _mpv?.setVolume(1.0, muted: _muted);
      } else {
        _shaka.setVolume(1.0, muted: _muted);
      }
      _showBanner();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _squareIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white.withValues(alpha: 0.16),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 20, color: Colors.white, shadows: _textShadows),
        ),
      ),
    );
  }

  Widget _buildOptionsBar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _squareIconButton(
          icon: Icons.audiotrack_rounded,
          tooltip: 'Audio Track',
          active: _openPicker == _PcPickerKind.audio,
          onTap: () {
            setState(() => _openPicker = _openPicker == _PcPickerKind.audio ? null : _PcPickerKind.audio);
            _bannerAutoHideTimer?.cancel();
          },
        ),
        const SizedBox(width: 8),
        _squareIconButton(
          icon: Icons.hd_rounded,
          tooltip: 'Video Quality',
          active: _openPicker == _PcPickerKind.quality,
          onTap: () {
            setState(() => _openPicker = _openPicker == _PcPickerKind.quality ? null : _PcPickerKind.quality);
            _bannerAutoHideTimer?.cancel();
          },
        ),
        const SizedBox(width: 8),
        _squareIconButton(
          icon: Icons.aspect_ratio_rounded,
          tooltip: 'Aspect Ratio',
          active: _openPicker == _PcPickerKind.stretch,
          onTap: () {
            setState(() => _openPicker = _openPicker == _PcPickerKind.stretch ? null : _PcPickerKind.stretch);
            _bannerAutoHideTimer?.cancel();
          },
        ),
        const SizedBox(width: 8),
        _squareIconButton(
          icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          tooltip: _muted ? 'Unmute (M)' : 'Mute (M)',
          onTap: () {
            setState(() => _muted = !_muted);
            if (_useMpvEngine) {
              _mpv?.setVolume(1.0, muted: _muted);
            } else {
              _shaka.setVolume(1.0, muted: _muted);
            }
            _scheduleBannerAutoHide();
          },
        ),
      ],
    );
  }

  Widget _buildPickerDialog() {
    final kind = _openPicker!;
    final title = kind == _PcPickerKind.audio
        ? 'Audio Track'
        : kind == _PcPickerKind.quality
            ? 'Video Quality'
            : 'Aspect Ratio';

    List<Map<String, dynamic>> items;
    if (kind == _PcPickerKind.audio) {
      items = _audioTracks.isNotEmpty
          ? _audioTracks
          : [
              {'label': 'Default Audio', 'selected': true, 'language': '', 'role': ''}
            ];
    } else if (kind == _PcPickerKind.quality) {
      items = _videoTracks.isNotEmpty
          ? _videoTracks
          : [
              {'id': -1, 'label': 'Highest (Default)', 'selected': true}
            ];
    } else {
      items = [
        {'mode': 'fill', 'label': 'Stretch (Fill)', 'selected': _resizeMode == 'fill'},
        {'mode': 'fit', 'label': 'Original (Fit)', 'selected': _resizeMode == 'fit'},
        {'mode': 'zoom', 'label': 'Zoom (Crop)', 'selected': _resizeMode == 'zoom'},
      ];
    }

    return Center(
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF012151E),
          borderRadius: BorderRadius.circular(12),
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
                    fontFamily: 'Anton',
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  onPressed: () {
                    setState(() => _openPicker = null);
                    _scheduleBannerAutoHide();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, idx) {
                  final item = items[idx];
                  final selected = item['selected'] == true;
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: Colors.white.withValues(alpha: 0.14),
                    onTap: () {
                      if (kind == _PcPickerKind.audio) {
                        final lang = (item['language'] ?? '').toString();
                        final role = (item['role'] ?? '').toString();
                        if (_useMpvEngine) {
                          _mpv?.selectAudioTrack(lang, role);
                        } else {
                          _shaka.selectAudioTrack(lang, role);
                        }
                      } else if (kind == _PcPickerKind.quality) {
                        final id = (item['id'] as num?)?.toInt() ?? -1;
                        if (_useMpvEngine) {
                          _mpv?.selectVideoVariant(id);
                        } else {
                          _shaka.selectVideoVariant(id);
                        }
                      } else {
                        final mode = (item['mode'] ?? 'fill').toString();
                        setState(() => _resizeMode = mode);
                        if (_useMpvEngine) {
                          _mpv?.setResizeMode(mode);
                        } else {
                          _shaka.setResizeMode(mode);
                        }
                      }
                      setState(() => _openPicker = null);
                      _scheduleBannerAutoHide();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (item['label'] ?? 'Option').toString(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_rounded, color: Colors.white, size: 18),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewCh = _previewChannel;
    final activeProgram = _activeProgram;
    final displayChannelNumber =
        previewCh.channelNumber > 0 ? previewCh.channelNumber : (_previewIndex + 101);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _playerFocus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: MouseRegion(
          onHover: (_) {
            if (!_bannerVisible) {
              _showBanner();
            } else {
              _scheduleBannerAutoHide();
            }
          },
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Offstage(
                    offstage: _useMpvEngine,
                    child: _shaka.buildView(),
                  ),
                ),
                if (_useMpvEngine && _mpv != null && _mpv!.isInitialized)
                  Positioned.fill(child: _mpv!.buildView()),
                if (_loading) const Center(child: PcBrandCircularLoader(size: 84)),
                if (_error != null)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xE6101218),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFE65312), size: 40),
                          const SizedBox(height: 12),
                          SelectableText(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65312)),
                                onPressed: () => _startChannelStream(_previewIndex, showBanner: true),
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _closePlayer,
                                child: const Text('Back to channels'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Top Header Bar (Back + Weekday/Clock)
                if (_bannerVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 14, 24, 12),
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          _squareIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Back (Esc)',
                            onTap: _closePlayer,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _clockHeaderText(),
                            style: const TextStyle(
                              fontFamily: 'Anton',
                              color: Colors.white,
                              fontSize: 25,
                              letterSpacing: 0.55,
                              shadows: _textShadows,
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

                // Bottom STB Banner
                if (_bannerVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.14),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 248,
                            height: 140,
                            child: ClipRect(
                              child: PcProgramPoster(
                                primaryUrl: activeProgram.posterUrl,
                                fallbackUrl: activeProgram.fallbackPosterUrl,
                                title: activeProgram.title,
                              ),
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            child: SizedBox(
                              height: 140,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 36,
                                    child: Row(
                                      children: [
                                        Text(
                                          '$displayChannelNumber',
                                          style: const TextStyle(
                                            fontFamily: 'Anton',
                                            color: Colors.white,
                                            fontSize: 27,
                                            height: 1.05,
                                            letterSpacing: 0.8,
                                            shadows: _textShadows,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            previewCh.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Anton',
                                              color: Colors.white,
                                              fontSize: 26,
                                              height: 1.05,
                                              letterSpacing: 0.55,
                                              shadows: _textShadows,
                                            ),
                                          ),
                                        ),
                                        _squareIconButton(
                                          icon: Icons.chevron_left_rounded,
                                          tooltip: 'Previous Channel',
                                          onTap: () {
                                            final prev = (_playingIndex - 1 + _channels.length) % _channels.length;
                                            _startChannelStream(prev, showBanner: true);
                                          },
                                        ),
                                        _squareIconButton(
                                          icon: Icons.chevron_right_rounded,
                                          tooltip: 'Next Channel',
                                          onTap: () {
                                            final next = (_playingIndex + 1) % _channels.length;
                                            _startChannelStream(next, showBanner: true);
                                          },
                                        ),
                                        if (_previewIndex == _playingIndex) ...[
                                          const SizedBox(width: 4),
                                          _squareIconButton(
                                            icon: Icons.tune_rounded,
                                            tooltip: 'Options',
                                            active: _optionsMode,
                                            onTap: () => _showBanner(openOptions: !_optionsMode),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 54,
                                    child: _optionsMode
                                        ? Align(
                                            alignment: Alignment.centerLeft,
                                            child: _buildOptionsBar(),
                                          )
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                activeProgram.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: 'Anton',
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  height: 1.1,
                                                  shadows: _textShadows,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  Text(
                                                    activeProgram.timeLabel,
                                                    style: const TextStyle(
                                                      fontFamily: 'Anton',
                                                      color: Color(0xFFD6DCE8),
                                                      fontSize: 13.5,
                                                      shadows: _textShadows,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  if (activeProgram.isLiveNow)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFE65312),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: const Text(
                                                        'LIVE',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    activeProgram.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.5,
                                      height: 1.25,
                                      shadows: _textShadows,
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

                if (_openPicker != null) _buildPickerDialog(),

                if (_typedDigits.isNotEmpty || _digitOsdError != null)
                  Positioned(
                    top: 66,
                    right: 28,
                    child: PcStbChannelNumberOsd(
                      digits: _typedDigits,
                      previewChannelName: _playerDigitPreviewName,
                      errorMessage: _digitOsdError,
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
