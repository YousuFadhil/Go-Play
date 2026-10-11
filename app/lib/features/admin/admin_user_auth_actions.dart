import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../auth/auth_service.dart' show AuthService;
import 'admin_models.dart';
import 'admin_repository.dart';

/// The three sign-in actions on another account (migration `0103`), each as one dialog opened
/// from the account screen: change email, send a recovery email, set a password.
///
/// Answers `true` when the account was changed, or may have been, so the screen reads it again;
/// `false` or nothing otherwise.
///
/// **What this does not decide.** Whether the administrator may do it, and to whom, is the
/// server's, asked twice before anything is changed. The buttons that open this are hidden for
/// the administrator's own account and for a System Admin, and the change-email one is disabled
/// for a Google-linked account, but that is wording; the server refuses regardless.
///
/// **Three services are not one transaction, and this says so.** An email change is the Auth
/// service changing it, the email provider sending the recovery mail, and the audit trail
/// recording it. The result view tells which of them did what, and when the email changed but the
/// mail did not go, it keeps the change in place and offers the mail again.
///
/// **The password.** It lives in a controller and nowhere else: not in this widget's state, not in
/// a failure, not in a log. The controllers are cleared when the action succeeds and again when
/// the dialog is closed.
Future<bool?> showAdminUserAuthDialog(
  BuildContext context, {
  required AdminUserAuthAction action,
  required AdminUserAccount account,
  required AdminRepository repository,
}) =>
    showDialog<bool>(
      context: context,
      // An outside tap must not hide a request that is in flight.
      barrierDismissible: false,
      builder: (_) => _AdminUserAuthDialog(
        action: action,
        account: account,
        repository: repository,
      ),
    );

class _AdminUserAuthDialog extends StatefulWidget {
  const _AdminUserAuthDialog({
    required this.action,
    required this.account,
    required this.repository,
  });

  final AdminUserAuthAction action;
  final AdminUserAccount account;
  final AdminRepository repository;

  @override
  State<_AdminUserAuthDialog> createState() => _AdminUserAuthDialogState();
}

