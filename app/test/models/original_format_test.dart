// Entries stored by the original (backups, imports) keep their data in the replica's models.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/ai_model_config.dart';
import 'package:newread/models/httptts.dart';

void main() {
  test('HttpTts: the original keeps the engine page as a String', () {
    final e = HttpTts.fromJson({'id': 'x', 'name': '火山', 'tp': 0, 'html': '<html><script>function getttsurl(){}</script></html>'});
    expect(e.html['page'], contains('getttsurl'));
    expect(e.toJson()['html'], isA<String>()); // written back in the original's form
    final legado = HttpTts.fromJson({'id': 'y', 'name': 'HTTP', 'html': {'url': 'http://127.0.0.1/tts', 'contentType': 'audio/mpeg'}});
    expect(legado.toJson()['html'], isA<Map>());
  });

  test('AiModelConfig: the original stores concurrent as a bool', () {
    expect(AiModelConfig.fromJson({'id': 'a', 'concurrent': true}).concurrent, 1);
    expect(AiModelConfig.fromJson({'id': 'a', 'concurrent': false}).concurrent, 0);
    expect(AiModelConfig.fromJson({'id': 'a', 'concurrent': 3}).concurrent, 3);
  });
}
