import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/database_service.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/lovera_theme_background.dart';

class MilestonesView extends ConsumerStatefulWidget {
  const MilestonesView({super.key});

  @override
  ConsumerState<MilestonesView> createState() => _MilestonesViewState();
}

class _MilestonesViewState extends ConsumerState<MilestonesView> {
  Stream<List<Milestone>>? _milestonesStream;
  String? _cachedCoupleId;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final coupleId = ref.read(coupleIdProvider);
    _cachedCoupleId = coupleId;
    _milestonesStream = DatabaseService().milestonesStream(coupleId: coupleId);
    DatabaseService().syncDefaultCulturalMilestones(coupleId: coupleId);
  }

  Future<void> _openSheet(BuildContext context, {Milestone? editing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _MilestoneFormSheet(editing: editing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coupleId = ref.watch(coupleIdProvider);

    // Eğer coupleId değiştiyse stream'i güncelle, yoksa mevcut stream'i koru
    if (_cachedCoupleId != coupleId || _milestonesStream == null) {
      _cachedCoupleId = coupleId;
      _milestonesStream = DatabaseService().milestonesStream(coupleId: coupleId);
      DatabaseService().syncDefaultCulturalMilestones(coupleId: coupleId);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Özel Günler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        backgroundColor: LoveraColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni gün ekle'),
      ),
      body: LoveraThemeBackground(
        child: StreamBuilder<List<Milestone>>(
          stream: _milestonesStream,
          builder: (context, snapshot) {
            // Veri varsa (veya önbellekte veri varsa) doğrudan göster, asla git-gel yapma!
            final items = snapshot.data;

            if (snapshot.connectionState == ConnectionState.waiting && items == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final milestoneList = List<Milestone>.from(items ?? []);
            milestoneList.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

            if (milestoneList.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_note_rounded, size: 56, color: LoveraColors.secondary),
                      const SizedBox(height: 14),
                      Text('Henüz özel gün yok',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Yıldönümü, doğum günü ya da ilk tatilinizi ekleyin. Firebase bulutuna anında kaydedilir.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: LoveraColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              itemCount: milestoneList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final m = milestoneList[i];
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: theme.dividerColor),
                    boxShadow: AppTheme.ambientShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LoveraColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: LoveraColors.primary.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${m.daysLeft}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'GÜN KALDI',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    m.title,
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (m.isSystem) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: LoveraColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Özel',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: LoveraColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m.date.day}.${m.date.month}.${m.date.year}',
                              style: theme.textTheme.bodySmall?.copyWith(color: LoveraColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (m.isSystem)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Tooltip(
                            message: 'Bu özel gün sabittir, silinemez veya düzenlenemez.',
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                              color: LoveraColors.textMuted.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      else ...[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: LoveraColors.textMuted,
                          tooltip: 'Düzenle',
                          onPressed: () => _openSheet(context, editing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                          color: LoveraColors.textMuted,
                          tooltip: 'Sil',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Text('Özel Günü Sil'),
                                content: Text('"${m.title}" özel gününü silmek istediğinize emin misiniz?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Vazgeç'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                    child: const Text(
                                      'Sil',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await DatabaseService().deleteMilestone(m.id, coupleId: coupleId);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MilestoneFormSheet extends ConsumerStatefulWidget {
  const _MilestoneFormSheet({this.editing});
  final Milestone? editing;

  @override
  ConsumerState<_MilestoneFormSheet> createState() => _MilestoneFormSheetState();
}

class _MilestoneFormSheetState extends ConsumerState<_MilestoneFormSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(text: widget.editing?.title ?? '');
  late DateTime _date = widget.editing?.date ?? DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Özel Günü Düzenle' : 'Yeni Özel Gün',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Başlık (ör: Yıldönümümüz, İlk Tatil)'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Başlık zorunludur' : null,
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_rounded, color: LoveraColors.primary),
              title: Text('${_date.day}.${_date.month}.${_date.year}'),
              subtitle: const Text('Tarihi değiştirmek için dokunun'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1950),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (!_form.currentState!.validate()) return;
                  final coupleId = ref.read(coupleIdProvider);
                  if (isEditing) {
                    await DatabaseService().updateMilestone(
                      milestoneId: widget.editing!.id,
                      title: _title.text.trim(),
                      date: _date,
                      coupleId: coupleId,
                    );
                  } else {
                    await DatabaseService().addMilestone(
                      title: _title.text.trim(),
                      date: _date,
                      coupleId: coupleId,
                    );
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(isEditing ? 'Kaydet' : 'Oluştur'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
