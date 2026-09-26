/// Build stamp set by `tool/build_web.sh`, shown so testers can tell which
/// version their browser is running.
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');
