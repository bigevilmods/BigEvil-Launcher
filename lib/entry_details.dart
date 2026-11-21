import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'dashboard.dart';
import 'library.dart';
import 'online_browser.dart';

class EntryDetails extends StatefulWidget {
  const EntryDetails({
    super.key,
    required this.entry,
    required this.onOpen,
    this.onEdit,
  });

  final Entry entry;
  final Future<void> Function(Entry) onOpen;
  final Future<Entry?> Function(Entry)? onEdit;

  @override
  State<EntryDetails> createState() => _EntryDetailsState();
}

class _EntryDetailsState extends State<EntryDetails> {
  late Entry _entry = widget.entry;

  Future<void> _edit() async {
    final edited = await widget.onEdit?.call(_entry);
    if (edited != null && mounted) setState(() => _entry = edited);
  }

  Future<void> _openLink(String address) async {
    try {
      await Library.openWebLink(address);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao abrir o endereço: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final game = entry.kind == Kind.game;
    final online = Library.webUri(entry.onlineUrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              tooltip: 'Editar item',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _DetailImage(
                            path: entry.backgroundPath ?? entry.coverPath,
                            width: 1440,
                            fallback: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xff225064),
                                    Color(0xff3f2852),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x2411141c), Color(0xf3161820)],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 62, 16, 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 104,
                                  height: 132,
                                  child: _DetailImage(
                                    path: entry.coverPath,
                                    width: 360,
                                    fallback: ColoredBox(
                                      color: const Color(0xff292d3b),
                                      child: Icon(
                                        game
                                            ? Icons.sports_esports_outlined
                                            : Icons.apps,
                                        color: dashboardCyan,
                                        size: 42,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    if (entry.developer.isNotEmpty)
                                      Text(
                                        entry.developer,
                                        style: const TextStyle(
                                          color: dashboardMuted,
                                          fontSize: 16,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (entry.target.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => widget.onOpen(entry),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(game ? 'Jogar' : 'Abrir'),
                        ),
                      if (online != null)
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OnlineBrowser(
                                title: entry.name,
                                initialUrl: online,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.language),
                          label: Text(game ? 'Jogar online' : 'Abrir online'),
                        ),
                      if (Library.isWebLink(entry.downloadUrl))
                        OutlinedButton.icon(
                          onPressed: () => _openLink(entry.downloadUrl),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Baixar'),
                        ),
                      if (Library.isWebLink(entry.repositoryUrl))
                        OutlinedButton.icon(
                          onPressed: () => _openLink(entry.repositoryUrl),
                          icon: const Icon(Icons.code),
                          label: const Text('Repositório'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Descrição',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    entry.description.isEmpty
                        ? 'Nenhuma descrição cadastrada.'
                        : entry.description,
                    style: const TextStyle(color: dashboardMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  const _DetailImage({
    required this.path,
    required this.width,
    required this.fallback,
  });

  final String? path;
  final int width;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => switch (path) {
    final path? => Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: width,
      errorBuilder: (_, _, _) => fallback,
    ),
    null => fallback,
  };
}
