import 'package:check_d/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud configuration requires both values', () {
    const missingKey = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: '',
    );
    const complete = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'publishable-key',
    );

    expect(missingKey.hasCloudConfiguration, isFalse);
    expect(complete.hasCloudConfiguration, isTrue);
  });
}
