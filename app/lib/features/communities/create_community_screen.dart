import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'community_models.dart';
import 'community_repository.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _communityRepository = CommunityRepository();
  // Open by default: a community is always visible, and the organizer opts
  // into requiring the code rather than out of it.
  JoinPolicy _joinPolicy = JoinPolicy.open;
  bool _isLoading = false;

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
      await _communityRepository.createCommunity(
        name: _nameController.text,
        description: _descriptionController.text,
        joinPolicy: _joinPolicy,
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
      appBar: AppBar(title: Text(l10n.createCommunityTitle)),
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
