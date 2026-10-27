// TXT import: charset detection (UTF-8/UTF-16/GBK), chapter splitting by TOC rules, volume titles, fixed-size fallback.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/txt_toc_rule.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/txt/text_encoding.dart';
import 'package:newread/read/txt/text_file.dart';

const _chapterRule = r'^[ 　\t]{0,4}(?:序章|楔子|终章|后记|尾声|番外|第?[零〇一二两三四五六七八九十百千万0-9]{1,8}[章节回卷集部篇]).{0,30}$';

List<TxtTocRule> get _rules => [TxtTocRule(name: '章节', rule: _chapterRule, isEnabled: true)];

String _novel({int chapters = 12, bool withVolume = false}) {
  final sb = StringBuffer('书名：测试小说\r\n作者：某某\r\n\r\n这是前言的一段话。\r\n\r\n');
  for (var i = 1; i <= chapters; i++) {
    if (withVolume && (i == 1 || i == 7)) sb.write('第${i == 1 ? '一' : '二'}卷 风起云涌\r\n');
    sb.write('第$i章 标题$i\r\n');
    for (var k = 0; k < 3; k++) {
      sb.write('　　这是第$i章的第$k段正文，包含一些汉字和标点，“引号”也要正确。\r\n');
    }
    sb.write('\r\n');
  }
  return sb.toString();
}

Uint8List _utf16(String s, {required bool le, bool bom = true}) {
  final out = BytesBuilder();
  if (bom) out.add(le ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final u in s.codeUnits) {
    out.add(le ? [u & 0xff, u >> 8] : [u >> 8, u & 0xff]);
  }
  return out.toBytes();
}

