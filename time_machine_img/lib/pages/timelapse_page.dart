import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/comparison_controller.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/timelapse_tool_bar.dart';
import 'package:time_machine_res/time_machine_res.dart';

class TimelapsePage extends StatefulWidget {
  const TimelapsePage({
    super.key,
    this.recordId,
  });

  final int? recordId;

  @override
  TimelapsePageState createState() => TimelapsePageState();
}

class TimelapsePageState extends State<TimelapsePage>
    with SingleTickerProviderStateMixin {
  static const defaultAspectRatio = 4.0 / 3.0;

  late ComparisonController comparisonController;
  late AnimationController animationController;

  @override
  void initState() {
    animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4),
    )..repeat(reverse: true);
    comparisonController = ComparisonController(
      cacheService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
      telegramService: context.read(),
    );
    super.initState();
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: FutureBuilder(
        future: comparisonController.loadRecord(widget.recordId),
        builder: (context, snapshot) => _buildContent(snapshot.data),
      ),
      bottomNavigationBar: TimelapseToolBar(
        animationController: animationController,
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(ImgLocalizations.of(context).timelapsePage),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent(Record? record) {
    return FutureBuilder(
      future: comparisonController.createTimelapse(record),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.hasError) {
          return Center(
            child: Column(
              children: [
                Text(snapshot.error.toString(), style: h3Style(context),),
                SizedBox(height: 8,),
                Text(snapshot.stackTrace.toString(), style: bodyStyle(context),)
              ],
            ),
          );
        }
        if (data == null) {
          return LoadingView();
        }
        return Image.memory(data);
      },
    );
  }
}