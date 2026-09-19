import 'package:flutter/material.dart';
import 'package:time_machine_config/l10n/config_localizations.dart';

class CloudProviderSelection extends StatelessWidget {
  const CloudProviderSelection({
    super.key,
    required this.clouds,
    required this.onSelect,
  });

  final List<String> clouds;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final localizations = ConfigLocalizations.of(context);
    if (clouds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(localizations.cloudPageProviderUnavailable),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                localizations.cloudPageProviderSelect,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final name in clouds)
            ListTile(
              leading: _buildLogo(context, name),
              title: Text(name),
              onTap: () => onSelect(name),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context, String cloudName) {
    final asset = switch (cloudName) {
      'gdrive' => 'assets/images/gdrive_icon.png',
      'dropbox' => 'assets/images/dropbox_icon.png',
      'nextcloud' => 'assets/images/nextcloud_icon.png',
      'yandex' => 'assets/images/yandexdisk_icon.png',
      _ => '',
    };
    if (asset.isEmpty) {
      return Icon(
        Icons.cloud_outlined,
        color: Theme.of(context).colorScheme.outline,
      );
    }
    return Image.asset(
      asset,
      height: 24,
      fit: BoxFit.contain,
    );
  }
}