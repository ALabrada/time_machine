import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/controllers/cloud_controller.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/molecules/cloud_provider_selection.dart';
import 'package:time_machine_config/molecules/dropbox_cloud_content.dart';
import 'package:time_machine_config/molecules/google_drive_cloud_content.dart';
import 'package:time_machine_config/molecules/nextcloud_cloud_content.dart';
import 'package:time_machine_config/molecules/supabase_cloud_content.dart';
import 'package:time_machine_net/time_machine_net.dart';

import '../l10n/config_localizations.dart';

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  CloudPageState createState() => CloudPageState();
}

class CloudPageState extends State<CloudPage> {
  late final CloudController controller;

  @override
  void initState() {
    super.initState();
    controller = CloudController(
      configurationService: context.read(),
      networkService: context.read(),
      cloudSyncService: context.read(),
      googleDriveSignIn: context.read<GoogleDriveSignIn?>(),
    );
  }

  @override
  void dispose() {
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
          final loading = controller.loading;
          final error = controller.error;
          final Widget child;
          if (loading) {
            child = _buildLoading(context);
          } else if (error != null) {
            child = _buildError(context, error);
          } else if (controller.value is NotSelectedState) {
            child = _buildSelectionContent(context);
          } else {
            child = _buildProviderContent(context);
          }
          final key = loading
              ? 'loading'
              : error != null
                  ? 'error'
                  : controller.value is NotSelectedState
                      ? 'selection'
                      : 'provider';
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<String>(key),
              child: SizedBox.expand(child: child),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    final message = switch (
      controller.loadingPhase ?? CloudLoadingPhase.connecting
    ) {
      CloudLoadingPhase.authenticating =>
        localizations.cloudPageLoadingAuthenticating,
      CloudLoadingPhase.synchronizing =>
        localizations.cloudPageLoadingSynchronizing,
      CloudLoadingPhase.deactivating =>
        localizations.cloudPageLoadingDeactivating,
      CloudLoadingPhase.connecting => localizations.cloudPageLoadingConnecting,
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ),
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

  Widget _buildSelectionContent(BuildContext context) {
    final state = controller.value;
    final clouds = state is NotSelectedState
        ? state.clouds
        : const <String>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CloudProviderSelection(
          clouds: clouds,
          onSelect: controller.selectCloud,
        ),
      ],
    );
  }

  Widget _buildProviderContent(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    final cloud = controller.cloud;
    if (cloud == null) {
      return _buildSelectionContent(context);
    }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              onPressed: () => controller.showSelection(),
              icon: const Icon(Icons.swap_horiz),
              label: Text(localizations.cloudPageChangeProvider),
            ),
          ),
        ]),
        ..._buildCloudContent(context, cloud),
      ],
    );
  }

  List<Widget> _buildCloudContent(BuildContext context, CloudBase cloud) {
    return [
      if (cloud is SupabaseCloud)
        SupabaseCloudContent(
          state: controller.value,
          onEvent: controller.handleEvent,
        )
      else if (cloud is GoogleDriveCloud)
        GoogleDriveCloudContent(
          state: controller.value,
          onEvent: controller.handleEvent,
        )
      else if (cloud is DropBoxCloud)
        DropBoxCloudContent(
          state: controller.value,
          onEvent: controller.handleEvent,
        )
      else if (cloud is NextCloudCloud)
        NextCloudCloudContent(
          state: controller.value,
          onEvent: controller.handleEvent,
        ),
    ];
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}