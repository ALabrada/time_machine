import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/controllers/cloud_controller.dart';
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
          if (!controller.cloudAvailable) {
            return _buildUnavailable(context);
          }
          if (controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = controller.error;
          if (error != null) {
            return _buildError(context, error);
          }
          return _buildContent(context);
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
    final cloud = controller.cloud;
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
      ],
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    return Card(
      child: Column(children: children),
    );
  }
}