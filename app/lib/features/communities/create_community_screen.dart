import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/l10n.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import '../locations/wilayat_picker.dart';
import '../locations/wilayat_repository.dart';
import 'community_models.dart';
import 'community_repository.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({
    super.key,
    this.repository,
    this.wilayatRepository,
  });

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final CommunityRepository? repository;
  final WilayatRepository? wilayatRepository;

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final CommunityRepository _communityRepository =
      widget.repository ?? CommunityRepository();
  late final WilayatRepository _wilayats =
      widget.wilayatRepository ?? WilayatRepository.shared;
  // Open by default: a community is always visible, and the organizer opts
  // into requiring the code rather than out of it.
  JoinPolicy _joinPolicy = JoinPolicy.open;
  bool _isLoading = false;

  /// Where the community plays. Required: it is what places the community in
  /// Discover, and there is deliberately no default to fall back on.
  int? _wilayatCode;

  @override
  void initState() {
    super.initState();
    // Warms the cache so the picker opens ready; the label reads it at build.
    _wilayats.load().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  Future<void> _pickWilayat(FormFieldState<int> field) async {
    final picked = await showWilayatPicker(
      context,
      repository: _wilayats,
      selectedCode: _wilayatCode,
    );
    if (picked == null || !mounted) return;
    setState(() => _wilayatCode = picked);
    field.didChange(picked);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final communityId = await _communityRepository.createCommunity(
        name: _nameController.text,
        description: _descriptionController.text,
        joinPolicy: _joinPolicy,
        wilayatCode: _wilayatCode!,
      );
      // After the community exists, and before the screen closes. The record
      // does not delay the close: `track` returns immediately and the RPC
      // finishes on its own, so a slow analytics call cannot hold the organizer
      // on a form whose work is already done.
      ProductAnalytics.instance.track(
        ProductEvent.communityCreated,
        communityId: communityId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.communityCreateFailed)),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.createCommunityTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration:
                      InputDecoration(labelText: l10n.communityNameLabel),
                  maxLength: 50,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.communityNameRequired
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: l10n.communityDescriptionLabel,
                  ),
                  maxLines: 3,
                  maxLength: 200,
                ),
                const SizedBox(height: 8),
                FormField<int>(
                  key: const Key('createCommunityWilayat'),
                  initialValue: _wilayatCode,
                  validator: (value) =>
                      value == null ? l10n.wilayatRequired : null,
                  builder: (field) => WilayatField(
                    label: l10n.communityWilayatLabel,
                    valueText: _wilayatCode == null
                        ? null
                        : _wilayats.cached?.nameOf(
                              _wilayatCode,
                              arabic: wilayatArabic(context),
                            ) ??
                            '—',
                    emptyText: l10n.wilayatRequired,
                    errorText: field.errorText,
                    onTap: () => _pickWilayat(field),
                  ),
                ),
                const SizedBox(height: 8),
                Text(l10n.joinPolicyLabel,
                    style: Theme.of(context).textTheme.labelLarge),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_joinPolicy == JoinPolicy.codeRequired
                      ? l10n.joinPolicyCodeRequired
                      : l10n.joinPolicyOpen),
                  subtitle: Text(_joinPolicy == JoinPolicy.codeRequired
                      ? l10n.joinPolicyCodeRequiredHelp
                      : l10n.joinPolicyOpenHelp),
                  value: _joinPolicy == JoinPolicy.codeRequired,
                  onChanged: (value) => setState(() => _joinPolicy =
                      value ? JoinPolicy.codeRequired : JoinPolicy.open),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.createCommunityButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
