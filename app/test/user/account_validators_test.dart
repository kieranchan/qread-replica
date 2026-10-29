// The account pages' field checks (pages/user/account_validators.dart) with the original's messages.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/user/account_validators.dart';

void main() {
  test('username: empty, too short, fine', () {
    expect(AccountValidators.username(''), '请输入用户名');
    expect(AccountValidators.username(' ', empty: '请输入用户名或邮箱'), '请输入用户名或邮箱');
    expect(AccountValidators.username('a'), '用户名至少2个字符');
    expect(AccountValidators.username('ab'), isNull);
    expect(AccountValidators.username('  张三 '), isNull);
  });

  test('email: the original regex (any domain, 163/126 included)', () {
    expect(AccountValidators.email(''), '请输入邮箱地址');
    expect(AccountValidators.email('nope'), '请输入有效的邮箱地址');
    expect(AccountValidators.email('a@b'), '请输入有效的邮箱地址');
    expect(AccountValidators.email('user@qq.com'), isNull);
    expect(AccountValidators.email('first.last-1@mail.example.co'), isNull);
    expect(AccountValidators.email('someone@163.com'), isNull);
  });

  test('password, confirmation and the new-password rule', () {
    expect(AccountValidators.password(''), '请输入密码');
    expect(AccountValidators.password('12345'), '密码至少6位');
    expect(AccountValidators.password('123456'), isNull);
    expect(AccountValidators.confirm('123456', ''), '请确认密码');
    expect(AccountValidators.confirm('123456', '1234567'), '两次输入的密码不一致');
    expect(AccountValidators.confirm('123456', '123456'), isNull);
    expect(AccountValidators.newPassword('oldpass', ''), '请输入新密码');
    expect(AccountValidators.newPassword('oldpass', 'short'), '密码至少6位');
    expect(AccountValidators.newPassword('oldpass', 'oldpass'), '新密码不能与当前密码相同');
    expect(AccountValidators.newPassword('oldpass', 'newpass1'), isNull);
  });
}
