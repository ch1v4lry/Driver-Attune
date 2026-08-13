import 'package:flutter/material.dart';

import 'drowsiness_evidence_store.dart';

/// Shows the drowsiness photos saved on this phone.
class EvidenceGalleryScreen extends StatefulWidget {
  const EvidenceGalleryScreen({super.key, required this.store});

  final DrowsinessEvidenceStore store;

  @override
  State<EvidenceGalleryScreen> createState() => _EvidenceGalleryScreenState();
}

class _EvidenceGalleryScreenState extends State<EvidenceGalleryScreen> {
  List<DrowsinessEvidence>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.list();
    if (!mounted) {
      return;
    }
    setState(() => _items = items);
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all photos?'),
        content: const Text(
          'This permanently erases every drowsiness photo saved on this phone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.deleteAll();
      await _load();
    }
  }

  Future<void> _confirmDelete(DrowsinessEvidence item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.delete(item);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drowsiness photos'),
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete all',
              onPressed: _confirmDeleteAll,
            ),
        ],
      ),
      body: switch (items) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const _EmptyState(),
        _ => _Grid(items: items, onDelete: _confirmDelete),
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 44,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No photos yet',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'A photo is saved here each time drowsiness is detected while '
              'driving, so you can see what the app caught.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items, required this.onDelete});

  final List<DrowsinessEvidence> items;
  final ValueChanged<DrowsinessEvidence> onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Stored on this phone only — never uploaded, shared, or collected.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _Tile(
              item: items[i],
              onDelete: () => onDelete(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onDelete});

  final DrowsinessEvidence item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _openFullScreen(context),
              child: Image.file(
                item.file,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatTimestamp(item.capturedAt),
                    style: textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_formatTimestamp(item.capturedAt))),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(child: Image.file(item.file)),
          ),
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}  '
      '${two(at.hour)}:${two(at.minute)}';
}
