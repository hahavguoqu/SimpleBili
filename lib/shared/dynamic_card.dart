import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'image_cache_manager.dart';

class DynamicCard extends StatelessWidget {
  final String authorName;
  final String authorFace;
  final String publishTime;
  final String title;
  final String cover;
  final String viewCount;
  final String danmakuCount;
  final String duration;
  final String likeCount;
  final String commentCount;
  final String forwardCount;
  final String shareUrl;
  final VoidCallback onAuthorTap;
  final VoidCallback onTap;

  const DynamicCard({
    super.key,
    required this.authorName,
    required this.authorFace,
    required this.publishTime,
    required this.title,
    required this.cover,
    required this.viewCount,
    required this.danmakuCount,
    required this.duration,
    required this.likeCount,
    required this.commentCount,
    required this.forwardCount,
    required this.shareUrl,
    required this.onAuthorTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author Profile Row
              GestureDetector(
                onTap: onAuthorTap,
                child: Row(
                  children: [
                    ClipOval(
                      child: CachedImage(
                        url: authorFace,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_) => CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey[800],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            "$publishTime · Posted a video",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.more_vert, color: Colors.white.withOpacity(0.5)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Video Content Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        CachedImage(
                          url: cover,
                          width: 160,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (context) => Container(
                            width: 160,
                            height: 90,
                            color: Colors.grey[900],
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              duration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildStatIcon(
                              Icons.play_circle_outline,
                              viewCount,
                            ),
                            const SizedBox(width: 16),
                            _buildStatIcon(
                              Icons.message_outlined,
                              danmakuCount,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.white10),
              const SizedBox(height: 12),
              // Interaction Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFooterAction(
                    context,
                    Icons.share_outlined,
                    forwardCount == "0" ? "Share" : forwardCount,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: shareUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied to clipboard'),
                        ),
                      );
                    },
                  ),
                  _buildFooterAction(
                    context,
                    Icons.mode_comment_outlined,
                    commentCount,
                  ),
                  _buildFooterAction(
                    context,
                    Icons.thumb_up_outlined,
                    likeCount,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatIcon(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.4)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFooterAction(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? Colors.white.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
