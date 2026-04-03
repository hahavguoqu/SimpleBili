import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// 基于 LRU 的内存图片缓存管理器
/// 自动驱逐最久未使用的图片，确保不超过内存上限
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._();
  static ImageCacheManager get instance => _instance;

  ImageCacheManager._();

  /// 最大缓存字节数（默认 50MB）
  int maxCacheBytes = 50 * 1024 * 1024;

  /// 当前缓存占用字节
  int _currentBytes = 0;
  int get currentBytes => _currentBytes;

  /// LRU 缓存：key=url, value=图片字节
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// 正在加载中的请求，防止重复请求
  final Map<String, Future<Uint8List?>> _pending = {};

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Referer': 'https://www.bilibili.com',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      responseType: ResponseType.bytes,
    ),
  );

  /// 获取缓存图片，命中时提升到最新
  Uint8List? get(String url) {
    final data = _cache.remove(url);
    if (data != null) {
      _cache[url] = data; // 移到末尾（最近使用）
    }
    return data;
  }

  /// 放入缓存，超出上限时驱逐最旧条目
  void put(String url, Uint8List data) {
    // 如果已存在，先移除旧的
    final old = _cache.remove(url);
    if (old != null) {
      _currentBytes -= old.length;
    }

    _cache[url] = data;
    _currentBytes += data.length;

    // 驱逐最久未使用的条目直到低于上限
    while (_currentBytes > maxCacheBytes && _cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      final removed = _cache.remove(firstKey);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }
  }

  /// 移除指定 url 的缓存
  void remove(String url) {
    final data = _cache.remove(url);
    if (data != null) {
      _currentBytes -= data.length;
    }
  }

  /// 清空全部缓存
  void clear() {
    _cache.clear();
    _currentBytes = 0;
    _pending.clear();
  }

  /// 缓存条目数
  int get length => _cache.length;

  /// 异步获取图片，优先走缓存
  Future<Uint8List?> fetch(String url) async {
    // 1. 内存命中
    final cached = get(url);
    if (cached != null) return cached;

    // 2. 合并重复请求
    if (_pending.containsKey(url)) {
      return _pending[url];
    }

    // 3. 发起网络请求
    final future = _download(url);
    _pending[url] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _pending.remove(url);
    }
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final response = await _dio.get<List<int>>(url);
      if (response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        put(url, bytes);
        return bytes;
      }
    } catch (_) {
      // 网络错误，返回 null
    }
    return null;
  }
}

/// 带内存缓存的网络图片 Widget
class CachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? errorBuilder;

  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  Uint8List? _data;
  bool _hasError = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  void _load() {
    if (widget.url.isEmpty) {
      setState(() {
        _hasError = true;
        _loading = false;
      });
      return;
    }

    // 同步检查缓存
    final cached = ImageCacheManager.instance.get(widget.url);
    if (cached != null) {
      _data = cached;
      _hasError = false;
      _loading = false;
      return;
    }

    _loading = true;
    _hasError = false;

    ImageCacheManager.instance.fetch(widget.url).then((bytes) {
      if (!mounted) return;
      setState(() {
        _data = bytes;
        _hasError = bytes == null;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Container(color: Colors.grey[900]),
      );
    }

    if (_hasError || _data == null) {
      return widget.errorBuilder?.call(context) ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[900],
            child: const Icon(Icons.broken_image, color: Colors.white24),
          );
    }

    return Image.memory(
      _data!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}
