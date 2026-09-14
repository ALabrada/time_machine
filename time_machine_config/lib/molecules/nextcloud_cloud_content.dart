import 'package:flutter/material.dart';
import 'package:time_machine_config/domain/cloud_event.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/l10n/config_localizations.dart';
import 'package:time_machine_res/time_machine_res.dart';

class NextCloudCloudContent extends StatefulWidget {
  const NextCloudCloudContent({
    super.key,
    required this.state,
    required this.onEvent,
  });

  final CloudState state;
  final Future<void> Function(CloudEvent event) onEvent;

  @override
  State<NextCloudCloudContent> createState() => _NextCloudCloudContentState();
}

class _NextCloudCloudContentState extends State<NextCloudCloudContent> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _loginNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _syncFromState();
  }

  @override
  void didUpdateWidget(covariant NextCloudCloudContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromState();
  }

  /// Fills the form with the server URL and login name carried by the state
  /// (e.g. after a failed sign-in attempt) without touching the password.
  void _syncFromState() {
    final nextcloud = widget.state is NextCloudState
        ? widget.state as NextCloudState
        : null;
    final serverUrl = nextcloud?.serverUrl;
    final loginName = nextcloud?.loginName;
    if (serverUrl != null && serverUrl != _serverUrlController.text) {
      _serverUrlController.text = serverUrl;
    }
    if (loginName != null && loginName != _loginNameController.text) {
      _loginNameController.text = loginName;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _loginNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    final nextcloud = widget.state is NextCloudState
        ? widget.state as NextCloudState
        : null;
    final authenticated = nextcloud?.signedIn == true;
    final active = nextcloud != null && nextcloud.isActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(
                  authenticated ? Icons.verified_user : Icons.person_outline,
                  color: authenticated
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                ),
                title: Text(localizations.cloudPageAuthSection),
                subtitle: authenticated && nextcloud!.loginName != null
                    ? Text(
                        nextcloud.serverUrl == null
                            ? nextcloud.loginName!
                            : '${nextcloud.loginName}\n${nextcloud.serverUrl}',
                      )
                    : null,
                trailing: Text(
                  authenticated
                      ? localizations.cloudPageAuthSignedIn
                      : localizations.cloudPageAuthSignedOut,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: authenticated
                    ? FilledButton.icon(
                        onPressed: active
                            ? () => _deactivate(context)
                            : () => _activate(context),
                        icon: Icon(
                          active
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_upload_outlined,
                        ),
                        label: Text(
                          active
                              ? localizations.cloudPageDeactivate
                              : localizations.cloudPageActivate,
                        ),
                      )
                    : _buildSignInForm(context, localizations),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignInForm(
    BuildContext context,
    ConfigLocalizations localizations,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _serverUrlController,
            decoration: InputDecoration(
              labelText: localizations.cloudPageServerUrl,
            ).applyDefaults(formFieldDecoration(context)),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              final uri = Uri.tryParse(trimmed);
              if (trimmed.isEmpty ||
                  uri == null ||
                  !uri.hasScheme ||
                  uri.host.isEmpty) {
                return localizations.cloudPageServerUrlInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _loginNameController,
            decoration: InputDecoration(
              labelText: localizations.cloudPageLoginName,
            ).applyDefaults(formFieldDecoration(context)),
            autocorrect: false,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? localizations.cloudPageFieldRequired
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: localizations.cloudPagePassword,
              helperText: localizations.cloudPagePasswordHint,
              helperMaxLines: 5,
            ).applyDefaults(formFieldDecoration(context)),
            obscureText: true,
            validator: (value) => (value == null || value.isEmpty)
                ? localizations.cloudPageFieldRequired
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : () => _signIn(context),
            icon: const Icon(Icons.login),
            label: Text(localizations.cloudPageSignIn),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    final localizations = ConfigLocalizations.of(context);
    setState(() => _submitting = true);
    try {
      await _run(
        context,
        () => widget.onEvent(NextCloudSignInEvent(
          serverUrl: _serverUrlController.text.trim(),
          loginName: _loginNameController.text.trim(),
          password: _passwordController.text,
        )),
        success: localizations.cloudPageActivationSuccess,
        failure: localizations.cloudPageActivationFailed,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _activate(BuildContext context) async {
    final localizations = ConfigLocalizations.of(context);
    await _run(
      context,
      () => widget.onEvent(const CloudActivateEvent()),
      success: localizations.cloudPageActivationSuccess,
      failure: localizations.cloudPageActivationFailed,
    );
  }

  Future<void> _deactivate(BuildContext context) async {
    final localizations = ConfigLocalizations.of(context);
    await _run(
      context,
      () => widget.onEvent(const CloudDeactivateEvent()),
      success: localizations.cloudPageDeactivationSuccess,
      failure: localizations.cloudPageDeactivationFailed,
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    required String success,
    required String failure,
  }) async {
    try {
      await action();
      if (!context.mounted) return;
      _showMessage(context, success);
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, failure, error: error);
    }
  }

  void _showMessage(BuildContext context, String message, {Object? error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error == null ? message : '$message\n$error'),
    ));
  }
}