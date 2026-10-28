// util/source/response.dart — `Response` (class 1224, toJson 0xe59820 / 0x1b0aec): what the `http` handler gives the page.
// The bridge library of the pages documents the fields: method; body = the response bytes as base64; headers =
// map<String, List<String>>; statusCode; statusMessage; data = the bytes decoded as text.
class Response {
  final String method;
  final String data;
  final String body;
  final Map<String, List<String>> headers;
  final int statusCode;
  final String statusMessage;

  const Response({
    required this.method,
    this.data = '',
    this.body = '',
    this.headers = const {},
    this.statusCode = 0,
    this.statusMessage = '',
  });

  /// A failed request (0xea7274: empty data/body, status 0, the error as status message).
  factory Response.error(String method, Object error) => Response(method: method, statusMessage: '$error');

  Map<String, dynamic> toJson() => {
        'method': method,
        'data': data,
        'body': body,
        'headers': headers,
        'statusCode': statusCode,
        'statusMessage': statusMessage,
      };
}
