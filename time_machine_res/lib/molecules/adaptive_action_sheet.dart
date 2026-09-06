import 'package:adaptive_action_sheet/adaptive_action_sheet.dart'
    hide showAdaptiveActionSheet;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:popover/popover.dart';

import '../foundation/responsive.dart';

export 'package:adaptive_action_sheet/adaptive_action_sheet.dart'
    show CancelAction, BottomSheetAction;

/// Whether the current screen should present action sheets as popup menus
/// anchored to their source, mirroring native iPad action sheets (which render
/// as popovers anchored to the presenting control when the interface is
/// horizontally regular). On phones the sheet stays a bottom sheet.
bool _usesTabletPopup(BuildContext context) => isTabletLayout(context);

/// Reads the source context inherited from an enclosing action sheet popover.
///
/// When an action sheet is opened from inside another action sheet and no
/// explicit [showAdaptiveActionSheet.source] is supplied, the new sheet
/// inherits the source of the first one so the popover stays anchored to the
/// original source button (native iPad behavior).
BuildContext? inheritedActionSheetSource(BuildContext context) {
  return _ActionSheetSource.maybeSourceOf(context);
}

/// Which side a tablet popover should open toward. Defaults to [auto], which
/// picks the side with the most room (like a native iPad popover). Used by
/// toolbar buttons to force the popup to open upward, above the control.
enum ActionSheetDirection { auto, up, down, left, right }

PopoverDirection _mapDirection(ActionSheetDirection? direction, BuildContext page,
    BuildContext source) {
  final resolved = direction ?? ActionSheetDirection.auto;
  switch (resolved) {
    case ActionSheetDirection.up:
      return PopoverDirection.top;
    case ActionSheetDirection.down:
      return PopoverDirection.bottom;
    case ActionSheetDirection.left:
      return PopoverDirection.right;
    case ActionSheetDirection.right:
      return PopoverDirection.left;
    case ActionSheetDirection.auto:
      return _autoDirection(page, source);
  }
}

/// Renders an adaptive action sheet.
///
/// On tablet-sized screens it is displayed as a popover anchored to [source]
/// (the context of the button that opened it), with an arrow pointing back at
/// it — like a native iPad action sheet. On phones, or when no [source] is
/// available, it falls back to the classic bottom sheet.
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  Widget? title,
  required List<BottomSheetAction> actions,
  CancelAction? cancelAction,
  Color? barrierColor,
  Color? bottomSheetColor,
  double? androidBorderRadius,
  bool isDismissible = true,
  bool? useRootNavigator,
  BuildContext? source,
  ActionSheetDirection direction = ActionSheetDirection.auto,
}) async {
  final effectiveSource = source ?? inheritedActionSheetSource(context);
  if (_usesTabletPopup(context)) {
    return _showTabletPopover<T>(
      context: context,
      source: effectiveSource,
      title: title,
      actions: actions,
      isDismissible: isDismissible,
      direction: direction,
    );
  }
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showCupertinoModalPopup<T>(
      context: context,
      barrierDismissible: isDismissible,
      useRootNavigator: useRootNavigator ?? true,
      builder: (coxt) => _buildCupertino(
        context,
        coxt,
        title,
        actions,
        cancelAction,
      ),
    );
  }
  return _showMaterialSheet<T>(
    context,
    title,
    actions,
    cancelAction,
    barrierColor,
    bottomSheetColor,
    androidBorderRadius,
    isDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
  );
}

