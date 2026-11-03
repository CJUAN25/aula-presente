import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../data/firestore_demo_records_repository.dart';
import '../domain/demo_record.dart';
import '../domain/demo_records_repository.dart';
import 'demo_records_messages.dart';
import 'demo_record_detail_screen.dart';
import 'demo_record_form_screen.dart';

class DemoRecordsScreen extends StatefulWidget {
  const DemoRecordsScreen({super.key, this.repository});

  final DemoRecordsRepository? repository;

  @override
  State<DemoRecordsScreen> createState() => _DemoRecordsScreenState();
}

class _DemoRecordsScreenState extends State<DemoRecordsScreen> {
  late final DemoRecordsRepository _repository;
  late Stream<List<DemoRecord>> _records;
  final Set<String> _openingRecords = {};
  bool _openingForm = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreDemoRecordsRepository();
    _records = _repository.watchRecords();
  }

  void _retry() => setState(() => _records = _repository.watchRecords());

  Future<void> _openForm() async {
    if (_openingForm) return;
    setState(() => _openingForm = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DemoRecordFormScreen(repository: _repository),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingForm = false);
    }
  }

  Future<void> _openRecord(DemoRecord record) async {
    if (!_openingRecords.add(record.id)) return;
    setState(() {});
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DemoRecordDetailScreen(
            recordId: record.id,
            repository: _repository,
          ),
        ),
      );
    } finally {
      _openingRecords.remove(record.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registros de prueba')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openingForm ? null : _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo registro'),
      ),
      body: StreamBuilder<List<DemoRecord>>(
        stream: _records,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: demoRecordsErrorMessage(snapshot.error),
              onRetry: _retry,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data ?? const <DemoRecord>[];
          if (records.isEmpty) return const _EmptyRecords();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            itemCount: records.length + 1,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 14 : 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Text(
                  'Estos registros son de prueba y pertenecen a tu cuenta.',
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                );
              }
              final record = records[index - 1];
              final opening = _openingRecords.contains(record.id);
              return _RecordTile(
                record: record,
                opening: opening,
                onTap: opening ? null : () => _openRecord(record),
              );
            },
          );
        },
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.record,
    required this.opening,
    required this.onTap,
  });

  final DemoRecord record;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: AppColors.primary,
                size: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (record.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        record.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (opening)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 52,
            color: AppColors.information,
          ),
          const SizedBox(height: 16),
          Text(
            'Aún no tienes registros',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: AppColors.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Crea uno para probar las operaciones de esta entrega.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.danger,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
