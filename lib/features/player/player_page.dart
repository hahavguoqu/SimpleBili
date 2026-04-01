import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'player_provider.dart';
import 'video_service.dart';

class PlayerPage extends ConsumerStatefulWidget {
  final String bvid;

  const PlayerPage({super.key, required this.bvid});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player player;
  late final VideoController controller;
  String? _currentUrl;
  int? _currentQuality;
  double _lastSpeed = 1.0;
  bool _isSeeking = false;
  double _seekValueMs = 0;
  DateTime? _rightKeyDownTime;
  DateTime? _leftKeyDownTime;

  @override
  void initState() {
    super.initState();
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    // Increase demuxer buffer for smoother playback at higher speeds
    if (player.platform is NativePlayer) {
      final nativePlayer = player.platform as NativePlayer;
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      if (isMobile) {
        // Mobile: smaller buffers to save memory, enable hardware decode
        nativePlayer.setProperty('demuxer-max-bytes', '32MiB');
        nativePlayer.setProperty('demuxer-max-back-bytes', '16MiB');
        nativePlayer.setProperty('cache-secs', '15');
        nativePlayer.setProperty('hwdec', 'auto');
        nativePlayer.setProperty('vd-lavc-dr', 'yes');
        nativePlayer.setProperty('vd-lavc-fast', 'yes');
      } else {
        // Desktop: larger buffers for quality
        nativePlayer.setProperty('demuxer-max-bytes', '64MiB');
        nativePlayer.setProperty('demuxer-max-back-bytes', '32MiB');
        nativePlayer.setProperty('cache-secs', '30');
      }
    }
    controller = VideoController(player);
    // Listen to mpv logs for debugging
    player.stream.log.listen((log) {
      debugPrint('[mpv ${log.level}] ${log.prefix}: ${log.text}');
    });
    // Listen to player errors
    player.stream.error.listen((error) {
      debugPrint('[SimpleBili] Player error: $error');
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _playVideo(Map<String, dynamic> playUrlInfo) async {
    String? videoUrl;
    String? audioUrl;
    final currentQn = ref.read(playerProvider(widget.bvid)).currentQuality;

    if (playUrlInfo['dash'] != null) {
      final dash = playUrlInfo['dash'];
      final videos = dash['video'] as List<dynamic>? ?? [];
      final audios = dash['audio'] as List<dynamic>? ?? [];

      // Select video stream matching requested quality
      // On mobile, prefer H.264 (avc) for smoother high-speed playback
      // On desktop, prefer highest quality codec (AV1/HEVC)
      if (videos.isNotEmpty) {
        final isMobile =
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        final matchQn = videos
            .cast<Map<String, dynamic>>()
            .where((v) => v['id'] == currentQn)
            .toList();
        final candidates = matchQn.isNotEmpty
            ? matchQn
            : videos.cast<Map<String, dynamic>>().toList();

        if (isMobile) {
          // Mobile: prefer H.264 (codecs contains 'avc') for hardware decode compatibility
          final avcStream = candidates
              .where((v) => (v['codecs'] ?? '').toString().startsWith('avc'))
              .toList();
          final selected = avcStream.isNotEmpty
              ? avcStream.first
              : candidates.last;
          videoUrl = selected['base_url'] ?? selected['baseUrl'];
          debugPrint('[SimpleBili] Mobile codec: ${selected['codecs']}');
        } else {
          // Desktop: use first (highest quality codec)
          videoUrl =
              candidates.first['base_url'] ?? candidates.first['baseUrl'];
          debugPrint(
            '[SimpleBili] Desktop codec: ${candidates.first['codecs']}',
          );
        }
      }

      // Select highest quality audio stream
      if (audios.isNotEmpty) {
        audioUrl = audios[0]['base_url'] ?? audios[0]['baseUrl'];
      }
    } else if (playUrlInfo['durl'] != null &&
        (playUrlInfo['durl'] as List).isNotEmpty) {
      // Fallback to legacy FLV/MP4 combined stream
      videoUrl = playUrlInfo['durl'][0]['url'];
    }

    if (videoUrl != null &&
        (videoUrl != _currentUrl || currentQn != _currentQuality)) {
      _currentUrl = videoUrl;
      _currentQuality = currentQn;

      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com',
      };

      debugPrint('[SimpleBili] videoUrl: ${videoUrl.substring(0, 80)}...');
      debugPrint(
        '[SimpleBili] audioUrl: ${audioUrl != null ? audioUrl.substring(0, 80) : "null"}...',
      );

      // Open video with httpHeaders (media_kit handles per-file headers for video)
      await player.open(Media(videoUrl, httpHeaders: headers));
      debugPrint('[SimpleBili] player.open() called');

      // After video is loading, dynamically add audio track via mpv command
      if (audioUrl != null && player.platform is NativePlayer) {
        final nativePlayer = player.platform as NativePlayer;

        // Set HTTP headers globally for the audio-add request
        // Use change-list command for proper string list handling
        await nativePlayer.command([
          'change-list',
          'http-header-fields',
          'clr',
          '',
        ]);
        await nativePlayer.command([
          'change-list',
          'http-header-fields',
          'append',
          'Referer: https://www.bilibili.com',
        ]);
        await nativePlayer.command([
          'change-list',
          'http-header-fields',
          'append',
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        ]);
        debugPrint('[SimpleBili] http-header-fields set via change-list');

        // Use audio-add command to dynamically load external audio track
        await nativePlayer.command(['audio-add', audioUrl, 'select']);
        debugPrint('[SimpleBili] audio-add command executed');
      }
    }
  }

  void _updateSpeed(double speed) {
    player.setRate(speed);
    ref.read(playerProvider(widget.bvid).notifier).setSpeed(speed);
  }

  void _togglePlayPause() {
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) {
        _rightKeyDownTime = DateTime.now();
        _lastSpeed = ref.read(playerProvider(widget.bvid)).speed;
        _updateSpeed(3.0);
      } else if (event is KeyUpEvent) {
        _updateSpeed(_lastSpeed);
        final elapsed = DateTime.now().difference(
          _rightKeyDownTime ?? DateTime.now(),
        );
        if (elapsed.inMilliseconds < 300) {
          player.seek(player.state.position + const Duration(seconds: 4));
        }
        _rightKeyDownTime = null;
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent) {
        _leftKeyDownTime = DateTime.now();
      } else if (event is KeyUpEvent) {
        final elapsed = DateTime.now().difference(
          _leftKeyDownTime ?? DateTime.now(),
        );
        if (elapsed.inMilliseconds < 300) {
          final newPos = player.state.position - const Duration(seconds: 4);
          player.seek(newPos < Duration.zero ? Duration.zero : newPos);
        }
        _leftKeyDownTime = null;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider(widget.bvid));

    if (playerState.playUrlInfo != null) {
      _playVideo(playerState.playUrlInfo!);
    }

    if (playerState.speed != player.state.rate) {
      player.setRate(playerState.speed);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          playerState.videoInfo?['title'] ?? 'Playing',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _handlePlayerKeyEvent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxVideoHeight = constraints.maxHeight * 0.5;
            final desiredHeight = constraints.maxWidth * 9 / 16;
            final videoHeight = desiredHeight > maxVideoHeight
                ? maxVideoHeight
                : desiredHeight;
            final videoWidth = videoHeight * 16 / 9;

            return Column(
              children: [
                SizedBox(
                  height: videoHeight,
                  child: Center(
                    child: SizedBox(
                      width: videoWidth,
                      height: videoHeight,
                      child: Stack(
                        children: [
                          Container(
                            color: Colors.black,
                            child: playerState.isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFFB7299),
                                    ),
                                  )
                                : playerState.error != null
                                ? Center(
                                    child: Text(
                                      'Load failed: ${playerState.error}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Video(
                                    controller: controller,
                                    controls: NoVideoControls,
                                  ),
                          ),
                          if (!playerState.isLoading &&
                              playerState.error == null)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: _togglePlayPause,
                                onLongPressStart: (details) {
                                  if (details.localPosition.dx >
                                      MediaQuery.of(context).size.width / 2) {
                                    _lastSpeed = playerState.speed;
                                    _updateSpeed(3.0);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('3.0x Speeding...'),
                                        duration: Duration(milliseconds: 500),
                                      ),
                                    );
                                  }
                                },
                                onLongPressEnd: (_) {
                                  _updateSpeed(_lastSpeed);
                                },
                              ),
                            ),
                          if (!playerState.isLoading &&
                              playerState.error == null)
                            Positioned.fill(
                              child: StreamBuilder<bool>(
                                stream: player.stream.playing,
                                builder: (context, snapshot) {
                                  final isPlaying = snapshot.data ?? true;
                                  if (isPlaying) {
                                    return const SizedBox.shrink();
                                  }
                                  return Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.pause,
                                        size: 36,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (!playerState.isLoading &&
                              playerState.error == null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildPlayerControlsOverlay(
                                playerState,
                                onFullscreenTap: _enterFullscreen,
                                fullscreenIcon: Icons.fullscreen,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildEngagementBar(playerState),
                Expanded(child: _buildVideoInfoScrollable(playerState)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerControlsOverlay(
    VideoPlayerState state, {
    VoidCallback? onFullscreenTap,
    IconData? fullscreenIcon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(0.6),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _buildProgressBar()),
              const SizedBox(width: 12),
              _buildControlPill(
                _currentQualityLabel(state),
                onTap: () => _showQualitySheet(state),
              ),
              const SizedBox(width: 8),
              _buildControlPill('${state.speed}x 倍速', onTap: _showSpeedSheet),
              if (onFullscreenTap != null && fullscreenIcon != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onFullscreenTap,
                  icon: Icon(fullscreenIcon, color: Colors.white),
                  tooltip: 'Fullscreen',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _enterFullscreen() async {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    if (isMobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(playerProvider(widget.bvid));
              return Scaffold(
                backgroundColor: Colors.black,
                body: Focus(
                  autofocus: true,
                  onKeyEvent: _handlePlayerKeyEvent,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          onLongPressStart: (details) {
                            _lastSpeed = state.speed;
                            _updateSpeed(3.0);
                          },
                          onLongPressEnd: (_) {
                            _updateSpeed(_lastSpeed);
                          },
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Video(
                                  controller: controller,
                                  controls: NoVideoControls,
                                ),
                              ),
                              StreamBuilder<bool>(
                                stream: player.stream.playing,
                                builder: (context, snapshot) {
                                  final isPlaying = snapshot.data ?? true;
                                  if (isPlaying) {
                                    return const SizedBox.shrink();
                                  }
                                  return Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.pause,
                                        size: 36,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                      if (!state.isLoading && state.error == null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildPlayerControlsOverlay(
                            state,
                            onFullscreenTap: () => Navigator.of(context).pop(),
                            fullscreenIcon: Icons.fullscreen_exit,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    if (isMobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final valueMs = _isSeeking
                ? _seekValueMs
                : position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxMs == 0 ? 0.0 : maxMs)
                      .toDouble();

            return Row(
              children: [
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: const Color(0xFFFB7299),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: const Color(0xFFFB7299),
                    ),
                    child: Slider(
                      value: maxMs == 0 ? 0.0 : valueMs,
                      min: 0.0,
                      max: maxMs == 0 ? 1.0 : maxMs,
                      onChangeStart: (_) {
                        setState(() {
                          _isSeeking = true;
                        });
                      },
                      onChanged: (value) {
                        setState(() {
                          _seekValueMs = value;
                        });
                      },
                      onChangeEnd: (value) {
                        player.seek(Duration(milliseconds: value.toInt()));
                        setState(() {
                          _isSeeking = false;
                        });
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControlPill(String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Future<void> _showSpeedSheet() async {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: speeds.map((speed) {
              return ListTile(
                title: Text(
                  '${speed}x',
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: ref.read(playerProvider(widget.bvid)).speed == speed
                    ? const Icon(Icons.check, color: Color(0xFFFB7299))
                    : null,
                onTap: () {
                  _updateSpeed(speed);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showQualitySheet(VideoPlayerState state) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: state.availableQualities.map((quality) {
              final qn = quality['qn'] as int;
              return ListTile(
                title: Text(
                  quality['desc'],
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: state.currentQuality == qn
                    ? const Icon(Icons.check, color: Color(0xFFFB7299))
                    : null,
                onTap: () {
                  ref
                      .read(playerProvider(widget.bvid).notifier)
                      .changeQuality(qn);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _currentQualityLabel(VideoPlayerState state) {
    final current = state.availableQualities.firstWhere(
      (q) => q['qn'] == state.currentQuality,
      orElse: () => {'desc': 'Auto'},
    );
    return current['desc'] ?? 'Auto';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildEngagementBar(VideoPlayerState state) {
    final stat = state.videoInfo?['stat'] ?? {};
    final like = stat['like'] ?? 0;
    final reply = stat['reply'] ?? 0;
    final share = stat['share'] ?? 0;
    final favorite = stat['favorite'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildEngagementItem(Icons.thumb_up_outlined, _formatCount(like)),
          _buildEngagementItem(
            Icons.mode_comment_outlined,
            _formatCount(reply),
          ),
          _buildEngagementItem(Icons.share_outlined, _formatCount(share)),
          _buildFavoriteItem(_formatCount(favorite)),
        ],
      ),
    );
  }

  Widget _buildEngagementItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFavoriteItem(String label) {
    return InkWell(
      onTap: () => _showFavoriteSheet(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.bookmark_border, size: 18, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFavoriteSheet() async {
    final state = ref.read(playerProvider(widget.bvid));
    final aid = state.videoInfo?['aid'];
    if (aid == null) {
      return;
    }

    final service = ref.read(videoServiceProvider);
    final mid = await service.getCurrentUserMid();
    if (mid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to use favorites.')),
      );
      return;
    }

    final folders = await service.getFavoriteFolders(mid);
    if (!mounted) return;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No favorite folders found.')),
      );
      return;
    }

    final selectedIds = <int>{};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    '选择收藏夹',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final id = folder['id'] as int;
                        final title = folder['title'] as String;
                        final isSelected = selectedIds.contains(id);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(
                            title,
                            style: const TextStyle(color: Colors.white),
                          ),
                          activeColor: const Color(0xFFFB7299),
                          onChanged: (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                selectedIds.add(id);
                              } else {
                                selectedIds.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () async {
                                await ref
                                    .read(playerProvider(widget.bvid).notifier)
                                    .addToFavorite(
                                      aid: aid,
                                      folderIds: selectedIds.toList(),
                                    );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFB7299),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('收藏'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _formatCount(num value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    return value.toString();
  }

  Widget _buildVideoInfoScrollable(VideoPlayerState state) {
    return SingleChildScrollView(child: _buildVideoInfo(state));
  }

  Widget _buildVideoInfo(VideoPlayerState state) {
    if (state.isLoading && state.videoInfo == null) {
      return const SizedBox.shrink();
    }

    final info = state.videoInfo ?? {};
    final title = info['title'] ?? 'No Title';
    final desc = info['desc'] ?? 'No Description';
    final owner = info['owner']?['name'] ?? 'Unknown';
    final viewCount = info['stat']?['view']?.toString() ?? '0';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person, size: 18, color: Color(0xFFFB7299)),
              const SizedBox(width: 8),
              Text(
                owner,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.play_circle_outline,
                size: 16,
                color: Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                viewCount,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Description',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              height: 1.5,
              color: Colors.white38,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
