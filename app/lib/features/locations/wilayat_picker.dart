import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'wilayat_models.dart';
import 'wilayat_repository.dart';

/// Whether the reader's language is Arabic, which is what picks a Wilayat's
/// name. Anything else reads the English one.
bool wilayatArabic(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar';

/// Opens the Wilayat picker and answers with the chosen code, or null when the
/// reader dismissed it.
///
/// **One picker for every place a Wilayat is chosen** -- the Near chip, a new
/// community, a community's owner and a player's Default Location -- so the four
/// cannot drift into four searches with four ideas of what matches.
///
/// It answers with a code and does nothing else: what a choice *means* (a
/// session override, a saved setting, a required field) is the caller's.
Future<int?> showWilayatPicker(
  BuildContext context, {
  required WilayatRepository repository,
  int? selectedCode,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _WilayatPickerSheet(
      repository: repository,
      selectedCode: selectedCode,
    ),
  );
}

class _WilayatPickerSheet extends StatefulWidget {
  const _WilayatPickerSheet({
    required this.repository,
    required this.selectedCode,
  });

  final WilayatRepository repository;
  final int? selectedCode;

  @override
  State<_WilayatPickerSheet> createState() => _WilayatPickerSheetState();
}

class _WilayatPickerSheetState extends State<_WilayatPickerSheet> {
  late Future<WilayatCatalog> _catalog = widget.repository.load();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _catalog = widget.repository.load());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final arabic = wilayatArabic(context);

    return Padding(
      // Lifted above the keyboard, so the results stay in view while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(
                l10n.wilayatPickerTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: TextField(
                key: const Key('wilayatSearchField'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.wilayatSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: FutureBuilder<WilayatCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final catalog = snapshot.data;
                  if (snapshot.hasError || catalog == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.loadFailed),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _retry,
                            child: Text(l10n.retryButton),
                          ),
                        ],
                      ),
                    );
                  }
                  final groups = catalog.groups(query: _query);
                  if (groups.isEmpty) {
                    return Center(child: Text(l10n.wilayatSearchEmpty));
                  }
                  return ListView(
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            20,
                            12,
                            20,
                            4,
                          ),
                          child: Text(
                            group.governorate.name(arabic: arabic),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        for (final wilayat in group.wilayats)
                          ListTile(
                            key: Key('wilayat_${wilayat.code}'),
                            title: Text(wilayat.name(arabic: arabic)),
                            selected: wilayat.code == widget.selectedCode,
                            trailing: wilayat.code == widget.selectedCode
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () =>
                                Navigator.of(context).pop(wilayat.code),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only field that opens the picker: a label, the current Wilayat (or
/// [emptyText]) and, when [onClear] is given and something is chosen, a way to
/// go back to none.
class WilayatField extends StatelessWidget {
  const WilayatField({
    super.key,
    required this.label,
    required this.valueText,
    required this.emptyText,
    required this.onTap,
    this.onClear,
    this.clearTooltip,
    this.errorText,
    this.helperText,
    this.busy = false,
  });

  final String label;

  /// The chosen Wilayat's name, or null when none is chosen.
  final String? valueText;
  final String emptyText;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final String? clearTooltip;
  final String? errorText;
  final String? helperText;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final chosen = valueText != null;
    return InkWell(
      onTap: busy ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          helperText: helperText,
          suffixIcon: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : chosen && onClear != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: clearTooltip,
                      onPressed: onClear,
                    )
                  : const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          valueText ?? emptyText,
          style: chosen ? null : TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}
