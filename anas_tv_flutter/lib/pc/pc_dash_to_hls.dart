import 'dart:math' as math;

class PcHlsTrackSequenceState {
  int baseSeq = 0;
  List<String> lastSegmentUrls = const [];
}

class _XmlNode {
  final String name;
  final Map<String, String> attrs;
  final List<_XmlNode> children = [];
  final StringBuffer _textBuf = StringBuffer();

  _XmlNode(this.name, this.attrs);

  String get localName {
    final idx = name.indexOf(':');
    return idx >= 0 ? name.substring(idx + 1) : name;
  }

  String get text => _textBuf.toString().trim();

  String? attr(String key) {
    final direct = attrs[key];
    if (direct != null) return direct;
    final lower = key.toLowerCase();
    for (final entry in attrs.entries) {
      final k = entry.key.toLowerCase();
      if (k == lower || k.endsWith(':$lower')) {
        return entry.value;
      }
    }
    return null;
  }

  Iterable<_XmlNode> childrenNamed(String local) sync* {
    final target = local.toLowerCase();
    for (final c in children) {
      if (c.localName.toLowerCase() == target) yield c;
    }
  }

  _XmlNode? firstChildNamed(String local) {
    final target = local.toLowerCase();
    for (final c in children) {
      if (c.localName.toLowerCase() == target) return c;
    }
    return null;
  }
}

class _TinyXmlParser {
  static final RegExp _tagOrDecl = RegExp(
    r'''<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|<!DOCTYPE[\s\S]*?>|<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[A-Za-z_][\w:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'))?)*)\s*(\/?)>''',
  );
  static final RegExp _attrRegex = RegExp(
    r'''([A-Za-z_][\w:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'))?''',
  );

  static String unescapeXml(String s) {
    if (!s.contains('&')) return s;
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#38;', '&');
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    return out;
  }

  static _XmlNode? parse(String xml) {
    final root = _XmlNode('_root', const {});
    final stack = <_XmlNode>[root];
    var pos = 0;

    for (final m in _tagOrDecl.allMatches(xml)) {
      if (m.start > pos) {
        final txt = xml.substring(pos, m.start);
        if (txt.trim().isNotEmpty) {
          stack.last._textBuf.write(unescapeXml(txt));
        }
      }
      pos = m.end;

      final cdata = m.group(1);
      if (cdata != null) {
        stack.last._textBuf.write(cdata);
        continue;
      }

      final rawTag = m.group(0)!;
      if (rawTag.startsWith('<!--') ||
          rawTag.startsWith('<?') ||
          rawTag.startsWith('<!')) {
        continue;
      }

      final isClosing = m.group(2) == '/';
      final tagName = m.group(3) ?? '';
      final attrText = m.group(4) ?? '';
      final isSelfClosing = m.group(5) == '/';

      if (isClosing) {
        for (var i = stack.length - 1; i > 0; i--) {
          if (stack[i].name == tagName ||
              stack[i].localName.toLowerCase() ==
                  (tagName.contains(':') ? tagName.split(':').last : tagName).toLowerCase()) {
            stack.length = i;
            break;
          }
        }
      } else {
        final attrs = <String, String>{};
        if (attrText.trim().isNotEmpty) {
          for (final am in _attrRegex.allMatches(attrText)) {
            final k = am.group(1);
            if (k == null || k.isEmpty) continue;
            final val = am.group(2) ?? am.group(3) ?? '';
            attrs[k] = unescapeXml(val);
          }
        }
        final node = _XmlNode(tagName, attrs);
        stack.last.children.add(node);
        if (!isSelfClosing) {
          stack.add(node);
        }
      }
    }

    for (final c in root.children) {
      if (c.localName.toUpperCase() == 'MPD') return c;
    }
    return root.children.isNotEmpty ? root.children.first : null;
  }
}

class _MergedSegTemplate {
  final String initialization;
  final String media;
  final int timescale;
  final int duration;
  final int startNumber;
  final int presentationTimeOffset;
  final _XmlNode? segmentTimeline;

  const _MergedSegTemplate({
    required this.initialization,
    required this.media,
    required this.timescale,
    required this.duration,
    required this.startNumber,
    required this.presentationTimeOffset,
    required this.segmentTimeline,
  });

  bool get hasSegments =>
      media.isNotEmpty && (segmentTimeline != null || duration > 0);
}

class PcDashSegment {
  final int number;
  final int time;
  final double durationSec;
  final String url;

