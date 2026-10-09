import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'support_repository.dart';
import 'support_whatsapp_link.dart';

/// Only surfaced in the System Admin console. The database enforces the role
/// again through admin_set_support_whatsapp_phone, regardless of navigation.
class AdminSupportPhoneScreen extends StatefulWidget {
  const AdminSupportPhoneScreen({super.key, this.repository});

  final SupportRepository? repository;

  @override
  State<AdminSupportPhoneScreen> createState() =>
      _AdminSupportPhoneScreenState();
}

class _AdminSupportPhoneScreenState extends State<AdminSupportPhoneScreen> {
  late final SupportRepository _repository =
      widget.repository ?? SupportRepository();
  late Future<String?> _phoneFuture = _repository.fetchWhatsAppPhone();
  final _phone = TextEditingController();
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _initialized = false;
        _phoneFuture = _repository.fetchWhatsAppPhone();
      });

  Future<void> _save() async {
    if (_saving) return;
    final raw = _phone.text.trim();
    final normalized = SupportWhatsAppLink.normalizePhone(raw);
    final l10n = context.l10n;
    if (raw.isNotEmpty && normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.supportPhoneInvalid)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _repository.setWhatsAppPhone(normalized);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.supportPhoneSaved)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.genericError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppHeader(title: Text(l10n.supportAdminPhoneTitle)),
      body: FutureBuilder<String?>(
        future: _phoneFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _reload);
          }
          if (!_initialized) {
            _initialized = true;
            _phone.text = snapshot.data ?? '';
          }
          return ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(l10n.supportAdminPhoneHelp),
              const SizedBox(height: Gap.lg),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                // A phone number reads left to right even in an RTL layout;
                // otherwise the leading '+' is drawn after the digits.
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l10n.supportPhoneLabel,
                  hintText: '+968XXXXXXXX',
                ),
              ),
              const SizedBox(height: Gap.lg),
              FilledButton(
                key: const Key('saveSupportPhone'),
                onPressed: _saving ? null : _save,
                child: Text(l10n.supportSavePhone),
              ),
            ],
          );
        },
      ),
    );
  }
}
