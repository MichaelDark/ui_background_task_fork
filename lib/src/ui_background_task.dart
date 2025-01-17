import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

import 'ui_background_task_platform_interface.dart';

class UiBackgroundTask {
  ///Duration after which all the tasks will be ended when the app is in background.
  ///Keeping it a bit less than 30 seconds, i.e. the time app gets when in background.
  static const kAppBackgroundTimerDuration = Duration(seconds: 28);

  ///Duration for which each task is going to run at max.
  ///Keeping it a bit less than 30 seconds, i.e. the time before which the background tasks should end.
  ///The expiration handler of the task is only called when teh app is in background for more than 30 seconds
  static const kTaskCompletionTimerDuration = Duration(seconds: 29);

  static final UiBackgroundTask _instance = UiBackgroundTask._();

  static UiBackgroundTask get instance => _instance;

  UiBackgroundTask._();

  ///List to store the task Ids of the running background tasks.
  final List<int> _taskIds = [];

  final StopWatchTimer _stopWatchTimer = StopWatchTimer();

  StreamSubscription<int>? _subscription;

  Future<int> beginBackgroundTask() async {
    ///This is done to check if any task gets started after the [kAppBackgroundTimerDuration], then that would crash the app.
    ///Hence skipping creating a task after that. 1 second is subtracted to account for precision error.
    if ((_stopWatchTimer.secondTime.valueOrNull ?? 0) >
        kAppBackgroundTimerDuration.inSeconds - 1) {
      debugPrint('BG_TASK:: SKIPPED STARTING BG TASK');
      return 0;
    }

    final taskId = await _getTaskId();
    _taskIds.add(taskId);

    StopWatchTimer taskStopWatchTimer = StopWatchTimer();
    taskStopWatchTimer.onStartTimer();
    taskStopWatchTimer.secondTime.listen((event) async {
      if (event == kTaskCompletionTimerDuration.inSeconds ||
          !_taskIds.contains(taskId)) {
        taskStopWatchTimer.dispose();
      }
      if (event == kTaskCompletionTimerDuration.inSeconds) {
        debugPrint('BG_TASK:: $taskId cancelled at $event seconds');
        endBackgroundTask(taskId);
      }
    });

    return taskId;
  }

  Future<void> endBackgroundTask(int taskId) async {
    await UiBackgroundTaskPlatform.instance.endBackgroundTask(taskId);
    _taskIds.remove(taskId);
  }

  void appLifeCycleUpdate(AppLifecycleState appLifecycleState) {
    switch (appLifecycleState) {
      case AppLifecycleState.resumed:
        debugPrint('BG_TASK:: App background timer reset');
        _stopWatchTimer.onResetTimer();
        break;
      case AppLifecycleState.paused:
        if (_taskIds.isNotEmpty) {
          _stopWatchTimer.onResetTimer();
          _stopWatchTimer.onStartTimer();
          _subscription?.cancel();
          _subscription = _stopWatchTimer.secondTime.listen((event) {
            if (event == kAppBackgroundTimerDuration.inSeconds) {
              for (var taskId in [..._taskIds]) {
                endBackgroundTask(taskId);
                debugPrint('BG_TASK:: $taskId cancelled at $event seconds');
              }
            }
          });
        }
        break;
      case AppLifecycleState.detached:
        _stopWatchTimer.dispose();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        //do nothing
        break;
    }
  }

  Future<int> _getTaskId() async {
    final taskId =
        await UiBackgroundTaskPlatform.instance.beginBackgroundTask();
    if (taskId == null) {
      throw Exception('Cannot begin BackgroundTask');
    }
    return taskId;
  }

  void dispose() {
    _stopWatchTimer.dispose();
    _taskIds.clear();
  }
}
