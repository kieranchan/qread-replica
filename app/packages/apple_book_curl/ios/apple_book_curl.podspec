#
# Local plugin of the qread replica: the iOS page-curl page view of the reader (lib/pages/read/pages/novel/apple_book.dart).
#
Pod::Spec.new do |s|
  s.name             = 'apple_book_curl'
  s.version          = '0.1.0'
  s.summary          = 'iOS page-curl page view for the qread replica reader.'
  s.description      = 'A UIPageViewController with the page-curl transition, driven over a method channel with pictures of the pages.'
  s.homepage         = 'https://github.com/kieranchan/qread-replica'
  s.license          = { :type => 'MIT', :text => 'Part of the qread replica (personal use).' }
  s.author           = { 'kieranchan' => 'kieranchan@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