/// Shows the action-sheet menu as a [popover] popup with an arrow pointing at
/// the source button. Falls back to a bottom sheet when there is no source
/// (e.g. sheets opened from a long press or file chooser).
Future<T?> _showTabletPopover<T>({
  required BuildContext context,
  required BuildContext? source,
  required Widget? title,
  required List<BottomSheetAction> actions,
  required bool isDismissible,
  ActionSheetDirection direction = ActionSheetDirection.auto,
}) {
  if (source == null) {
    return _showMaterialSheet<T>(
      context,
      title,
      actions,
      null,
      null,
      null,
      null,
      isDismissible: isDismissible,
    );
  }
  final resolved = _mapDirection(direction, context, source);
  return showPopover<T>(
    context: source,
    direction: resolved,
    backgroundColor: Theme.of(context).colorScheme.surface,
    radius: 12,
    arrowWidth: 24,
    arrowHeight: 12,
    barrierColor: Colors.black45,
    barrierDismissible: isDismissible,
    constraints: BoxConstraints(
      minWidth: 220,
      maxWidth: 360,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    bodyBuilder: (popupContext) {
      return _ActionSheetSource(
        source: source,
        child: _ActionSheetMenu(
          title: title,
          actions: actions,
        ),
      );
    },
  );
}

/// Chooses which side of the source the popover should appear on, so the
/// arrow points back at the button.
PopoverDirection _autoDirection(BuildContext page, BuildContext source) {
  final renderObject = source.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return PopoverDirection.bottom;
  }
  final global = renderObject.localToGlobal(Offset.zero) & renderObject.size;
  final screen = MediaQuery.sizeOf(page);
  final center = global.center;
  final toTop = center.dy;
  final toBottom = screen.height - center.dy;
  final toLeft = center.dx;
  final toRight = screen.width - center.dx;
  if (toBottom >= toTop && toBottom >= toLeft && toBottom >= toRight) {
    return PopoverDirection.top; // place above, arrow points down
  }
  if (toTop >= toLeft && toTop >= toRight) {
    return PopoverDirection.bottom; // place below, arrow points up
  }
  if (toRight >= toLeft) {
    return PopoverDirection.left; // place to the right, arrow points left
  }
  return PopoverDirection.right; // place to the left, arrow points right
}

/// The visual popover content: title + action items. It omits the cancel
/// button (dismissal is via tapping the barrier), matching native iPad action
/// sheet popovers. Items pop the enclosing popover route with their result.
class _ActionSheetMenu extends StatelessWidget {
  const _ActionSheetMenu({
    required this.title,
    required this.actions,
  });

