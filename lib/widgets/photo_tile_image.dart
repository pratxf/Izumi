import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders a photo thumbnail with a transparent placeholder and an automatic
/// fallback to the full-resolution URL when the thumbnail URL fails to load.
///
/// The thumbnail and full URLs are cached separately by `CachedNetworkImage`
/// using the URL as the cache key, so a thumbnail loaded here will be reused
/// instantly by `ImageDetailScreen`.
class PhotoTileImage extends StatelessWidget {
  final String thumbUrl;
  final String fullUrl;
  final BoxFit fit;

  const PhotoTileImage({
    super.key,
    required this.thumbUrl,
    required this.fullUrl,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (thumbUrl.isEmpty && fullUrl.isEmpty) {
      return _missing();
    }
    final primary = thumbUrl.isNotEmpty ? thumbUrl : fullUrl;
    final fallback = (fullUrl.isNotEmpty && fullUrl != primary) ? fullUrl : '';

    return CachedNetworkImage(
      imageUrl: primary,
      fit: fit,
      placeholder: (_, __) => Container(color: Colors.grey[200]),
      errorWidget: (_, __, ___) {
        if (fallback.isEmpty) return _broken();
        return CachedNetworkImage(
          imageUrl: fallback,
          fit: fit,
          placeholder: (_, __) => Container(color: Colors.grey[200]),
          errorWidget: (_, __, ___) => _broken(),
        );
      },
    );
  }

  Widget _missing() => Container(
        color: Colors.grey[300],
        child: Icon(Icons.image_not_supported, color: Colors.grey[500]),
      );

  Widget _broken() => Container(
        color: Colors.grey[300],
        child: Icon(Icons.broken_image, color: Colors.grey[500]),
      );
}
