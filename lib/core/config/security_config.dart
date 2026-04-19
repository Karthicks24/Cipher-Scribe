abstract class SecurityConfig {
  static const String androidSigninghash = String.fromEnvironment(
    'SIGNING_HASH',
    defaultValue: 'DEBUG_BASE64_HASH_HERE',
  );
  static const String iosTeamId = String.fromEnvironment(
    'IOS_TEAM_ID',
    defaultValue: 'YOUR_TEAM_ID',
  );
}