  final Widget? title;
  final List<BottomSheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultTextStyle =
        theme.textTheme.titleLarge ?? const TextStyle(fontSize: 20);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: title!,
            ),
          ...actions.map((action) {
            return InkWell(
              onTap: () => action.onPressed(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (action.leading != null) ...[
                      action.leading!,
                      const SizedBox(width: 12),
                    ],
                    Flexible(
                      child: DefaultTextStyle(
                        style: defaultTextStyle,
                        textAlign: action.leading != null
                            ? TextAlign.start
                            : TextAlign.center,
                        child: action.title,
                      ),
                    ),
                    if (action.trailing != null) ...[
                      const SizedBox(width: 8),
                      action.trailing!,
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Carries the source of the enclosing popover so a sheet opened from within
/// another sheet can inherit it.
class _ActionSheetSource extends InheritedWidget {
  const _ActionSheetSource({required this.source, required super.child});

  final BuildContext? source;

  static BuildContext? maybeSourceOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ActionSheetSource>()
        ?.source;
  }

  @override
  bool updateShouldNotify(_ActionSheetSource oldWidget) =>
      oldWidget.source != source;
}

/// The Cupertino action sheet used on iOS phones, mirroring the native
/// `adaptive_action_sheet` package behavior.
Widget _buildCupertino(
  BuildContext context,
  BuildContext coxt,
  Widget? title,
  List<BottomSheetAction> actions,
  CancelAction? cancelAction,
) {
  final defaultTextStyle =
      Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 20);
  return CupertinoActionSheet(
    title: title,
    actions: actions.map<Widget>((action) {
      return Material(
        color: Colors.transparent,
        child: CupertinoActionSheetAction(
          onPressed: () => action.onPressed(coxt),
          child: Row(
            children: [
              if (action.leading != null) ...[
                action.leading!,
                const SizedBox(width: 15),
              ],
              Expanded(
                child: DefaultTextStyle(
                  style: defaultTextStyle,
                  textAlign: action.leading != null
                      ? TextAlign.start
                      : TextAlign.center,
                  child: action.title,
                ),
              ),
              if (action.trailing != null) ...[
                const SizedBox(width: 10),
                action.trailing!,
              ],
            ],
          ),
        ),
      );
    }).toList(),
    cancelButton: cancelAction != null
        ? CupertinoActionSheetAction(
            onPressed: () {
              if (cancelAction.onPressed != null) {
                cancelAction.onPressed!(coxt);
              } else {
                Navigator.of(coxt).pop();
              }
            },
            child: DefaultTextStyle(
              style: defaultTextStyle.copyWith(color: Colors.lightBlue),
              textAlign: TextAlign.center,
              child: cancelAction.title,
            ),
          )
        : null,
  );
}

/// The material bottom sheet implementation, kept from the
/// `adaptive_action_sheet` package (used on non-iOS phones and desktop).
Future<T?> _showMaterialSheet<T>(
  BuildContext context,
  Widget? title,
  List<BottomSheetAction> actions,
  CancelAction? cancelAction,
  Color? barrierColor,
  Color? bottomSheetColor,
  double? androidBorderRadius, {
  bool isDismissible = true,
  bool? useRootNavigator,
}) {
  return showModalBottomSheet<T>(
    context: context,
    elevation: 0,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    isScrollControlled: true,
    backgroundColor: bottomSheetColor,
    barrierColor: barrierColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(androidBorderRadius ?? 30),
        topRight: Radius.circular(androidBorderRadius ?? 30),
      ),
    ),
    useRootNavigator: useRootNavigator ?? false,
    builder: (coxt) {
      final defaultTextStyle =
          Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 20);
      final screenHeight = MediaQuery.of(context).size.height;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenHeight - (screenHeight / 10),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(child: title),
                  ),
                ...actions.map<Widget>((action) {
                  return InkWell(
                    onTap: () => action.onPressed(coxt),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          if (action.leading != null) ...[
                            action.leading!,
                            const SizedBox(width: 15),
                          ],
                          Expanded(
                            child: DefaultTextStyle(
                              style: defaultTextStyle,
                              textAlign: action.leading != null
                                  ? TextAlign.start
                                  : TextAlign.center,
                              child: action.title,
                            ),
                          ),
                          if (action.trailing != null) ...[
                            const SizedBox(width: 10),
                            action.trailing!,
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
                if (cancelAction != null)
                  InkWell(
                    onTap: () {
                      if (cancelAction.onPressed != null) {
                        cancelAction.onPressed!(coxt);
                      } else {
                        Navigator.of(coxt).pop();
                      }
                    },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: DefaultTextStyle(
                          style: defaultTextStyle.copyWith(
                            color: Colors.lightBlue,
                          ),
                          textAlign: TextAlign.center,
                          child: cancelAction.title,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A tablet-aware slider sheet shown as a popover anchored to [source].
///
/// On tablet-sized screens it is shown as a popover with an arrow pointing at
/// [source] — inheriting the source of the enclosing action sheet when opened
/// from one. On phones it is a classic modal bottom sheet.
Future<void> showAdaptiveSliderSheet({
  required BuildContext context,
  required String title,
  required double initial,
  required double min,
  required double max,
  required int divisions,
  required String Function(double) label,
  required ValueChanged<double> onChanged,
  BuildContext? source,
  ActionSheetDirection direction = ActionSheetDirection.auto,
}) async {
  final effectiveSource = source ?? inheritedActionSheetSource(context);
  if (_usesTabletPopup(context) && effectiveSource != null) {
    final resolved = _mapDirection(direction, context, effectiveSource);
    await showPopover<void>(
      context: effectiveSource,
      direction: resolved,
      backgroundColor: Theme.of(context).colorScheme.surface,
      radius: 12,
      arrowWidth: 24,
      arrowHeight: 12,
      barrierColor: Colors.black45,
      barrierDismissible: true,
      constraints: BoxConstraints(
        minWidth: 280,
        maxWidth: 360,
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      bodyBuilder: (popupContext) {
        return _ActionSheetSource(
          source: effectiveSource,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(popupContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _SliderValueEditor(
                  initial: initial,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: label,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }
  await _showSliderBottomSheet(
    context: context,
    title: title,
    initial: initial,
    min: min,
    max: max,
    divisions: divisions,
    label: label,
    onChanged: onChanged,
  );
}

class _SliderValueEditor extends StatefulWidget {
  const _SliderValueEditor({
    required this.initial,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double initial;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;

  @override
  _SliderValueEditorState createState() => _SliderValueEditorState();
}

class _SliderValueEditorState extends State<_SliderValueEditor> {
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _current,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      label: widget.label(_current),
      onChanged: (value) {
        setState(() => _current = value);
      },
      onChangeEnd: widget.onChanged,
    );
  }
}

Future<void> _showSliderBottomSheet({
  required BuildContext context,
  required String title,
  required double initial,
  required double min,
  required double max,
  required int divisions,
  required String Function(double) label,
  required ValueChanged<double> onChanged,
}) {
  var current = initial;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 16),
                Slider(
                  value: current,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: label(current),
                  onChanged: (value) {
                    setState(() => current = value);
                  },
                  onChangeEnd: onChanged,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
