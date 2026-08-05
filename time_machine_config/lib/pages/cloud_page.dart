import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/controllers/cloud_controller.dart';

import '../l10n/config_localizations.dart';

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  CloudPageState createState() => CloudPageState();
}

class CloudPageState extends State<CloudPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final CloudController controller;

  @override
  void initState() {
    super.initState();
    controller = CloudController(
      configurationService: context.read(),
      networkService: context.read(),
      cloudSyncService: context.read(),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ConfigLocalizations.of(context).cloudPageTitle),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Theme.of(context).colorScheme.onSecondary,
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return !controller.cloudAvailable
              ? _buildUnavailable(context)
              : controller.loading
              ? const Center(child: CircularProgressIndicator())
              : controller.error != null
              ? _buildError(context, controller.error!)
              : _buildContent(context);
        },
      ),
    );
  }

  Widget _buildUnavailable(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.cloud_off,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          controller.cloudName == null
              ? localizations.cloudPageProviderNotSelected
              : localizations.cloudPageProviderUnavailable,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final localizations = ConfigLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.cloud_off,
          size: 64,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          '${localizations.cloudPageProviderUnavailable}\n$error',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(context, [
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(localizations.cloudPageProvider),
            trailing: Text(controller.cloudName!),
          ),
          ListTile(
            leading: Icon(
              controller.isActive ? Icons.check_circle : Icons.cancel,
              color: controller.isActive
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
            title: Text(localizations.cloudPageStatus),
            trailing: Text(
              controller.isActive
                  ? localizations.cloudPageStatusActive
                  : localizations.cloudPageStatusInactive,
            ),
          ),
        ]),
        if (controller.supportsAuthentication)
          _buildAuthSection(context),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: controller.loading
              ? null
              : () => _activate(context),
          icon: controller.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(localizations.cloudPageActivate),
        ),
      ],
    );
  }

  Widget _buildAuthSection(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    final authenticated = controller.isAuthenticated;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _buildSection(context, [
          ListTile(
            leading: Icon(
              authenticated ? Icons.verified_user : Icons.person_outline,
              color: authenticated
                  ? Colors.green
                  : Theme.of(context).colorScheme.outline,
            ),
            title: Text(localizations.cloudPageAuthSection),
            trailing: authenticated
                ? Text(localizations.cloudPageStatusActive)
                : Text(localizations.cloudPageStatusInactive),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.cloudPageEmail,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          onSubmitted: (_) => _signIn(),
          decoration: InputDecoration(
            labelText: localizations.cloudPagePassword,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: controller.loading ? null : _signIn,
          child: Text(localizations.cloudPageSignIn),
        ),
        TextButton(
          onPressed: controller.loading
              ? null
              : () => _runAuth(controller.signOut),
          child: Text(localizations.cloudPageSignOut),
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    return Card(
      child: Column(children: children),
    );
  }

  Future<void> _signIn() {
    return _runAuth(
      () => controller.signIn(_emailController.text, _passwordController.text),
    );
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    final localizations = ConfigLocalizations.of(context);
    try {
      await action();
      if (!mounted) return;
      _showMessage(localizations.cloudPageAuthSuccess);
    } catch (error) {
      if (!mounted) return;
      _showMessage(localizations.cloudPageAuthFailed, error: error);
    }
  }

  Future<void> _activate(BuildContext context) async {
    final localizations = ConfigLocalizations.of(context);
    try {
      final activated = await controller.activate();
      if (!mounted) return;
      _showMessage(
        activated
            ? localizations.cloudPageActivationSuccess
            : localizations.cloudPageActivationFailed,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(localizations.cloudPageActivationFailed, error: error);
    }
  }

  void _showMessage(String message, {Object? error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error == null ? message : '$message\n$error'),
    ));
  }
}
