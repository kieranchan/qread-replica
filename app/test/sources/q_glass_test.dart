// QGlassContainer follows the 沉浸光感 level (ImmersiveLight.level): 0 plain, 1 blurred; GlassCard / GlassFAB are glass surfaces.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/immersive_light.dart';
import 'package:newread/widget/ui/glass_card.dart';
import 'package:newread/widget/ui/q_glass.dart';

void main() {
  tearDown(() => ImmersiveLight.level.value = ImmersiveLight.off);

  testWidgets('level 0 is a plain surface, level 1 adds the 3x3 backdrop blur, glass:false stays plain', (t) async {
    ImmersiveLight.level.value = ImmersiveLight.off;
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          QGlassContainer(key: Key('g1'), child: Text('甲')),
          QGlassContainer(key: Key('g2'), glass: false, child: Text('乙')),
          GlassCard(child: Text('丙')),
        ]),
      ),
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('甲'), findsOneWidget);

    ImmersiveLight.level.value = ImmersiveLight.balanced;
    await t.pump();
    expect(find.descendant(of: find.byKey(const Key('g1')), matching: find.byType(BackdropFilter)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('g2')), matching: find.byType(BackdropFilter)), findsNothing);
    expect(find.byType(BackdropFilter), findsNWidgets(2)); // g1 + the card
  });

  testWidgets('GlassFAB taps through the glass', (t) async {
    var n = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: GlassFAB(icon: Icons.add, onPressed: () => n++)))));
    await t.tap(find.byIcon(Icons.add));
    expect(n, 1);
  });
}
