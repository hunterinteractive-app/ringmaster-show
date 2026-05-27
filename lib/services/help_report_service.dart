// lib/services/help_report_service.dart

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/config/app_versions.dart';
import 'package:ringmaster_show/services/app_session.dart';

class HelpReportService {
  HelpReportService._();

  static const String _screenshotBucket = 'help-report-screenshots';

  static final ScreenshotController screenshotController = ScreenshotController();
  static final _supabase = Supabase.instance.client;

  static Future<void> submitReport({
    required String message,
    String? pageTitle,
    String? pageRoute,
    String? showId,
    BuildContext? context,
  }) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message cannot be empty.');
    }

    final user = _supabase.auth.currentUser;
    final deviceInfo = await _collectDeviceInfo();
    final cleanedShowId = showId == null || showId.trim().isEmpty
        ? null
        : showId.trim();

    int? screenWidth;
    int? screenHeight;

    if (context != null) {
      final size = MediaQuery.maybeOf(context)?.size;
      if (size != null) {
        screenWidth = size.width.round();
        screenHeight = size.height.round();
      }
    }

    final screenshot = await _captureAndUploadScreenshot(
      userId: user?.id,
      pageTitle: pageTitle ?? 'unknown-page',
    );

    final enhancedDeviceInfo = <String, dynamic>{
      ...deviceInfo,
      if (screenshot.error != null) 'screenshot_error': screenshot.error,
    };

    await _supabase.from('help_reports').insert({
      'user_id': user?.id,
      'user_email': user?.email,
      'show_id': cleanedShowId,
      'page_title': pageTitle,
      'page_route': pageRoute,
      'message': trimmedMessage,
      'app_version': kRingMasterAppVersion,
      'build_number': kRingMasterBuildNumber,
      'workflow_version': kRingMasterWorkflowVersion,
      'platform': deviceInfo['platform'],
      'operating_system': deviceInfo['operating_system'],
      'browser_user_agent': deviceInfo['browser_user_agent'],
      'device_info': enhancedDeviceInfo,
      'screen_width': screenWidth,
      'screen_height': screenHeight,
      'support_mode': AppSession.isSupportMode,
      'screenshot_path': screenshot.path,
      'screenshot_url': screenshot.signedUrl,
    });
  }

  static Future<_ScreenshotUploadResult> _captureAndUploadScreenshot({
    required String? userId,
    required String pageTitle,
  }) async {
    try {
      final bytes = await screenshotController.capture(
        pixelRatio: 1,
        delay: const Duration(milliseconds: 150),
      );

      if (bytes == null || bytes.isEmpty) {
        return const _ScreenshotUploadResult(
          error: 'Screenshot capture returned no image bytes.',
        );
      }

      final safePageTitle = pageTitle
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-');
      final owner = userId == null || userId.isEmpty ? 'anonymous' : userId;
      final fileName = safePageTitle.isEmpty ? 'page' : safePageTitle;
      final path = '$owner/$timestamp-$fileName.png';

      await _supabase.storage.from(_screenshotBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );

      String? signedUrl;
      try {
        signedUrl = await _supabase.storage
            .from(_screenshotBucket)
            .createSignedUrl(path, 60 * 60 * 24 * 7);
      } catch (_) {
        signedUrl = null;
      }

      return _ScreenshotUploadResult(
        path: path,
        signedUrl: signedUrl,
      );
    } catch (e) {
      return _ScreenshotUploadResult(error: e.toString());
    }
  }

  static Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final plugin = DeviceInfoPlugin();

    try {
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return {
          'platform': 'web',
          'operating_system': info.platform,
          'browser_name': info.browserName.name,
          'browser_user_agent': info.userAgent,
          'vendor': info.vendor,
          'language': info.language,
          'hardware_concurrency': info.hardwareConcurrency,
        };
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        return {
          'platform': 'android',
          'operating_system': 'Android ${info.version.release}',
          'manufacturer': info.manufacturer,
          'model': info.model,
          'device': info.device,
          'sdk_int': info.version.sdkInt,
        };
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        return {
          'platform': 'ios',
          'operating_system': '${info.systemName} ${info.systemVersion}',
          'model': info.model,
          'localized_model': info.localizedModel,
          'name': info.name,
        };
      }

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await plugin.macOsInfo;
        return {
          'platform': 'macos',
          'operating_system': 'macOS ${info.osRelease}',
          'model': info.model,
          'computer_name': info.computerName,
        };
      }

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await plugin.windowsInfo;
        return {
          'platform': 'windows',
          'operating_system': 'Windows',
          'computer_name': info.computerName,
          'number_of_cores': info.numberOfCores,
        };
      }

      if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await plugin.linuxInfo;
        return {
          'platform': 'linux',
          'operating_system': info.prettyName,
          'name': info.name,
          'version': info.version,
        };
      }

      return {
        'platform': Platform.operatingSystem,
        'operating_system': Platform.operatingSystemVersion,
      };
    } catch (e) {
      return {
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'device_info_error': e.toString(),
      };
    }
  }
}

class _ScreenshotUploadResult {
  final String? path;
  final String? signedUrl;
  final String? error;

  const _ScreenshotUploadResult({
    this.path,
    this.signedUrl,
    this.error,
  });
}