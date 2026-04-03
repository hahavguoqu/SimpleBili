import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'video_service.dart';

class VideoPlayerState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? videoInfo;
  final Map<String, dynamic>? playUrlInfo;
  final double speed;
  final int currentQuality;
  final List<Map<String, dynamic>> availableQualities;
  final bool isFavoriting;
  final int? currentCid;

  VideoPlayerState({
    this.isLoading = false,
    this.error,
    this.videoInfo,
    this.playUrlInfo,
    this.speed = 1.0,
    this.currentQuality = 80, // Default to 1080P
    this.availableQualities = const [
      {'qn': 116, 'desc': '1080P 60FPS'},
      {'qn': 80, 'desc': '1080P'},
      {'qn': 64, 'desc': '720P'},
      {'qn': 32, 'desc': '480P'},
      {'qn': 16, 'desc': '360P'},
    ],
    this.isFavoriting = false,
    this.currentCid,
  });

  /// Get the pages list from videoInfo (multi-part videos)
  List<Map<String, dynamic>> get pages {
    final p = videoInfo?['pages'] as List<dynamic>?;
    return p?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get ugc_season sections from videoInfo (collection videos)
  Map<String, dynamic>? get ugcSeason {
    return videoInfo?['ugc_season'] as Map<String, dynamic>?;
  }

  /// Whether video has multiple pages
  bool get hasMultiPages => pages.length > 1;

  /// Whether video belongs to a ugc_season collection
  bool get hasUgcSeason => ugcSeason != null;

  VideoPlayerState copyWith({
    bool? isLoading,
    String? error,
    Map<String, dynamic>? videoInfo,
    Map<String, dynamic>? playUrlInfo,
    double? speed,
    int? currentQuality,
    List<Map<String, dynamic>>? availableQualities,
    bool? isFavoriting,
    int? currentCid,
    bool clearError = false,
  }) {
    return VideoPlayerState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      videoInfo: videoInfo ?? this.videoInfo,
      playUrlInfo: playUrlInfo ?? this.playUrlInfo,
      speed: speed ?? this.speed,
      currentQuality: currentQuality ?? this.currentQuality,
      availableQualities: availableQualities ?? this.availableQualities,
      isFavoriting: isFavoriting ?? this.isFavoriting,
      currentCid: currentCid ?? this.currentCid,
    );
  }
}

class PlayerNotifier extends StateNotifier<VideoPlayerState> {
  final VideoService _service;
  final String _bvid;

  PlayerNotifier(this._service, this._bvid) : super(VideoPlayerState());

  Future<void> loadVideo({int? cid}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final info = state.videoInfo ?? await _service.getVideoInfo(_bvid);
      final targetCid = cid ?? info['cid'];
      final playInfo = await _service.getPlayUrl(
        _bvid,
        targetCid,
        qn: state.currentQuality,
      );

      // Extract available qualities from DASH response
      List<Map<String, dynamic>>? qualities;
      if (playInfo['dash'] != null) {
        final videos = playInfo['dash']['video'] as List<dynamic>? ?? [];
        final seen = <int>{};
        qualities = [];
        for (final v in videos) {
          final id = v['id'] as int;
          if (seen.add(id)) {
            qualities.add({'qn': id, 'desc': _qualityName(id)});
          }
        }
        qualities.sort((a, b) => (b['qn'] as int).compareTo(a['qn'] as int));
      }

      state = state.copyWith(
        isLoading: false,
        videoInfo: info,
        playUrlInfo: playInfo,
        availableQualities: qualities,
        currentCid: targetCid,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  static String _qualityName(int qn) {
    const map = {
      127: '8K 超高清',
      126: '杜比视界',
      125: 'HDR 真彩',
      120: '4K 超清',
      116: '1080P 60FPS',
      112: '1080P 高码率',
      80: '1080P',
      74: '720P 60FPS',
      64: '720P',
      32: '480P',
      16: '360P',
    };
    return map[qn] ?? '${qn}P';
  }

  Future<void> addToFavorite({
    required int aid,
    required List<int> folderIds,
  }) async {
    if (state.isFavoriting) return;
    state = state.copyWith(isFavoriting: true);
    try {
      await _service.addToFavorite(aid: aid, folderIds: folderIds);
      final info = await _service.getVideoInfo(_bvid);
      state = state.copyWith(videoInfo: info, isFavoriting: false);
    } catch (e) {
      state = state.copyWith(isFavoriting: false, error: 'Favorite failed: $e');
    }
  }

  Future<void> switchPage(int cid) async {
    if (state.currentCid == cid) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final playInfo = await _service.getPlayUrl(
        _bvid,
        cid,
        qn: state.currentQuality,
      );

      List<Map<String, dynamic>>? qualities;
      if (playInfo['dash'] != null) {
        final videos = playInfo['dash']['video'] as List<dynamic>? ?? [];
        final seen = <int>{};
        qualities = [];
        for (final v in videos) {
          final id = v['id'] as int;
          if (seen.add(id)) {
            qualities.add({'qn': id, 'desc': _qualityName(id)});
          }
        }
        qualities.sort((a, b) => (b['qn'] as int).compareTo(a['qn'] as int));
      }

      state = state.copyWith(
        isLoading: false,
        playUrlInfo: playInfo,
        currentCid: cid,
        availableQualities: qualities,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> changeQuality(int qn) async {
    if (state.currentQuality == qn) return;
    state = state.copyWith(currentQuality: qn, isLoading: true);
    try {
      final cid = state.currentCid ?? state.videoInfo!['cid'];
      final playInfo = await _service.getPlayUrl(_bvid, cid, qn: qn);
      state = state.copyWith(
        isLoading: false,
        playUrlInfo: playInfo,
        // Signal URL changed so player re-opens
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Change quality failed: $e',
      );
    }
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }
}

final playerProvider =
    StateNotifierProvider.family<PlayerNotifier, VideoPlayerState, String>((
      ref,
      bvid,
    ) {
      return PlayerNotifier(ref.read(videoServiceProvider), bvid)..loadVideo();
    });
