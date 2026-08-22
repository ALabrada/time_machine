import 'package:flutter/material.dart';
import 'package:time_machine_config/domain/cloud_event.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/l10n/config_localizations.dart';

class DropBoxCloudContent extends StatelessWidget {
  const DropBoxCloudContent({
    super.key,
    required this.state,
    required this.onEvent,
  });

  final CloudState state;
  final Future<void> Function(CloudEvent event) onEvent;

  @override
  Widget build(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    final localState = state;
    final dropbox = localState is DropBoxState ? localState : null;
    final authenticated = dropbox?.accountEmail != null;
    final active = dropbox != null && dropbox.isActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(
                authenticated ? Icons.verified_user : Icons.person_outline,
                color: authenticated
                    ? Colors.green
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(localizations.cloudPageAuthSection),
              subtitle: dropbox?.accountEmail != null
                  ? Text(dropbox!.accountEmail!)
                  : null,
              trailing: Text(
                authenticated
                    ? localizations.cloudPageStatusActive
                    : localizations.cloudPageStatusInactive,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: active ? () => _deactivate(context) : () => _activate(context),
          icon: Icon(
            active ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
          ),
          label: Text(
            active
                ? localizations.cloudPageDeactivate
                : localizations.cloudPageActivate,
          ),
        ),
      ],
    );
  }

  Future<void> _activate(BuildContext context) async {
    final localizations = ConfigLocalizations.of(context);
    await _run(
      context,
      () => onEvent(const CloudActivateEvent()),
      success: localizations.cloudPageActivationSuccess,
      failure: localizations.cloudPageActivationFailed,
    );
  }

  Future<void> _deactivate(BuildContext context) async {
    final localizations = ConfigLocalizations.of(context);
    await _run(
      context,
      () => onEvent(const CloudDeactivateEvent()),
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
