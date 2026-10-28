// SVG bubbles: the built-in `desvgs` (0x2276cc), the member-aware list (0x2273b0), the flutter_svg previews (0x1093800 / 0x1028d98)
// and the editor's save path for members.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/data/svg.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/pages/setting/choose_svg.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

Future<void> signIn({required bool vip}) => UserSession.apply(Userinfo(
    username: 'alice', vip: vip ? '2030-01-01' : '', tockenid: 't', email: 'a@x.io', nickname: 'a', avatarUrl: '', isvip: vip));

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
  });
  tearDown(() => dev.delete());

  test('desvgs: four built-in bubbles with both placeholders, used when nothing is stored', () async {
    expect(Svg.desvgs.map((s) => s.id), ['0', '1', '2', '3']);
    for (final s in Svg.desvgs) {
      expect(s.svg, startsWith('<svg width='));
      expect(s.svg, endsWith('</svg>'));
      expect(s.svg, contains(r'stroke="$color"'));
      expect(s.svg, contains(r'>$displayText</text>'));
    }
    expect(Svg.desvgs[0].svg, contains('<path d="M4,2 L13,2 Q15,2 15,4 L15,9 Q15,11 13,11 L4,11 Q2,11 2,9 L2,7.5 L0.5,6 L2,4.5 L2,4 Q2,2 4,2 Z" '));
    expect(Svg.desvgs[1].svg, contains('<circle cx="50" cy="50" r="40" fill="none" stroke="\$color" stroke-width="1"/>'));
    await Svg.load();
    expect(Svg.svgs.map((s) => s.id), ['0', '1', '2', '3']);
    // the defaults are copies: editing the store does not touch desvgs
    await Svg.put('0', '<svg/>');
    expect(Svg.desvgs[0].svg, isNot('<svg/>'));
  });

  test('available: stored bubbles for members, the defaults for everyone else', () async {
    await Svg.put('mine', '<svg width="10" height="10"></svg>');
    expect(Svg.available.map((s) => s.id), ['0', '1', '2', '3']);
    expect(Svg.selected('mine')?.id, '0');
    await signIn(vip: true);
    expect(Svg.available.map((s) => s.id), ['mine']);
    expect(Svg.selected('mine')?.id, 'mine');
  });

  testWidgets('preview fills the placeholders and renders with flutter_svg; current() is 20x20', (t) async {
    final filled = ChooseSvgPage.render(Svg.desvgs[1].svg, color: '#FF0000', text: '1');
    expect(filled, contains('stroke="#FF0000"'));
    expect(filled, contains('>1</text>'));
    await Storage.setString(ChooseSvgPage.selectedKey, '3');
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => Column(children: [ChooseSvgPage.preview(c, Svg.desvgs[0].svg), ChooseSvgPage.current(c)])),
    ));
    await t.pump();
    final pics = t.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
    expect(pics.length, 2);
    expect(pics[0].width, 120);
    expect(pics[1].width, 20);
    expect(t.takeException(), isNull);
  });

  testWidgets('members add a bubble through the editor (time id, live preview)', (t) async {
    await signIn(vip: true);
    await t.pumpWidget(GetMaterialApp(home: const ChooseSvgPage()));
    await t.pump();
    expect(find.byKey(const Key('svg_item_0')), findsOneWidget);
    await t.tap(find.byKey(const Key('svg_add')));
    await t.pumpAndSettle();
    expect(find.text('输入SVG代码后显示预览'), findsOneWidget);
    await t.tap(find.byKey(const Key('svg_save')));
    await t.pump();
    expect(Toast.log, contains('ID和SVG代码不能为空'));
    await t.enterText(find.byKey(const Key('svg_code')), r'<svg width="20" height="20"><text fill="$color">$displayText</text></svg>');
    await t.pump();
    expect(find.text('输入SVG代码后显示预览'), findsNothing);
    await t.tap(find.byKey(const Key('svg_save')));
    await t.pumpAndSettle();
    expect(Svg.svgs.length, 5);
    expect(int.tryParse(Svg.svgs.last.id), isNotNull);
  });
}
