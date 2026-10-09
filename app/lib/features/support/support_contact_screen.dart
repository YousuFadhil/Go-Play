import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../infrastructure/platform/support_whatsapp_launcher.dart';
import 'support_repository.dart';
import 'support_whatsapp_link.dart';

/// A user-initiated WhatsApp handoff, not an in-app chat or message sender.
class SupportContactScreen extends StatefulWidget {
  const SupportContactScreen({
    super.key,
    this.repository,
    this.openWhatsApp,
  });

  final SupportRepository? repository;

  /// UI tests inject this; production launches the official wa.me link.
  final Future<bool> Function(Uri uri)? openWhatsApp;

  @override
  State<SupportContactScreen> createState() => _SupportContactScreenState();
}

class _SupportContactScreenState extends State<SupportContactScreen> {
  late final SupportRepository _repository =
      widget.repository ?? SupportRepository();
  late Future<String?> _phoneFuture = _repository.fetchWhatsAppPhone();
  final _message = TextEditingController();
  int _reason = 0;
  bool _opening = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
        _phoneFuture = _repository.fetchWhatsAppPhone();
      });

  Future<void> _open(String phone) async {
    if (_opening || _message.text.trim().isEmpty) return;
    final l10n = context.l10n;
    final reasons = [
      l10n.supportReasonTechnical,
      l10n.supportReasonSuggestion,
      l10n.supportReasonQuestion,
      l10n.supportReasonOther,
    ];
    final url = SupportWhatsAppLink.build(
      phone: phone,
      reason: reasons[_reason],
      message: _message.text,
    );
    setState(() => _opening = true);
    try {
      final opened = await (widget.openWhatsApp ??
          const SupportWhatsAppLauncher().open)(url);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.supportOpenFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.supportOpenFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reasons = [
      l10n.supportReasonTechnical,
      l10n.supportReasonSuggestion,
      l10n.supportReasonQuestion,
      l10n.supportReasonOther,
    ];

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.supportContactTitle)),
      body: FutureBuilder<String?>(
        future: _phoneFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _refresh);
          }
          final phone = SupportWhatsAppLink.normalizePhone(snapshot.data);
          return ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(
                l10n.supportContactIntro,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Gap.lg),
              DropdownButtonFormField<int>(
                initialValue: _reason,
                decoration:
                    InputDecoration(labelText: l10n.supportCategoryLabel),
                items: [
                  for (var i = 0; i < reasons.length; i++)
                    DropdownMenuItem(value: i, child: Text(reasons[i])),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _reason = value);
                },
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _message,
                maxLines: 5,
                maxLength: 1200,
                decoration: InputDecoration(
                  labelText: l10n.supportMessageLabel,
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (phone == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: Text(
                    l10n.supportPhoneNotConfigured,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              FilledButton.icon(
                key: const Key('openWhatsAppSupport'),
                onPressed:
                    _opening || phone == null || _message.text.trim().isEmpty
                        ? null
                        : () => _open(phone),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.supportOpenWhatsApp),
              ),
            ],
          );
        },
      ),
    );
  }
}
