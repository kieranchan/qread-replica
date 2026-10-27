// widget/ui/q_switch.dart — `QSwitch`: the adaptive switch used in setting rows (CupertinoSwitch on iOS in the original).
import 'package:flutter/material.dart';

class QSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const QSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => Switch.adaptive(value: value, onChanged: onChanged);
}
