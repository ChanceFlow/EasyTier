import '../models/models.dart';

/// The transport seam between the UI and the EasyTier core.
///
/// Two implementations exist:
///  * [MockCoreClient] — design/development, no Rust needed.
///  * `FfiCoreClient` — `easytier-ffi` over `dart:ffi` (Android, desktop).
///
/// The interface is intentionally small and async; everything the screens need
/// is expressed here so the UI never touches a socket, a file or a TUN fd.
abstract class CoreClient {
  /// One-time initialization: open the native library / connect to the daemon.
  Future<void> init();

  Future<List<NetworkInstance>> listInstances();

  /// Starts a network and returns its instance id.
  Future<String> runInstance(NetworkConfig config);

  Future<void> stopInstance(String id);

  Future<void> deleteInstance(String id);

  Future<void> saveConfig(NetworkConfig config);

  Future<NetworkConfig?> getConfig(String id);

  /// Returns `null` when the config is valid, otherwise a human-readable error.
  Future<String?> validateConfig(NetworkConfig config);

  Future<InstanceStatus> collectStatus(String id);

  Future<String> version();

  /// Push channel for state transitions (connected, peer joined, ...).
  Stream<NetworkEvent> get events;

  Future<void> dispose();
}

/// Implemented by transports that can hand a TUN file descriptor to a running
/// instance (Android `VpnService`, desktop TUN fd injection).
///
/// The descriptor is owned by the platform side that created it; core borrows
/// it. Callers must never close the fd from Dart.
abstract interface class TunFdCapable {
  Future<void> setTunFd(String instanceId, int fd);
}
