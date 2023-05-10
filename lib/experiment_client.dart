import 'package:experiment_sdk_flutter/http_client.dart';
import 'package:experiment_sdk_flutter/local_storage.dart';
import 'package:experiment_sdk_flutter/types/experiment_config.dart';
import 'package:experiment_sdk_flutter/types/experiment_fetch_input.dart';
import 'package:experiment_sdk_flutter/types/experiment_sources.dart';
import 'package:experiment_sdk_flutter/types/experiment_variant.dart';

class GetSourceAndVariantResult {
  final ExperimentVariant? variant;
  final ExperimentVariantSource source;

  GetSourceAndVariantResult({this.variant, required this.source});
}

class ExperimentClient {
  final ExperimentConfig? _config;
  final HttpClient _httpClient;
  final LocalStorage _localStorage;

  ExperimentClient({required String apiKey, ExperimentConfig? config})
      : _config = config,
        _httpClient = HttpClient(
            apiKey: apiKey, shouldRetry: config?.retryFetchOnFailure),
        _localStorage = LocalStorage(apiKey: apiKey) {
    _localStorage.load();
  }

  Future<void> fetch(
      {String? userId,
      String? deviceId,
      Map<String, dynamic>? userProperties}) async {
    final input = ExperimentFetchInput(
        userId: userId, deviceId: deviceId, userProperties: userProperties);

    await _httpClient.get(input);

    _log(
        '[Experiment] Fetched ${_httpClient.fetchResult.length} for this user!');

    _storeVariants();
  }

  ExperimentVariant? variant(String flagKey) {
    final sourceAndVariant = _getSourceAndVariant(flagKey);
    final variant = sourceAndVariant?.variant;

    if (_config?.automaticExposureTracking != null &&
        _config!.automaticExposureTracking!) {
      exposure(flagKey);
    }

    _log('[Experiment] Variant for $flagKey is ${variant?.value}');

    return variant;
  }

  exposure(String flagKey) {
    final exposureTrackerProvider = _config?.exposureTrackingProvider;
    final sourceAndVariant = _getSourceAndVariant(flagKey);
    final source = sourceAndVariant?.source;
    final variant = sourceAndVariant?.variant;
    final instanceName = _config?.instanceName ?? 'default-instance';

    if (source != null &&
        isFallback(source) &&
        exposureTrackerProvider != null &&
        variant == null) {
      exposureTrackerProvider.exposure(flagKey, null, instanceName);
    } else if (variant != null && exposureTrackerProvider != null) {
      exposureTrackerProvider.exposure(flagKey, variant, instanceName);
    }

    _log(
        '[Experiment] Exposure event logged for $flagKey with variant: ${variant?.value}');
  }

  clear() {
    _localStorage.clear();
    _localStorage.save();
  }

  Map<String, ExperimentVariant> all() {
    return _localStorage.getAll();
  }

  GetSourceAndVariantResult? _getSourceAndVariant(String key) {
    final sourceVariant = _localStorage.get(key);

    if (sourceVariant != null) {
      return GetSourceAndVariantResult(
          variant: sourceVariant,
          source: ExperimentVariantSource.initialVariants);
    }

    if (_config?.fallbackVariant != null) {
      return GetSourceAndVariantResult(
          source: ExperimentVariantSource.fallbackConfig,
          variant: _config?.fallbackVariant);
    }

    return null;
  }

  _storeVariants() {
    _localStorage.clear();

    _httpClient.fetchResult.forEach((key, value) {
      _localStorage.put(key, value.toVariant());
    });

    _localStorage.save();
  }

  _log(String message) {
    if (_config?.debug ?? false) {
      // ignore: avoid_print
      print(message);
    }
  }
}