void main() {
  late Directory tmp;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_txt_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('encoding detection', () {
    test('UTF-8 with and without BOM, ASCII', () {
      final raw = Uint8List.fromList(utf8.encode('你好，世界。第一章'));
      expect(TextEncodings.detect(raw).encoding, TextEncoding.utf8);
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...raw]);
      final info = TextEncodings.detect(bom);
      expect(info.encoding, TextEncoding.utf8);
      expect(info.bomLength, 3);
      expect(TextEncodings.detect(Uint8List.fromList('hello world'.codeUnits)).encoding, TextEncoding.utf8);
    });

    test('GBK', () {
      final raw = Uint8List.fromList(gbk.encode('这是一段用GBK编码的中文文本，需要被正确识别。' * 5));
      final info = TextEncodings.detect(raw);
      expect(info.encoding, TextEncoding.gbk);
      expect(TextEncodings.decode(raw, info.encoding), startsWith('这是一段用GBK编码'));
    });

    test('UTF-16 with BOM (LE/BE) and without BOM', () {
      const s = '第一章 测试 UTF-16 编码，内容足够长以便检测。\n';
      expect(TextEncodings.detect(_utf16(s, le: true)).encoding, TextEncoding.utf16le);
      expect(TextEncodings.detect(_utf16(s, le: false)).encoding, TextEncoding.utf16be);
      // Latin text without BOM: NUL pattern decides
      const latin = 'This is a long enough ascii sentence for detection purposes only.\n';
      expect(TextEncodings.detect(_utf16(latin * 3, le: true, bom: false)).encoding, TextEncoding.utf16le);
      expect(TextEncodings.detect(_utf16(latin * 3, le: false, bom: false)).encoding, TextEncoding.utf16be);
      expect(TextEncodings.decode(_utf16(s, le: true), TextEncoding.utf16le, 2), s);
    });

    test('charset hint overrides detection', () {
      final raw = Uint8List.fromList(utf8.encode('你好'));
      expect(TextEncodings.detect(raw, hint: 'GB18030').encoding, TextEncoding.gbk);
      expect(TextEncodings.detect(raw, hint: 'auto').encoding, TextEncoding.utf8);
    });
  });

  group('chapter splitting', () {
    Future<void> checkNovel(Uint8List bytes, String charsetName) async {
      final f = File('${tmp.path}/测试小说 作者：某某.txt')..writeAsBytesSync(bytes);
      final res = await TextFile.parse(f, rules: _rules);
      expect(res.charset, charsetName);
      expect(res.name, '测试小说');
      expect(res.author, '某某');
      expect(res.ruleName, '章节');
      // prologue + 12 chapters
      expect(res.chapters.length, 13);
      expect(res.chapters.first.name, '前言');
      expect(res.chapters[1].name, '第1章 标题1');
      expect(res.chapters.last.name, '第12章 标题12');
      for (var i = 0; i < res.chapters.length; i++) {
        expect(res.chapters[i].index, i);
        if (i > 0) expect(res.chapters[i].start, res.chapters[i - 1].end, reason: 'chapters are contiguous');
      }
      expect(res.chapters.last.end, bytes.length);

      final c1 = await TextFile.readChapter(f, res.chapters[1], res.charset);
      expect(c1, isNot(contains('第1章 标题1'))); // title line is dropped
      expect(c1, contains('这是第1章的第0段正文'));
      expect(c1, isNot(contains('第2章')));
      expect(c1, isNot(contains('\r')));
      final c12 = await TextFile.readChapter(f, res.chapters.last, res.charset);
      expect(c12, contains('第12章的第2段'));
      final pro = await TextFile.readChapter(f, res.chapters.first, res.charset);
      expect(pro, contains('这是前言的一段话'));
      expect(pro, contains('书名：测试小说'));
    }

    test('UTF-8', () async => checkNovel(Uint8List.fromList(utf8.encode(_novel())), 'UTF-8'));

    test('UTF-8 with BOM', () async {
      final raw = [0xEF, 0xBB, 0xBF, ...utf8.encode(_novel())];
      await checkNovel(Uint8List.fromList(raw), 'UTF-8');
    });

    test('GBK', () async => checkNovel(Uint8List.fromList(gbk.encode(_novel())), 'GBK'));

    test('UTF-16LE', () async => checkNovel(_utf16(_novel(), le: true), 'UTF-16LE'));

    test('UTF-16BE', () async => checkNovel(_utf16(_novel(), le: false), 'UTF-16BE'));

    test('volume titles are flagged', () async {
      final f = File('${tmp.path}/v.txt')..writeAsStringSync(_novel(withVolume: true));
      final res = await TextFile.parse(f, rules: _rules);
      final volumes = res.chapters.where((c) => c.isVolume).map((c) => c.name).toList();
      expect(volumes, ['第一卷 风起云涌', '第二卷 风起云涌']);
      expect(res.chapters.where((c) => !c.isVolume && c.name.contains('章')).length, 12);
      expect(TextFile.isVolumeTitle('第3章 卷土重来'), isFalse);
      expect(TextFile.isVolumeTitle('卷五 终局'), isTrue);
      expect(TextFile.isVolumeTitle('第二部'), isTrue);
    });

    test('a rule that matches fewer than two lines is skipped, the next rule is used', () async {
      final text = _novel(chapters: 5);
      final f = File('${tmp.path}/r.txt')..writeAsStringSync(text);
      final rules = [
        TxtTocRule(name: '只有序章', rule: r'^序章.*$', isEnabled: true),
        TxtTocRule(name: '坏规则', rule: r'(unclosed', isEnabled: true),
        ...(_rules),
      ];
      final res = await TextFile.parse(f, rules: rules);
      expect(res.ruleName, '章节');
      expect(res.chapters.length, 6);
    });

    test('default rules are used when the caller passes none', () async {
      final f = File('${tmp.path}/d.txt')..writeAsStringSync(_novel(chapters: 4));
      final res = await TextFile.parse(f);
      expect(res.chapters.length, 5);
    });

    test('fixed-size fallback covers the whole file without losing or duplicating a byte', () async {
      final para = List.generate(60, (i) => '这是没有任何章节标题的长文本第$i行，用来测试固定长度分章。').join('\n');
      final text = List.filled(40, para).join('\n');
      final bytes = Uint8List.fromList(utf8.encode(text));
      final f = File('${tmp.path}/fixed.txt')..writeAsBytesSync(bytes);
      final res = await TextFile.parse(f, rules: _rules);
      expect(res.ruleName, '');
      expect(res.chapters.length, greaterThan(3));
      expect(res.chapters.first.name, '第1章');
      final sb = StringBuffer();
      for (final c in res.chapters) {
        sb.write(await TextFile.readChapter(f, c, res.charset));
      }
      expect(sb.toString(), text);
    });

    test('fixed-size fallback also cuts a file that has no line breaks at character boundaries (UTF-8, GBK, UTF-16)', () async {
      final text = List.generate(30000, (i) => String.fromCharCode(0x4e00 + i % 500)).join();
      for (final (name, bytes, charset) in [
        ('u8', Uint8List.fromList(utf8.encode(text)), 'UTF-8'),
        ('gb', Uint8List.fromList(gbk.encode(text)), 'GBK'),
        ('u16', _utf16(text, le: true), 'UTF-16LE'),
      ]) {
        final f = File('${tmp.path}/$name.txt')..writeAsBytesSync(bytes);
        final res = await TextFile.parse(f, rules: _rules, charset: charset);
        expect(res.chapters.length, greaterThan(1), reason: name);
        final sb = StringBuffer();
        for (final c in res.chapters) {
          sb.write(await TextFile.readChapter(f, c, res.charset));
        }
        expect(sb.toString(), text, reason: name);
      }
    });

    test('empty file gives no chapters', () async {
      final f = File('${tmp.path}/empty.txt')..writeAsBytesSync(Uint8List(0));
      final res = await TextFile.parse(f, rules: _rules);
      expect(res.chapters, isEmpty);
    });
  });

  group('helpers', () {
    test('Java-style flags in rules', () {
      final re = TextFile.toDartRegExp(r'(?i)^chapter \d+$')!;
      expect(re.hasMatch('CHAPTER 12'), isTrue);
      expect(TextFile.toDartRegExp(r'(unclosed'), isNull);
    });

    test('file name -> name and author', () {
      expect(TextFile.guessNameAuthor('《斗破苍穹》作者：天蚕土豆'), ('斗破苍穹', '天蚕土豆'));
      expect(TextFile.guessNameAuthor('斗破苍穹 by 天蚕土豆'), ('斗破苍穹', '天蚕土豆'));
      expect(TextFile.guessNameAuthor('斗破苍穹'), ('斗破苍穹', ''));
    });
  });
}
