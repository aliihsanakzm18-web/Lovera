import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

/// Kullanıcının kendi girdiği adı.
final userNameProvider = StateProvider<String>((ref) => '');

/// Kullanıcının profil fotoğrafı (yerel dosya yolu veya url).
final userAvatarProvider = StateProvider<String?>((ref) => null);

/// Bağlı bulunulan çift ID'si
final coupleIdProvider = StateProvider<String?>((ref) => null);

/// Partner UID
final partnerUidProvider = StateProvider<String?>((ref) => null);

/// Eşleşen partner (eşleşme yoksa null).
final partnerProvider = StateProvider<AppUser?>((ref) => null);

/// İlişki başlangıç tarihi (kullanıcı seçer).
final startDateProvider = StateProvider<DateTime?>((ref) => null);

/// Kullanıcının eklediği özel günler.
final milestonesProvider = StateProvider<List<Milestone>>((ref) => []);

/// Giriş yapmış kullanıcının anlık bilgileri (konum, pil, şehir vb.)
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

