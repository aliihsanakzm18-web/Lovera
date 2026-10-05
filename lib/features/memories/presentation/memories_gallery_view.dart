import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class MemoriesGalleryView extends StatelessWidget {
  const MemoriesGalleryView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ortak Anılarımız')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 56, color: LoveraColors.secondary),
              const SizedBox(height: 14),
              Text('Henüz anı yok',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Fotoğraf ekleme yakında burada olacak.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
