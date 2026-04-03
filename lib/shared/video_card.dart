import 'package:flutter/material.dart';
import 'image_cache_manager.dart';

class VideoCard extends StatelessWidget {
  final String title;
  final String cover;
  final String author;
  final String viewCount;
  final String duration;
  final String? date;
  final VoidCallback onTap;

  const VideoCard({
    super.key,
    required this.title,
    required this.cover,
    required this.author,
    required this.viewCount,
    required this.duration,
    this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with Overlays
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedImage(
                    url: cover,
                    fit: BoxFit.cover,
                    errorBuilder: (context) => Container(
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                  // Bottom Gradient & Stats
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            viewCount,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
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
          const SizedBox(height: 8),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Author & Date
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.account_box_outlined,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
                if (date != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    date!,
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
