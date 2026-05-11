import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_base.dart';

enum NetworkStatus {
  online,
  slow,
  offline,
}

class NetworkStatusService {
  final Connectivity _connectivity;
  final _controller = StreamController<NetworkStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _probeTimer;
  NetworkStatus _currentStatus = NetworkStatus.online;
  bool _started = false;

  NetworkStatusService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  Stream<NetworkStatus> get stream => _controller.stream;
  NetworkStatus get currentStatus => _currentStatus;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _connectivitySub = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_refreshStatus());
    });
    _probeTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      unawaited(_refreshStatus());
    });

    await _refreshStatus();
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _probeTimer?.cancel();
    await _controller.close();
  }

  Future<void> _refreshStatus() async {
    final results = await _connectivity.checkConnectivity();
    final hasConnectionType = results.any((result) => result != ConnectivityResult.none);

    if (!hasConnectionType) {
      _emit(NetworkStatus.offline);
      return;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse('$kApiBaseUrl/health'))
          .timeout(const Duration(seconds: 6));
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (stopwatch.elapsedMilliseconds >= 2500) {
          _emit(NetworkStatus.slow);
        } else {
          _emit(NetworkStatus.online);
        }
        return;
      }

      _emit(NetworkStatus.slow);
    } catch (_) {
      stopwatch.stop();
      _emit(NetworkStatus.slow);
    }
  }

  void _emit(NetworkStatus status) {
    if (status == _currentStatus) return;
    _currentStatus = status;
    if (!_controller.isClosed) {
      _controller.add(status);
    }
  }
}
