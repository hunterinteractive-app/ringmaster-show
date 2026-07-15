import 'dart:io';

final class WorkerConfig {
  WorkerConfig({
    required this.workerId,
    required this.batchSize,
    required this.pollInterval,
    required this.maxConcurrentRenders,
    required this.assetRoot,
    required this.continuous,
    required this.dryRun,
    required this.port,
    required this.buildVersion,
    this.dispatchConcurrency = 1,
    this.dispatchMaxRounds = 1,
    this.supabaseUrl,
    this.serviceRoleKey,
    this.storageBucket,
    this.workToken,
    this.workerBaseUrl,
  }) {
    if (!dryRun &&
        ((supabaseUrl ?? '').isEmpty || (serviceRoleKey ?? '').isEmpty)) {
      throw const FormatException(
        'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required outside dry-run mode.',
      );
    }
    _validateRange(
      'DISPATCH_CONCURRENCY',
      dispatchConcurrency,
      minimum: 1,
      maximum: 25,
    );
    _validateRange(
      'DISPATCH_MAX_ROUNDS',
      dispatchMaxRounds,
      minimum: 1,
      maximum: 5,
    );
    if (workerBaseUrl != null &&
        (!workerBaseUrl!.hasScheme ||
            !const {'http', 'https'}.contains(workerBaseUrl!.scheme) ||
            workerBaseUrl!.host.isEmpty)) {
      throw const FormatException(
        'WORKER_BASE_URL must be an absolute HTTP or HTTPS URL.',
      );
    }
  }

  factory WorkerConfig.fromEnvironment({List<String> arguments = const []}) {
    final environment = Platform.environment;
    final dryRun = arguments.contains('--dry-run');
    final continuous = arguments.contains('--continuous');
    return WorkerConfig(
      supabaseUrl: environment['SUPABASE_URL'],
      serviceRoleKey: environment['SUPABASE_SERVICE_ROLE_KEY'],
      workerId:
          environment['WORKER_ID'] ?? 'closeout-${Platform.localHostname}-$pid',
      batchSize: _integer(environment, 'TASK_BATCH_SIZE', 5, 1, 25),
      pollInterval: Duration(
        seconds: _integer(environment, 'POLL_INTERVAL_SECONDS', 10, 1, 300),
      ),
      maxConcurrentRenders: _integer(
        environment,
        'MAX_CONCURRENT_RENDERS',
        2,
        1,
        8,
      ),
      storageBucket: _optional(environment['STORAGE_BUCKET']),
      assetRoot: Directory(environment['ASSET_ROOT'] ?? 'assets'),
      workToken: _optional(environment['WORK_TRIGGER_TOKEN']),
      workerBaseUrl: _optionalUri(environment['WORKER_BASE_URL']),
      dispatchConcurrency: _integer(
        environment,
        'DISPATCH_CONCURRENCY',
        1,
        1,
        25,
      ),
      dispatchMaxRounds: _integer(environment, 'DISPATCH_MAX_ROUNDS', 1, 1, 5),
      continuous: continuous,
      dryRun: dryRun,
      port: _integer(environment, 'PORT', 8080, 1, 65535),
      buildVersion: environment['BUILD_VERSION'] ?? 'development',
    );
  }

  final String? supabaseUrl;
  final String? serviceRoleKey;
  final String workerId;
  final int batchSize;
  final Duration pollInterval;
  final int maxConcurrentRenders;
  final String? storageBucket;
  final Directory assetRoot;
  final String? workToken;
  final Uri? workerBaseUrl;
  final int dispatchConcurrency;
  final int dispatchMaxRounds;
  final bool continuous;
  final bool dryRun;
  final int port;
  final String buildVersion;

  static int _integer(
    Map<String, String> environment,
    String name,
    int fallback,
    int minimum,
    int maximum,
  ) {
    final value = int.tryParse(environment[name] ?? '') ?? fallback;
    if (value < minimum || value > maximum) {
      throw FormatException('$name must be between $minimum and $maximum.');
    }
    return value;
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static Uri? _optionalUri(String? value) {
    final normalized = _optional(value);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      throw const FormatException('WORKER_BASE_URL must be a valid URL.');
    }
    return uri;
  }

  static void _validateRange(
    String name,
    int value, {
    required int minimum,
    required int maximum,
  }) {
    if (value < minimum || value > maximum) {
      throw FormatException('$name must be between $minimum and $maximum.');
    }
  }
}
