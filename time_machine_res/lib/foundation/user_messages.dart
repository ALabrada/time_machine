import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/res_localizations.dart';

/// A semantic, non-localized notification produced by controllers and domain
/// services, and rendered by [UserMessageListener].
enum UserMessageKind { savedToFile }

class UserMessage {
  const UserMessage.savedToFile(this.path)
      : kind = UserMessageKind.savedToFile;

  final UserMessageKind kind;

  /// Destination path, for [UserMessageKind.savedToFile].
  final String? path;
}

/// Broadcasts [UserMessage]s from controllers to the presentation layer without
/// the controllers needing a `BuildContext` or any other view reference.
class UserMessageService {
  final _controller = StreamController<UserMessage>.broadcast();

  Stream<UserMessage> get messages => _controller.stream;

  void savedToFile(String path) =>
      _controller.add(UserMessage.savedToFile(path));

  void dispose() => _controller.close();
}

/// Listens to the [UserMessageService] and renders each message as a `SnackBar`.
///
/// Must sit below both the root `ScaffoldMessenger` and the app's
/// `Localizations`; the `MaterialApp.builder` slot satisfies both.
class UserMessageListener extends StatefulWidget {
  const UserMessageListener({super.key, required this.child});

  final Widget child;

  @override
  State<UserMessageListener> createState() => _UserMessageListenerState();
}

class _UserMessageListenerState extends State<UserMessageListener> {
  StreamSubscription<UserMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<UserMessageService>().messages.listen(_show);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _show(UserMessage message) {
    if (!mounted) {
      return;
    }
    final localizations = ResLocalizations.of(context);
    final text = switch (message.kind) {
      UserMessageKind.savedToFile =>
        localizations.savedToFile(message.path ?? ''),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
