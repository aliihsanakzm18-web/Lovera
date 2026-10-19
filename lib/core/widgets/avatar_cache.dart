import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AvatarCache {
  static final Map<String, ImageProvider> _providerCache = <String, ImageProvider>{};
  static final Map<String, Uint8List> _bytesCache = <String, Uint8List>{};

  static ImageProvider? getProvider(String? path) {
    if (path == null || path.isEmpty) return null;

    final cached = _providerCache[path];
    if (cached != null) return cached;

    ImageProvider? provider;
    if (path.startsWith('data:image')) {
      try {
        final clean = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(clean);
        _bytesCache[path] = bytes;
        provider = MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      provider = CachedNetworkImageProvider(path);
    } else {
      final file = File(path);
      if (file.existsSync()) {
        provider = FileImage(file);
      }
    }

    if (provider != null) {
      _providerCache[path] = provider;
    }
    return provider;
  }

  static Uint8List? getBytes(String? path) {
    if (path == null || path.isEmpty) return null;
    final cached = _bytesCache[path];
    if (cached != null) return cached;

    if (path.startsWith('data:image')) {
      try {
        final clean = path.contains(',') ? path.split(',').last : path;
        final bytes = base64Decode(clean);
        _bytesCache[path] = bytes;
        return bytes;
      } catch (_) {}
    }
    return null;
  }
}

class LoveraAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String fallbackLetter;
  final double radius;
  final Color? backgroundColor;

  const LoveraAvatar({
    super.key,
    required this.avatarUrl,
    required this.fallbackLetter,
    this.radius = 28,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final provider = AvatarCache.getProvider(avatarUrl);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? (isDark ? LoveraColors.darkSurfaceAlt : Colors.white),
        border: Border.all(
          color: isDark
              ? LoveraColors.primary.withValues(alpha: 0.45)
              : LoveraColors.primary.withValues(alpha: 0.35),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: provider != null
            ? Image(
                image: provider,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _buildFallback(context),
              )
            : _buildFallback(context),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    final letter = fallbackLetter.trim().isNotEmpty ? fallbackLetter.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}