  const PcDashSegment({
    required this.number,
    required this.time,
    required this.durationSec,
    required this.url,
  });
}

class PcDashTrack {
  final String kind; // 'video' or 'audio'
  final String id;
  final int indexInKind;
  final int bandwidth;
  final int width;
  final int height;
  final String codecs;
  final String language;
  final String initUrl;
  final List<PcDashSegment> segments;

  const PcDashTrack({
    required this.kind,
    required this.id,
    required this.indexInKind,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.codecs,
    required this.language,
    required this.initUrl,
    required this.segments,
  });
}

class PcParsedDashManifest {
  final bool isDynamic;
  final List<PcDashTrack> videos;
  final List<PcDashTrack> audios;

  const PcParsedDashManifest({
    required this.isDynamic,
    required this.videos,
    required this.audios,
  });

  bool get isConvertible => videos.isNotEmpty || audios.isNotEmpty;
}

class PcDashToHlsConverter {
  static double? _parseIsoDurationSec(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final days = double.tryParse(m.group(1) ?? '0') ?? 0;
    final hrs = double.tryParse(m.group(2) ?? '0') ?? 0;
    final mins = double.tryParse(m.group(3) ?? '0') ?? 0;
    final secs = double.tryParse(m.group(4) ?? '0') ?? 0;
    final total = (days * 86400) + (hrs * 3600) + (mins * 60) + secs;
    return total > 0 ? total : null;
  }

  static Uri _resolveBase(Uri parentBase, _XmlNode node) {
    for (final b in node.childrenNamed('BaseURL')) {
      final raw = b.text;
      if (raw.isEmpty) continue;
      try {
        return parentBase.resolve(raw);
      } catch (_) {}
    }
    return parentBase;
  }

  static _MergedSegTemplate _mergeTemplate(
    _MergedSegTemplate parent,
    _XmlNode node,
  ) {
    final st = node.firstChildNamed('SegmentTemplate');
    if (st == null) return parent;
    return _MergedSegTemplate(
      initialization: st.attr('initialization') ?? parent.initialization,
      media: st.attr('media') ?? parent.media,
      timescale: int.tryParse(st.attr('timescale') ?? '') ?? parent.timescale,
      duration: int.tryParse(st.attr('duration') ?? '') ?? parent.duration,
      startNumber: int.tryParse(st.attr('startNumber') ?? '') ?? parent.startNumber,
      presentationTimeOffset:
          int.tryParse(st.attr('presentationTimeOffset') ?? '') ??
              parent.presentationTimeOffset,
      segmentTimeline: st.firstChildNamed('SegmentTimeline') ?? parent.segmentTimeline,
    );
  }

  static String _expandTemplate(
    String template, {
    required String repId,
    required int bandwidth,
    required int number,
    required int time,
  }) {
    var out = template
        .replaceAll(r'$$', '\u0000')
        .replaceAll(r'$RepresentationID$', repId)
        .replaceAll(r'$Bandwidth$', bandwidth.toString());

    out = out.replaceAllMapped(
      RegExp(r'\$(Number|Time)(?:%0(\d+)d)?\$'),
      (m) {
        final kind = m.group(1)!;
        final widthStr = m.group(2);
        final rawVal = kind == 'Time' ? time : number;
        final str = rawVal.toString();
        if (widthStr != null) {
          final w = int.tryParse(widthStr) ?? 0;
          if (w > 0 && str.length < w) {
            return str.padLeft(w, '0');
          }
        }
        return str;
      },
    );

    return out.replaceAll('\u0000', r'$');
  }

