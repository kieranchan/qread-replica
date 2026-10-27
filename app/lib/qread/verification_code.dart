// qread/verification_code.dart — the captcha dialog (`java.getVerificationCode(url)`): shows the image and returns what the user
// typed. Original: two AlertDialog builders 0x2af2fc (Image + tap to enlarge -> ImageLookPage 0x2b0734) and 0x2b0954
// (CachedCoverImage variant used by the backend channel); both answer with the text field content.
import 'package:flutter/material.dart';

/// Loads the captcha image; replaceable in tests (default: `Image.network`).
Widget Function(String url) verificationImage = (url) => Image.network(url, height: 80, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, size: 48));

Future<String?> showVerificationCodeDialog(BuildContext context, String imageUrl, {String title = '请输入验证码'}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => showDialog<void>(
            context: ctx,
            builder: (c2) => Dialog(child: InteractiveViewer(child: verificationImage(imageUrl))),
          ),
          child: verificationImage(imageUrl),
        ),
        const SizedBox(height: 12),
        TextField(key: const Key('captcha_input'), controller: c, autofocus: true, onSubmitted: (v) => Navigator.of(ctx).pop(v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        TextButton(key: const Key('captcha_ok'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('确定')),
      ],
    ),
  );
}
