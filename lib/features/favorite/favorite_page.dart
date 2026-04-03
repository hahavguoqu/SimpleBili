import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'favorite_provider.dart';
import '../../shared/video_card.dart';
import '../../shared/image_cache_manager.dart';

/// 收藏夹列表页 — 展示用户创建的所有收藏夹
class FavoritePage extends ConsumerWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(favoriteListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(favoriteListProvider.notifier).load(),
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FavoriteListState state) {
    if (state.isLoading && state.folders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.folders.isEmpty) {
      return Center(child: Text('加载失败: ${state.error}'));
    }
    if (state.folders.isEmpty) {
      return const Center(child: Text('暂无收藏夹'));
    }
    return ListView.builder(
      itemCount: state.folders.length,
      itemBuilder: (context, index) {
        final folder = state.folders[index];
        final mediaCount = folder['media_count'] ?? 0;
        final cover = folder['cover'] ?? '';
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: cover.isNotEmpty
                ? CachedImage(
                    url: cover,
                    width: 80,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_) => Container(
                      width: 80,
                      height: 50,
                      color: Colors.grey[800],
                      child: const Icon(Icons.folder, color: Colors.white38),
                    ),
                  )
                : Container(
                    width: 80,
                    height: 50,
                    color: Colors.grey[800],
                    child: const Icon(Icons.folder, color: Colors.white38),
                  ),
          ),
          title: Text(folder['title'] ?? '未命名'),
          subtitle: Text('$mediaCount 个内容'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final id = folder['id'];
            if (id != null) {
              context.push('/favorite/$id');
            }
          },
        );
      },
    );
  }
}

/// 收藏夹详情页 — 展示某个收藏夹内的视频
class FavoriteDetailPage extends ConsumerStatefulWidget {
  final int mediaId;

  const FavoriteDetailPage({super.key, required this.mediaId});

  @override
  ConsumerState<FavoriteDetailPage> createState() => _FavoriteDetailPageState();
}

class _FavoriteDetailPageState extends ConsumerState<FavoriteDetailPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(favoriteDetailProvider(widget.mediaId).notifier).loadMore();
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatCount(dynamic count) {
    if (count == null) return '0';
    final n = count is int ? count : int.tryParse(count.toString()) ?? 0;
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoriteDetailProvider(widget.mediaId));

    return Scaffold(
      appBar: AppBar(title: Text(state.info?['title'] ?? '收藏夹')),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(favoriteDetailProvider(widget.mediaId).notifier).load(),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(FavoriteDetailState state) {
    if (state.isLoading && state.videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.videos.isEmpty) {
      return Center(child: Text('加载失败: ${state.error}'));
    }
    if (state.videos.isEmpty) {
      return const Center(child: Text('收藏夹为空'));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: state.videos.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.videos.length) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFB7299)),
          );
        }
        final video = state.videos[index];
        final bvid = video['bvid'] ?? video['bv_id'] ?? '';
        final cnt = video['cnt_info'] ?? {};
        return VideoCard(
          title: video['title'] ?? '',
          cover: video['cover'] ?? '',
          author: video['upper']?['name'] ?? '',
          viewCount: _formatCount(cnt['play']),
          duration: _formatDuration(video['duration'] ?? 0),
          onTap: () {
            if (bvid.isNotEmpty) {
              context.push('/player/$bvid');
            }
          },
        );
      },
    );
  }
}