  static PcParsedDashManifest? parse(String xml, Uri manifestUri) {
    final mpd = _TinyXmlParser.parse(xml);
    if (mpd == null || mpd.localName.toUpperCase() != 'MPD') return null;

    final isDynamic = (mpd.attr('type') ?? '').toLowerCase() == 'dynamic';
    final availStart = DateTime.tryParse(mpd.attr('availabilityStartTime') ?? '')?.toUtc();
    final suggestedDelaySec = _parseIsoDurationSec(mpd.attr('suggestedPresentationDelay'));
    final mediaPresDurSec = _parseIsoDurationSec(mpd.attr('mediaPresentationDuration'));

    bool looksVideo(String ct, String mt, String codecs, String w, String h) {
      if (ct == 'video' || mt.startsWith('video/')) return true;
      if (w.isNotEmpty || h.isNotEmpty) return true;
      return RegExp(r'(avc|hev|hvc|vp8|vp9|av01|mp4v|dvh|dvhe)', caseSensitive: false).hasMatch(codecs);
    }

    bool looksAudio(String ct, String mt, String codecs) {
      if (ct == 'audio' || mt.startsWith('audio/')) return true;
      return RegExp(r'(mp4a|ec-3|ac-3|ac-4|opus|vorbis|flac)', caseSensitive: false).hasMatch(codecs);
    }

    final mpdBase = _resolveBase(manifestUri, mpd);
    final periods = mpd.childrenNamed('Period').toList();
    final activePeriod = periods.isEmpty
        ? mpd
        : periods.lastWhere(
            (p) => p.childrenNamed('AdaptationSet').any((a) {
              final ct = (a.attr('contentType') ?? '').toLowerCase();
              final mt = (a.attr('mimeType') ?? '').toLowerCase();
              final ac = a.attr('codecs') ?? '';
              if (looksVideo(ct, mt, ac, a.attr('width') ?? '', a.attr('height') ?? '') ||
                  looksAudio(ct, mt, ac)) {
                return true;
              }
              return a.childrenNamed('Representation').any((r) =>
                  looksVideo(ct, (r.attr('mimeType') ?? '').toLowerCase(), r.attr('codecs') ?? '', r.attr('width') ?? '', r.attr('height') ?? '') ||
                  looksAudio(ct, (r.attr('mimeType') ?? '').toLowerCase(), r.attr('codecs') ?? ''));
            }),
            orElse: () => periods.last,
          );

    final periodBase = identical(activePeriod, mpd)
        ? mpdBase
        : _resolveBase(mpdBase, activePeriod);
    const rootTpl = _MergedSegTemplate(
      initialization: '',
      media: '',
      timescale: 1,
      duration: 0,
      startNumber: 1,
      presentationTimeOffset: 0,
      segmentTimeline: null,
    );
    final periodTpl = identical(activePeriod, mpd)
        ? rootTpl
        : _mergeTemplate(rootTpl, activePeriod);

    final videos = <PcDashTrack>[];
    final audios = <PcDashTrack>[];

    for (final aset in activePeriod.childrenNamed('AdaptationSet')) {
      final aMime = (aset.attr('mimeType') ?? '').toLowerCase();
      final aCt = (aset.attr('contentType') ?? '').toLowerCase();
      final aCodecs = aset.attr('codecs') ?? '';
      final aLang = aset.attr('lang') ?? aset.attr('language') ?? '';

      final isText = aCt == 'text' ||
          aCt == 'image' ||
          aMime.startsWith('text/') ||
          aMime.startsWith('image/') ||
          RegExp(r'stpp|wvtt', caseSensitive: false).hasMatch(aCodecs);
      if (isText) continue;

      final adaptBase = _resolveBase(periodBase, aset);
      final adaptTpl = _mergeTemplate(periodTpl, aset);

      final reps = aset.childrenNamed('Representation').toList();
      for (final rep in reps) {
        final rMime = (rep.attr('mimeType') ?? aMime).toLowerCase();
        final rCodecs = (rep.attr('codecs') ?? aCodecs).trim();
        final rw = rep.attr('width') ?? aset.attr('width') ?? '';
        final rh = rep.attr('height') ?? aset.attr('height') ?? '';
        final isVideo = looksVideo(aCt, rMime, rCodecs, rw, rh);
        final isAudio = !isVideo && looksAudio(aCt, rMime, rCodecs);
        if (!isVideo && !isAudio) continue;

        final repId = rep.attr('id') ?? '${isVideo ? 'v' : 'a'}_${videos.length + audios.length}';
        final repBase = _resolveBase(adaptBase, rep);
        final tpl = _mergeTemplate(adaptTpl, rep);
        if (!tpl.hasSegments) continue;

        final codecs = (rep.attr('codecs') ?? aCodecs).trim();
        final bandwidth = int.tryParse(rep.attr('bandwidth') ?? '') ??
            (isVideo ? 1500000 : 128000);
        final width = int.tryParse(rep.attr('width') ?? aset.attr('width') ?? '') ?? 0;
        final height = int.tryParse(rep.attr('height') ?? aset.attr('height') ?? '') ?? 0;
        final lang = (rep.attr('lang') ?? aLang).trim();

        final timescale = tpl.timescale > 0 ? tpl.timescale : 1;
        final initRaw = tpl.initialization.isNotEmpty
            ? _expandTemplate(
                tpl.initialization,
                repId: repId,
                bandwidth: bandwidth,
                number: tpl.startNumber,
                time: tpl.presentationTimeOffset,
              )
            : '';
        final initUrl = initRaw.isNotEmpty ? repBase.resolve(initRaw).toString() : '';

        final segs = <PcDashSegment>[];
        if (tpl.segmentTimeline != null) {
          var curTime = 0;
          var curNum = tpl.startNumber;
          for (final sNode in tpl.segmentTimeline!.childrenNamed('S')) {
            final tAttr = sNode.attr('t');
            if (tAttr != null && tAttr.isNotEmpty) {
              curTime = int.tryParse(tAttr) ?? curTime;
            }
            final d = int.tryParse(sNode.attr('d') ?? '') ?? 0;
            if (d <= 0) continue;
            final rawR = int.tryParse(sNode.attr('r') ?? '0') ?? 0;
            final repeatCount = rawR < 0 ? 12 : (rawR + 1).clamp(1, 2000);
            final durSec = (d / timescale).clamp(0.1, 60.0);

            for (var i = 0; i < repeatCount; i++) {
              final rel = _expandTemplate(
                tpl.media,
                repId: repId,
                bandwidth: bandwidth,
                number: curNum,
                time: curTime,
              );
              segs.add(PcDashSegment(
                number: curNum,
                time: curTime,
                durationSec: durSec,
                url: repBase.resolve(rel).toString(),
              ));
              curNum++;
              curTime += d;
            }
          }
          if (isDynamic && segs.length > 10) {
            segs.removeRange(0, segs.length - 10);
          }
        } else if (tpl.duration > 0) {
          final segDurSec = (tpl.duration / timescale).clamp(0.2, 60.0);
          int firstNum = tpl.startNumber;
          int lastNum = tpl.startNumber + 9;

          if (isDynamic && availStart != null) {
            final delay = suggestedDelaySec ?? (segDurSec * 3.0);
            final nowSec =
                DateTime.now().toUtc().difference(availStart).inMilliseconds / 1000.0;
            final liveEdgeSec = nowSec - delay - (tpl.presentationTimeOffset / timescale);
            final edgeNum = tpl.startNumber + (liveEdgeSec / segDurSec).floor();
            firstNum = math.max(tpl.startNumber, edgeNum - 9);
            lastNum = math.max(firstNum, edgeNum);
          } else if (!isDynamic && mediaPresDurSec != null && mediaPresDurSec > 0) {
            final total = (mediaPresDurSec / segDurSec).ceil().clamp(1, 3000);
            firstNum = tpl.startNumber;
            lastNum = tpl.startNumber + total - 1;
          }

          for (var n = firstNum; n <= lastNum; n++) {
            final time = ((n - tpl.startNumber) * tpl.duration) + tpl.presentationTimeOffset;
            final rel = _expandTemplate(
              tpl.media,
              repId: repId,
              bandwidth: bandwidth,
              number: n,
              time: time,
            );
            segs.add(PcDashSegment(
              number: n,
              time: time,
              durationSec: segDurSec,
              url: repBase.resolve(rel).toString(),
            ));
          }
        }

        if (segs.isEmpty) continue;

        if (isVideo) {
          videos.add(PcDashTrack(
            kind: 'video',
            id: repId,
            indexInKind: videos.length,
            bandwidth: bandwidth,
            width: width,
            height: height,
            codecs: codecs,
            language: lang,
            initUrl: initUrl,
            segments: segs,
          ));
        } else {
          audios.add(PcDashTrack(
            kind: 'audio',
            id: repId,
            indexInKind: audios.length,
            bandwidth: bandwidth,
            width: 0,
            height: 0,
            codecs: codecs,
            language: lang,
            initUrl: initUrl,
            segments: segs,
          ));
        }
      }
    }

    if (videos.isEmpty && audios.isEmpty) return null;

    // Sort videos highest resolution & bandwidth first so libmpv picks best quality by default.
    videos.sort((a, b) {
      if (b.height != a.height) return b.height.compareTo(a.height);
      return b.bandwidth.compareTo(a.bandwidth);
    });

    // Prefer AAC (mp4a) first if available for default audio.
    audios.sort((a, b) {
      final aAac = a.codecs.toLowerCase().contains('mp4a') ? 0 : 1;
      final bAac = b.codecs.toLowerCase().contains('mp4a') ? 0 : 1;
      if (aAac != bAac) return aAac.compareTo(bAac);
      return b.bandwidth.compareTo(a.bandwidth);
    });

    return PcParsedDashManifest(
      isDynamic: isDynamic,
      videos: videos,
      audios: audios,
    );
  }

