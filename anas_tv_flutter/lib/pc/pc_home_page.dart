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
import 'pc_window_fullscreen.dart';

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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.f11) {
      PcWindowFullscreen.toggle();
      return KeyEventResult.handled;
    }

    if (_searchFocus.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchQuery.isNotEmpty) {
          _searchController.clear();
          setState(() => _searchQuery = '');
        }
        _pageFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

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
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (!loading && error == null && filterTabs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF050505),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 2,
                                runSpacing: 2,
                                children: List.generate(filterTabs.length, (idx) {
                                  final label = filterTabs[idx];
                                  final active = label.toLowerCase() == selectedTab.toLowerCase();
                                  return _PcCategoryTab(
                                    label: label.toUpperCase(),
                                    selected: active,
                                    onTap: () {
                                      setState(() => selectedTab = label);
                                      if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                                    },
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 4),
                              child: SizedBox(
                                width: 220,
                                height: 34,
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  onChanged: (v) {
                                    setState(() => _searchQuery = v);
                                    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                                  },
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                  cursorColor: const Color(0xFFE65312),
                                  decoration: InputDecoration(
                                    hintText: 'Search...',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF8B909E),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      size: 17,
                                      color: Color(0xFF8B909E),
                                    ),
                                    prefixIconConstraints:
                                        const BoxConstraints(minWidth: 32, minHeight: 32),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(minWidth: 28, minHeight: 28),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: Color(0xFF8B909E),
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                              _pageFocus.requestFocus();
                                            },
                                          )
                                        : null,
                                    filled: true,
                                    fillColor: const Color(0xFF0E1015),
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: Color(0xFF1F1F1F)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: Color(0xFFE65312)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: ClipRect(
                      child: loading
                          ? const Center(child: PcBrandCircularLoader(size: 80))
                          : error != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.wifi_off_rounded,
                                          color: Color(0xFFE65312),
                                          size: 48,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          error!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFFE65312),
                                          ),
                                          onPressed: _loadChannels,
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : channels.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Koi channel nahi mila',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {
                                                selectedTab = 'ALL';
                                                _searchQuery = '';
                                              });
                                            },
                                            child: const Text('Show All'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                        final w = constraints.maxWidth;
                                        final cols = w >= 960 ? 8 : (w >= 680 ? 6 : 4);
                                        return GridView.builder(
                                          controller: _gridScroll,
                                          cacheExtent: 260,
                                          addAutomaticKeepAlives: false,
                                          clipBehavior: Clip.none,
                                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: cols,
                                            mainAxisSpacing: 7.0,
                                            crossAxisSpacing: 7.0,
                                            childAspectRatio: 0.88,
                                          ),
                                          itemCount: channels.length,
                                          itemBuilder: (_, idx) {
                                            final ch = channels[idx];
                                            return RepaintBoundary(
                                              key: ValueKey('ch_${ch.id}_$idx'),
                                              child: _PcChannelCard(
                                                channel: ch,
                                                onTap: () => _openChannelPlayer(channels, idx),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                    ),
                  ),
                ],
              ),
              if (_typedDigits.isNotEmpty || _digitOsdError != null)
                Positioned(
                  top: 14,
                  right: 20,
                  child: PcStbChannelNumberOsd(
                    digits: _typedDigits,
                    previewChannelName: _homeDigitPreviewName,
                    errorMessage: _digitOsdError,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PcCategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PcCategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PcCategoryTab> createState() => _PcCategoryTabState();
}

class _PcCategoryTabState extends State<_PcCategoryTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF23262F) : Colors.transparent,
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
              fontWeight: active || _hovered ? FontWeight.w700 : FontWeight.w600,
              color: active
                  ? const Color(0xFFE65312)
                  : (_hovered ? Colors.white : const Color(0xFFD0D4DC)),
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
    final activeHighlight = _hovered;
    final cardColor = activeHighlight ? const Color(0xFFE65312) : const Color(0xFF080808);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final logoSize = math.min(w * 0.68, h * 0.65);
      final nameSize = (w * 0.13).clamp(9.0, 16.0).toDouble();
      return AnimatedScale(
        scale: activeHighlight ? 1.16 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOut,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
              decoration: BoxDecoration(
                color: cardColor,
                border: activeHighlight
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
                        color: const Color(0xFF5CCFE0),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: activeHighlight ? Colors.white : const Color(0xFFD94B0A),
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
                  SizedBox(
                    height: nameSize * 1.38,
                    width: double.infinity,
                    child: Center(
                      child: _PcChannelMarquee(
                        text: widget.channel.name,
                        animate: activeHighlight,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: nameSize,
                          height: 1.05,
                          fontWeight: activeHighlight ? FontWeight.w700 : FontWeight.w500,
                          fontFamily: 'Roboto',
                          letterSpacing: -0.2,
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

class _PcChannelMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;

  const _PcChannelMarquee({
    required this.text,
    required this.style,
    this.animate = true,
  });

  @override
  State<_PcChannelMarquee> createState() => _PcChannelMarqueeState();
}

class _PcChannelMarqueeState extends State<_PcChannelMarquee> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(covariant _PcChannelMarquee oldWidget) {
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
        _controller.duration = Duration(
          milliseconds: ((distance / 38) * 1000).round().clamp(1800, 18000).toInt(),
        );
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
                SizedBox(
                  width: textWidth,
                  child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                ),
                const SizedBox(width: _gap),
                SizedBox(
                  width: textWidth,
                  child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                ),
              ],
            ),
          ),
        ),
      );
    });
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
  int _programAnimDir = 1;

  bool _loading = true;
  bool _isPaused = false;
  bool _muted = false;
  bool _isFullScreen = PcWindowFullscreen.isFullscreen;
  String _resizeMode = 'fill';
  String? _error;

  bool _bannerVisible = true;
  bool _optionsMode = false;
  int _selectedOptionIdx = 0;
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
    _isFullScreen = PcWindowFullscreen.isFullscreen;
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
        final hint = _mpv?.lastTraceHint;
        setState(() {
          _loading = false;
          _error = hint != null && hint.isNotEmpty
              ? 'HEVC playback timeout (28s): $hint'
              : 'HEVC playback timeout (28s). Stream respond nahi kar rahi.';
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

  void _toggleFullscreen() {
    final next = PcWindowFullscreen.toggle();
    setState(() => _isFullScreen = next);
    _scheduleBannerAutoHide();
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
    _bannerAutoHideTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _openPicker != null || _error != null) return;
      setState(() {
        _bannerVisible = false;
        _optionsMode = false;
        _programIndex = 0;
        _previewIndex = _playingIndex;
      });
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
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
      if (openOptions) _selectedOptionIdx = _selectedOptionIdx.clamp(0, 3);
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[(_now.weekday - 1).clamp(0, 6)];
    final h24 = _now.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final min = _now.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'pm' : 'am';
    return '$dayName, ${months[_now.month - 1]} ${_now.day}  |  $h12:$min $ampm';
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

  void _triggerOption(int optionIdx) {
    setState(() => _selectedOptionIdx = optionIdx);
    switch (optionIdx) {
      case 0:
        setState(() {
          _openPicker = _openPicker == _PcPickerKind.audio ? null : _PcPickerKind.audio;
        });
        if (_openPicker != null) {
          _bannerAutoHideTimer?.cancel();
        } else {
          _scheduleBannerAutoHide();
        }
        break;
      case 1:
        setState(() {
          _openPicker = _openPicker == _PcPickerKind.quality ? null : _PcPickerKind.quality;
        });
        if (_openPicker != null) {
          _bannerAutoHideTimer?.cancel();
        } else {
          _scheduleBannerAutoHide();
        }
        break;
      case 2:
        setState(() {
          _openPicker = _openPicker == _PcPickerKind.stretch ? null : _PcPickerKind.stretch;
        });
        if (_openPicker != null) {
          _bannerAutoHideTimer?.cancel();
        } else {
          _scheduleBannerAutoHide();
        }
        break;
      case 3:
        _toggleFullscreen();
        break;
    }
  }

  void _handleBack() {
    if (_typedDigits.isNotEmpty) {
      _digitCommitTimer?.cancel();
      setState(() {
        _typedDigits = '';
        _digitOsdError = null;
      });
      return;
    }
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
        _programIndex = 0;
        _previewIndex = _playingIndex;
      });
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
      _bannerAutoHideTimer?.cancel();
      return;
    }
    if (_isFullScreen) {
      final next = PcWindowFullscreen.setFullscreen(false);
      setState(() => _isFullScreen = next);
      return;
    }
    _closePlayer();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

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

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      _handleBack();
      return KeyEventResult.handled;
    }

    if (_openPicker != null) {
      return KeyEventResult.ignored;
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
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
        return KeyEventResult.handled;
      }
      if (_optionsMode) {
        setState(() => _selectedOptionIdx = (_selectedOptionIdx + 1) % 4);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      final next = (_previewIndex + 1) % _channels.length;
      setState(() {
        _bannerVisible = true;
        _optionsMode = false;
        _previewIndex = next;
        _programIndex = 0;
        _programAnimDir = 1;
      });
      _loadPreviewAndNeighbors(next);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
        return KeyEventResult.handled;
      }
      if (_optionsMode) {
        setState(() => _selectedOptionIdx = (_selectedOptionIdx - 1 + 4) % 4);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      final prev = (_previewIndex - 1 + _channels.length) % _channels.length;
      setState(() {
        _bannerVisible = true;
        _optionsMode = false;
        _previewIndex = prev;
        _programIndex = 0;
        _programAnimDir = 1;
      });
      _loadPreviewAndNeighbors(prev);
      _scheduleBannerAutoHide();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
        return KeyEventResult.handled;
      }
      if (_optionsMode) return KeyEventResult.handled;
      if (_previewPrograms.isNotEmpty) {
        final next = (_programIndex + 1).clamp(0, _previewPrograms.length - 1);
        if (next != _programIndex) {
          setState(() {
            _programAnimDir = 1;
            _programIndex = next;
          });
        }
        _scheduleBannerAutoHide();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
        return KeyEventResult.handled;
      }
      if (_optionsMode) {
        setState(() => _optionsMode = false);
        _scheduleBannerAutoHide();
        return KeyEventResult.handled;
      }
      if (_previewPrograms.isNotEmpty) {
        final prev = (_programIndex - 1).clamp(0, _previewPrograms.length - 1);
        if (prev != _programIndex) {
          setState(() {
            _programAnimDir = -1;
            _programIndex = prev;
          });
        }
        _scheduleBannerAutoHide();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.mediaPlayPause) {
      setState(() => _isPaused = !_isPaused);
      if (_useMpvEngine) {
        _mpv?.setPaused(_isPaused);
      } else {
        _shaka.setPaused(_isPaused);
      }
      _showBanner();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (_typedDigits.isNotEmpty) {
        _commitPlayerTypedChannel();
        return KeyEventResult.handled;
      }
      if (_error != null) {
        _startChannelStream(_previewIndex, showBanner: true);
        return KeyEventResult.handled;
      }
      if (!_bannerVisible) {
        _showBanner(resetToPlaying: true);
        return KeyEventResult.handled;
      }
      if (_optionsMode) {
        _triggerOption(_selectedOptionIdx);
        return KeyEventResult.handled;
      }
      if (_previewIndex != _playingIndex) {
        _startChannelStream(_previewIndex, showBanner: true);
      } else {
        _showBanner(openOptions: true);
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

  Widget _buildStbProgramDetails(PcProgram program, {required bool compactLayout}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          program.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Anton',
            color: Colors.white,
            fontSize: compactLayout ? 16 : 19,
            height: 1.15,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.45,
            shadows: _textShadows,
          ),
        ),
        SizedBox(height: compactLayout ? 4 : 5),
        Text(
          program.timeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Anton',
            color: const Color(0xFFF0F4FA),
            fontSize: compactLayout ? 13 : 14.5,
            height: 1.15,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.45,
            shadows: _textShadows,
          ),
        ),
        SizedBox(height: compactLayout ? 4 : 5),
        Text(
          program.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFFD6DCE8),
            fontSize: compactLayout ? 11 : 12.5,
            height: 1.30,
            shadows: _textShadows,
          ),
        ),
      ],
    );
  }

  Widget _buildStbOptionsBar() {
    final options = <(IconData, String)>[
      (Icons.audiotrack_rounded, 'Audio Track'),
      (Icons.hd_rounded, 'Video Quality'),
      (Icons.aspect_ratio_rounded, 'Aspect Ratio'),
      (
        _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        _isFullScreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(options.length, (i) {
          final selected = _selectedOptionIdx == i ||
              (i == 0 && _openPicker == _PcPickerKind.audio) ||
              (i == 1 && _openPicker == _PcPickerKind.quality) ||
              (i == 2 && _openPicker == _PcPickerKind.stretch) ||
              (i == 3 && _isFullScreen);
          final (iconData, tooltip) = options[i];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: tooltip,
              child: InkWell(
                onTap: () => _triggerOption(i),
                borderRadius: BorderRadius.circular(6),
                hoverColor: Colors.white.withValues(alpha: 0.16),
                focusColor: Colors.white.withValues(alpha: 0.22),
                highlightColor: Colors.white.withValues(alpha: 0.12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    iconData,
                    color: selected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                    size: 23,
                    shadows: _textShadows,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStbTrackPickerOverlay() {
    final kind = _openPicker!;
    final title = kind == _PcPickerKind.audio
        ? 'Audio Track'
        : kind == _PcPickerKind.quality
            ? 'Video Quality'
            : 'Screen Stretch Mode';

    List<Map<String, dynamic>> items;
    if (kind == _PcPickerKind.audio) {
      items = _audioTracks.isNotEmpty
          ? _audioTracks
          : [
              {'label': 'Default Stream Audio', 'selected': true, 'language': '', 'role': ''}
            ];
    } else if (kind == _PcPickerKind.quality) {
      items = _videoTracks.isNotEmpty
          ? _videoTracks
          : [
              {'id': -1, 'label': 'Highest (Default)', 'selected': true}
            ];
    } else {
      items = [
        {'mode': 'fill', 'label': 'Stretched (Full Screen)', 'selected': _resizeMode == 'fill'},
        {'mode': 'fit', 'label': 'Fit (Original Aspect)', 'selected': _resizeMode == 'fit'},
        {'mode': 'zoom', 'label': 'Zoom (Fill & Crop)', 'selected': _resizeMode == 'zoom'},
      ];
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.24),
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(6),
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
                      shadows: _textShadows,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() => _openPicker = null);
                      _scheduleBannerAutoHide();
                    },
                    borderRadius: BorderRadius.circular(4),
                    hoverColor: Colors.white.withValues(alpha: 0.16),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, idx) {
                    final item = items[idx];
                    final active = item['selected'] == true;
                    return InkWell(
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
                      borderRadius: BorderRadius.circular(4),
                      hoverColor: Colors.white.withValues(alpha: 0.16),
                      focusColor: Colors.white.withValues(alpha: 0.22),
                      highlightColor: Colors.white.withValues(alpha: 0.12),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (item['label'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.86),
                                  fontSize: 13.5,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                  shadows: _textShadows,
                                ),
                              ),
                            ),
                            if (active)
                              const Icon(Icons.check_rounded, size: 18, color: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    final previewCh = _previewChannel;
    final activeProgram = _activeProgram;
    final size = MediaQuery.sizeOf(context);
    final compactLayout = size.width < 720 || size.height < 500;
    final narrowCompact = size.width < 540;
    final posterWidth = narrowCompact ? 148.0 : (compactLayout ? 250.0 : 340.0);
    final posterHeight = narrowCompact ? 104.0 : (compactLayout ? 150.0 : 192.0);
    final titleRowHeight = narrowCompact ? 30.0 : (compactLayout ? 32.0 : 36.0);
    final middleSlotHeight = narrowCompact ? 76.0 : (compactLayout ? 80.0 : 92.0);
    final topPadInsideStrip = narrowCompact ? 4.0 : (compactLayout ? 5.0 : 6.0);
    final rowGap = narrowCompact ? 4.0 : (compactLayout ? 6.0 : 8.0);
    final rightContentHeight =
        topPadInsideStrip + titleRowHeight + rowGap + middleSlotHeight + rowGap + 3.0;
    final stripTopOffset = math.max(0.0, posterHeight - rightContentHeight);
    final progKey = ValueKey('${previewCh.id}_$_programIndex');
    final posterKey = ValueKey('poster_${previewCh.id}_$_programIndex');
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
            onDoubleTap: _openPicker == null ? _toggleFullscreen : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: _useMpvEngine ? -4000 : 0,
                  top: 0,
                  width: _useMpvEngine ? 1 : null,
                  height: _useMpvEngine ? 1 : null,
                  right: _useMpvEngine ? null : 0,
                  bottom: _useMpvEngine ? null : 0,
                  child: IgnorePointer(
                    ignoring: _useMpvEngine,
                    child: _shaka.buildView(),
                  ),
                ),
                if (_useMpvEngine && _mpv != null && _mpv!.isInitialized)
                  Positioned.fill(child: _mpv!.buildView()),
                if (_loading) const Center(child: PcBrandCircularLoader(size: 84)),
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
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE65312),
                                ),
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

                // Top Header Bar (TV-identical Clock + PAUSED pill; NO Back arrow icon)
                if (_bannerVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        compactLayout ? 14 : 26,
                        compactLayout ? 10 : 14,
                        compactLayout ? 14 : 26,
                        12,
                      ),
                      color: Colors.transparent,
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            Text(
                              _clockHeaderText(),
                              style: TextStyle(
                                fontFamily: 'Anton',
                                color: Colors.white,
                                fontSize: compactLayout ? 21 : 26,
                                fontWeight: FontWeight.w400,
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
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Bottom STB Banner (100% TV-identical floating poster + translucent strip)
                if (_bannerVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomLeft,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: stripTopOffset,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.10),
                                  Colors.black.withValues(alpha: 0.20),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compactLayout ? 14 : 28,
                              0,
                              compactLayout ? 14 : 28,
                              compactLayout ? 10 : 16,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                RepaintBoundary(
                                  child: SizedBox(
                                    width: posterWidth,
                                    height: posterHeight,
                                    child: ClipRect(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 180),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        layoutBuilder: (currentChild, previousChildren) => Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ...previousChildren,
                                            if (currentChild != null) currentChild,
                                          ],
                                        ),
                                        transitionBuilder: (child, animation) {
                                          final isIncoming = child.key == posterKey;
                                          final beginOffset = isIncoming
                                              ? Offset(0, _programAnimDir >= 0 ? 0.30 : -0.30)
                                              : Offset(0, _programAnimDir >= 0 ? -0.25 : 0.25);
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: beginOffset,
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: KeyedSubtree(
                                          key: posterKey,
                                          child: PcProgramPoster(
                                            primaryUrl: activeProgram.posterUrl,
                                            fallbackUrl: activeProgram.fallbackPosterUrl,
                                            title: activeProgram.title,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: compactLayout ? 14 : 22),
                                Expanded(
                                  child: RepaintBoundary(
                                    child: SizedBox(
                                      height: rightContentHeight,
                                      child: Padding(
                                        padding: EdgeInsets.only(top: topPadInsideStrip),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              height: titleRowHeight,
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$displayChannelNumber',
                                                    style: TextStyle(
                                                      fontFamily: 'Anton',
                                                      color: Colors.white,
                                                      fontSize: compactLayout ? 22 : 27,
                                                      height: 1.08,
                                                      fontWeight: FontWeight.w400,
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
                                                      style: TextStyle(
                                                        fontFamily: 'Anton',
                                                        color: Colors.white,
                                                        fontSize: compactLayout ? 21 : 26,
                                                        height: 1.08,
                                                        fontWeight: FontWeight.w400,
                                                        letterSpacing: 0.55,
                                                        shadows: _textShadows,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_previewIndex == _playingIndex) ...[
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () =>
                                                          _showBanner(openOptions: !_optionsMode),
                                                      borderRadius: BorderRadius.circular(6),
                                                      hoverColor:
                                                          Colors.white.withValues(alpha: 0.16),
                                                      focusColor:
                                                          Colors.white.withValues(alpha: 0.22),
                                                      highlightColor:
                                                          Colors.white.withValues(alpha: 0.12),
                                                      child: Container(
                                                        width: compactLayout ? 30 : 34,
                                                        height: compactLayout ? 30 : 34,
                                                        alignment: Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color: _optionsMode
                                                              ? Colors.white.withValues(alpha: 0.22)
                                                              : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(
                                                          Icons.tune_rounded,
                                                          size: compactLayout ? 19 : 21,
                                                          color: Colors.white,
                                                          shadows: _textShadows,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            SizedBox(height: rowGap),
                                            SizedBox(
                                              height: middleSlotHeight,
                                              width: double.infinity,
                                              child: _optionsMode
                                                  ? Align(
                                                      alignment: Alignment.centerLeft,
                                                      child: _buildStbOptionsBar(),
                                                    )
                                                  : Align(
                                                      alignment: Alignment.topLeft,
                                                      child: ClipRect(
                                                        child: AnimatedSwitcher(
                                                          duration:
                                                              const Duration(milliseconds: 180),
                                                          switchInCurve: Curves.easeOutCubic,
                                                          switchOutCurve: Curves.easeInCubic,
                                                          layoutBuilder:
                                                              (currentChild, previousChildren) =>
                                                                  Stack(
                                                            alignment: Alignment.topLeft,
                                                            children: [
                                                              ...previousChildren,
                                                              if (currentChild != null)
                                                                currentChild,
                                                            ],
                                                          ),
                                                          transitionBuilder: (child, animation) {
                                                            final isIncoming = child.key == progKey;
                                                            final beginOffset = isIncoming
                                                                ? Offset(
                                                                    0,
                                                                    _programAnimDir >= 0
                                                                        ? 0.35
                                                                        : -0.35,
                                                                  )
                                                                : Offset(
                                                                    0,
                                                                    _programAnimDir >= 0
                                                                        ? -0.30
                                                                        : 0.30,
                                                                  );
                                                            return FadeTransition(
                                                              opacity: animation,
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin: beginOffset,
                                                                  end: Offset.zero,
                                                                ).animate(animation),
                                                                child: child,
                                                              ),
                                                            );
                                                          },
                                                          child: KeyedSubtree(
                                                            key: progKey,
                                                            child: _buildStbProgramDetails(
                                                              activeProgram,
                                                              compactLayout: compactLayout,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                            const Spacer(),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                minHeight: 3,
                                                value: activeProgram.isLiveNow
                                                    ? activeProgram.progress
                                                    : 0.0,
                                                backgroundColor:
                                                    Colors.white.withValues(alpha: 0.25),
                                                valueColor: const AlwaysStoppedAnimation<Color>(
                                                  Color(0xFFE53935),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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

                if (_openPicker != null) _buildStbTrackPickerOverlay(),

                if (_typedDigits.isNotEmpty || _digitOsdError != null)
                  Positioned(
                    top: 16,
                    right: 24,
                    child: SafeArea(
                      child: PcStbChannelNumberOsd(
                        digits: _typedDigits,
                        previewChannelName: _playerDigitPreviewName,
                        errorMessage: _digitOsdError,
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