class _AdminUserAuthDialogState extends State<_AdminUserAuthDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _emailAgain = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  final _reason = TextEditingController();

  bool _busy = false;
  Failure? _failure;
  AdminUserAuthResult? _result;

  /// An answer was lost: the change may have been applied. Closing reads the account again.
  bool _mayHaveChanged = false;

  bool _retrying = false;
  Failure? _retryFailure;

  bool get _changed =>
      (_result?.emailChanged ?? false) ||
      (_result?.passwordSet ?? false) ||
      _mayHaveChanged;

  @override
  void dispose() {
    // Whatever was typed does not outlive the dialog.
    _password.clear();
    _passwordAgain.clear();
    _email.dispose();
    _emailAgain.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final id = widget.account.id;
    try {
      final result = switch (widget.action) {
        AdminUserAuthAction.changeEmail =>
          await widget.repository.changeUserEmail(
            id,
            newEmail: _email.text,
            reason: _reason.text,
            redirectTo: AuthService.recoveryRedirect,
          ),
        AdminUserAuthAction.sendRecovery =>
          await widget.repository.sendUserRecovery(
            id,
            reason: _reason.text,
            redirectTo: AuthService.recoveryRedirect,
          ),
        AdminUserAuthAction.setPassword =>
          await widget.repository.setUserPassword(
            id,
            password: _password.text,
            reason: _reason.text,
          ),
      };
      if (!mounted) return;
      _password.clear();
      _passwordAgain.clear();
      setState(() {
        _busy = false;
        _result = result;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = failure;
        // A lost answer (or a dropped connection) on a change leaves it unknown whether it was
        // applied. Sending a recovery email changes nothing, so nothing is unknown there.
        if (widget.action != AdminUserAuthAction.sendRecovery &&
            (failure.reason == FailureReason.authOutcomeUnknown ||
                failure is NetworkFailure)) {
          _mayHaveChanged = true;
        }
      });
    }
  }

  /// The recovery email again, after an email change that was made but not followed by the
  /// mail. The same request as "Send recovery email": it reads the account's address afresh,
  /// so it is safe to repeat.
  Future<void> _retryRecovery() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryFailure = null;
    });
    try {
      final again = await widget.repository.sendUserRecovery(
        widget.account.id,
        reason: _reason.text,
        redirectTo: AuthService.recoveryRedirect,
      );
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _result = _result!.withRecoverySent(auditRecorded: again.auditRecorded);
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _retryFailure = failure;
      });
    }
  }

  void _close() => Navigator.of(context).pop(_changed);

  String _title(AppLocalizations l10n) => switch (widget.action) {
        AdminUserAuthAction.changeEmail => l10n.adminAuthChangeEmailTitle,
        AdminUserAuthAction.sendRecovery => l10n.adminAuthSendRecoveryTitle,
        AdminUserAuthAction.setPassword => l10n.adminAuthSetPasswordTitle,
      };

  String _submitLabel(AppLocalizations l10n) => switch (widget.action) {
        AdminUserAuthAction.changeEmail => l10n.adminAuthSubmitChangeEmail,
        AdminUserAuthAction.sendRecovery => l10n.adminAuthSubmitSendRecovery,
        AdminUserAuthAction.setPassword => l10n.adminAuthSubmitSetPassword,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;

    return PopScope(
      // Back must not close the dialog under a request in flight.
      canPop: !_busy && !_retrying,
      child: AlertDialog(
        key: const Key('adminAuthDialog'),
        title: Text(_title(l10n)),
        content: SingleChildScrollView(
          child: result == null
              ? _formView(context, l10n)
              : _done(context, l10n, result),
        ),
        actions: result == null
            ? [
                TextButton(
                  key: const Key('adminAuthCancel'),
                  onPressed: _busy ? null : _close,
                  child: Text(l10n.cancelButton),
                ),
                FilledButton(
                  key: const Key('adminAuthSubmit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: Gap.sm),
                            Text(l10n.adminAuthWorking),
                          ],
                        )
                      : Text(_submitLabel(l10n)),
                ),
              ]
            : [
                FilledButton(
                  key: const Key('adminAuthDone'),
                  onPressed: _retrying ? null : _close,
                  child: Text(l10n.adminAuthDoneButton),
                ),
              ],
      ),
    );
  }

  Widget _formView(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final action = widget.action;
    final account = widget.account;

    String? requiredText(String? value, String message) =>
        (value ?? '').trim().isEmpty ? message : null;

    final body = switch (action) {
      AdminUserAuthAction.changeEmail => l10n.adminAuthChangeEmailBody,
      AdminUserAuthAction.sendRecovery =>
        l10n.adminAuthSendRecoveryBody(account.email),
      AdminUserAuthAction.setPassword => l10n.adminAuthSetPasswordBody,
    };

    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (action == AdminUserAuthAction.changeEmail) ...[
            const SizedBox(height: Gap.sm),
            Text(
              l10n.adminAuthCurrentEmail(account.email),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.md),
            TextFormField(
              key: const Key('adminAuthNewEmail'),
              controller: _email,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration:
                  InputDecoration(labelText: l10n.adminAuthNewEmailLabel),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return l10n.emailRequired;
                if (!AuthService.isValidEmail(text)) return l10n.emailInvalid;
                if (text.toLowerCase() == account.email.trim().toLowerCase()) {
                  return l10n.adminAuthEmailSame;
                }
                return null;
              },
            ),
            const SizedBox(height: Gap.sm),
            TextFormField(
              key: const Key('adminAuthNewEmailAgain'),
              controller: _emailAgain,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration:
                  InputDecoration(labelText: l10n.adminAuthConfirmEmailLabel),
              validator: (value) => (value ?? '').trim().toLowerCase() ==
                      _email.text.trim().toLowerCase()
                  ? null
                  : l10n.adminAuthEmailMismatch,
            ),
          ],
          if (action == AdminUserAuthAction.setPassword) ...[
            const SizedBox(height: Gap.md),
            TextFormField(
              key: const Key('adminAuthPassword'),
              controller: _password,
              enabled: !_busy,
              autofocus: true,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: l10n.newPasswordLabel),
              validator: (value) => AuthService.isValidPassword(value ?? '')
                  ? null
                  : l10n.passwordTooShort,
            ),
            const SizedBox(height: Gap.sm),
            TextFormField(
              key: const Key('adminAuthPasswordAgain'),
              controller: _passwordAgain,
              enabled: !_busy,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                  labelText: l10n.adminAuthConfirmPasswordLabel),
              validator: (value) => value == _password.text
                  ? null
                  : l10n.adminAuthPasswordMismatch,
            ),
          ],
          const SizedBox(height: Gap.md),
          TextFormField(
            key: const Key('adminAuthReason'),
            controller: _reason,
            enabled: !_busy,
            maxLength: 500,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.adminAuthReasonLabel,
              counterText: '',
            ),
            validator: (value) =>
                requiredText(value, l10n.adminAuthReasonRequired),
          ),
          if (_failure != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              _failureText(l10n, _failure!, action),
              key: const Key('adminAuthError'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _done(
    BuildContext context,
    AppLocalizations l10n,
    AdminUserAuthResult result,
  ) {
    final theme = Theme.of(context);

    final headline = switch (result.action) {
      AdminUserAuthAction.changeEmail => result.recoverySent
          ? l10n.adminAuthEmailChangedDone
          : switch (result.recoveryProblem) {
              AdminRecoveryProblem.rateLimited =>
                l10n.adminAuthEmailChangedRateLimited,
              _ => l10n.adminAuthEmailChangedNoRecovery,
            },
      AdminUserAuthAction.sendRecovery => l10n.adminAuthRecoveryDone,
      AdminUserAuthAction.setPassword => l10n.adminAuthPasswordDone,
    };
    final partial = result.action == AdminUserAuthAction.changeEmail &&
        !result.recoverySent;

    return Column(
      key: const Key('adminAuthResult'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              partial
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color:
                  partial ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(headline, key: const Key('adminAuthHeadline')),
            ),
          ],
        ),
        if (partial) ...[
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            key: const Key('adminAuthRetryRecovery'),
            onPressed: _retrying ? null : _retryRecovery,
            icon: _retrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            label: Text(l10n.adminAuthRetryRecovery),
          ),
          if (_retryFailure != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              _failureText(
                  l10n, _retryFailure!, AdminUserAuthAction.sendRecovery),
              key: const Key('adminAuthRetryError'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
        if (!result.auditRecorded) ...[
          const SizedBox(height: Gap.md),
          Text(
            l10n.adminAuthAuditMissing,
            key: const Key('adminAuthAuditMissing'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// What a failure reads as. By type, with a reason only where the sentence differs: nothing
/// here decides anything.
///
/// A dropped connection on a change reads as "not known whether it was done", because the
/// request may have reached the server; on a recovery email nothing is changed either way.
String _failureText(
  AppLocalizations l10n,
  Failure failure,
  AdminUserAuthAction action,
) =>
    switch (failure) {
      AuthorizationFailure() => l10n.adminAuthNotAllowed,
      AuthenticationFailure() => l10n.adminAuthNotAllowed,
      NotFoundFailure() => l10n.adminAuthAccountGone,
      ConflictFailure(reason: FailureReason.googleLinked) =>
        l10n.adminAuthGoogleLinked,
      ConflictFailure(reason: FailureReason.emailAlreadyUsed) =>
        l10n.adminAuthEmailTaken,
      ConflictFailure() => l10n.adminAuthNoEmail,
      ValidationFailure() => action == AdminUserAuthAction.setPassword
          ? l10n.adminAuthPasswordRejected
          : l10n.adminAuthEmailRejected,
      InfrastructureFailure(reason: FailureReason.tooManyRequests) =>
        l10n.adminAuthRateLimited,
      InfrastructureFailure(reason: FailureReason.authOutcomeUnknown) =>
        l10n.adminAuthOutcomeUnknown,
      NetworkFailure() => action == AdminUserAuthAction.sendRecovery
          ? l10n.adminAuthFailed
          : l10n.adminAuthOutcomeUnknown,
      _ => l10n.adminAuthFailed,
    };