  static String _sanitizeHlsAttr(String v) =>
      v.replaceAll('"', '').replaceAll('\r', '').replaceAll('\n', '').trim();

  static String buildMasterM3u8(
    PcParsedDashManifest mpd, {
    required String Function(PcDashTrack track) buildTrackUrl,
  }) {
    final sb = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-INDEPENDENT-SEGMENTS');

    final hasAudioGroup = mpd.audios.isNotEmpty;
    if (hasAudioGroup) {
      for (var i = 0; i < mpd.audios.length; i++) {
        final a = mpd.audios[i];
        final lang = _sanitizeHlsAttr(a.language.isNotEmpty ? a.language : 'und');
        final name = _sanitizeHlsAttr(
          a.language.isNotEmpty && a.language.toLowerCase() != 'und'
              ? '${a.language.toUpperCase()} (${a.id})'
              : 'Audio ${i + 1}',
        );
        final def = i == 0 ? 'YES' : 'NO';
        final uri = buildTrackUrl(a);
        sb.writeln(
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="$name",LANGUAGE="$lang",AUTOSELECT=YES,DEFAULT=$def,URI="$uri"',
        );
      }
    }

    final defaultAudioCodec =
        mpd.audios.isNotEmpty && mpd.audios.first.codecs.isNotEmpty
            ? mpd.audios.first.codecs
            : '';

    for (final v in mpd.videos) {
      final attrs = <String>['BANDWIDTH=${v.bandwidth}'];
      if (v.width > 0 && v.height > 0) {
        attrs.add('RESOLUTION=${v.width}x${v.height}');
      }
      final vCodec = _sanitizeHlsAttr(v.codecs);
      final aCodec = _sanitizeHlsAttr(defaultAudioCodec);
      if (vCodec.isNotEmpty) {
        final combined =
            (aCodec.isNotEmpty && !vCodec.contains(',')) ? '$vCodec,$aCodec' : vCodec;
        attrs.add('CODECS="$combined"');
      }
      if (hasAudioGroup) {
        attrs.add('AUDIO="aud"');
      }
      sb.writeln('#EXT-X-STREAM-INF:${attrs.join(',')}');
      sb.writeln(buildTrackUrl(v));
    }

    if (mpd.videos.isEmpty && mpd.audios.isNotEmpty) {
      final a = mpd.audios.first;
      sb.writeln('#EXT-X-STREAM-INF:BANDWIDTH=${a.bandwidth}');
      sb.writeln(buildTrackUrl(a));
    }

    return sb.toString();
  }

