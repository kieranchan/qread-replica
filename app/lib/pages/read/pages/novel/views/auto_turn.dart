// pages/read/pages/novel/views/auto_turn.dart — the auto-turn bar (original `_AutoTurnState`: "翻页时间 " / "翻页距离 " / "停止"; prefs
// `turntime` = seconds per page, `turnsudu` = scroll distance per tick in scroll mode).
import 'package:flutter/material.dart';

import '../../../../../read/setting/read_setting.dart';

class AutoTurn extends StatefulWidget {
  final ReadSetting setting;
  final VoidCallback onStop;

  /// Called after a value changed (the reader restarts its timer).
  final VoidCallback onChanged;

  const AutoTurn({super.key, required this.setting, required this.onStop, required this.onChanged});

  @override
  State<AutoTurn> createState() => _AutoTurnState();
}

class _AutoTurnState extends State<AutoTurn> {
  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final scroll = s.turn == TurnMode.scroll;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(scroll ? '翻页距离 ${s.turnsudu}' : '翻页时间 ${s.turntime}秒'),
              Expanded(
                child: Slider(
                  value: (scroll ? s.turnsudu : s.turntime).toDouble(),
                  min: 1,
                  max: scroll ? 20 : 60,
                  divisions: scroll ? 19 : 59,
                  onChanged: (v) async {
                    if (scroll) {
                      await s.setTurnsudu(v.round());
                    } else {
                      await s.setTurntime(v.round());
                    }
                    setState(() {});
                  },
                  onChangeEnd: (_) => widget.onChanged(),
                ),
              ),
              FilledButton.tonal(onPressed: widget.onStop, child: const Text('停止')),
            ],
          ),
        ),
      ),
    );
  }
}