  static String buildTrackM3u8(
    PcParsedDashManifest mpd,
    PcDashTrack track, {
    required PcHlsTrackSequenceState seqState,
    required String Function(String rawSegUrl) toDecryptUrl,
  }) {
    final segs = track.segments;
    var maxDur = 1;
    for (final s in segs) {
      final c = s.durationSec.ceil();
      if (c > maxDur) maxDur = c;
    }

    final segUrls = segs.map((s) => s.url).toList(growable: false);
    int mediaSequence;
    if (!mpd.isDynamic) {
      mediaSequence = segs.first.number;
    } else if (seqState.lastSegmentUrls.isEmpty) {
      mediaSequence = segs.first.number > 0 ? segs.first.number : 1;
    } else {
      final firstUrl = segUrls.first;
      final matchIdx = seqState.lastSegmentUrls.indexOf(firstUrl);
      if (matchIdx >= 0) {
        mediaSequence = seqState.baseSeq + matchIdx;
      } else {
        mediaSequence = seqState.baseSeq + seqState.lastSegmentUrls.length;
      }
    }
    seqState.baseSeq = mediaSequence;
    seqState.lastSegmentUrls = segUrls;

    final sb = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:$maxDur')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$mediaSequence');

    if (track.initUrl.isNotEmpty) {
      sb.writeln('#EXT-X-MAP:URI="${toDecryptUrl(track.initUrl)}"');
    }

    for (final s in segs) {
      sb.writeln('#EXTINF:${s.durationSec.toStringAsFixed(3)},');
      sb.writeln(toDecryptUrl(s.url));
    }

    if (!mpd.isDynamic) {
      sb.writeln('#EXT-X-ENDLIST');
    }

    return sb.toString();
  }
}
