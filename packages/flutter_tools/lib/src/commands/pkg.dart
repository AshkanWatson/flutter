import 'dart:io';

import 'package:file/src/interface/directory.dart';
import 'package:file/src/interface/file_system_entity.dart';
import 'package:path/path.dart' as path;

import '../base/common.dart';
import '../base/logger.dart';
import '../cache.dart';
import '../globals.dart' as globals;
import '../runner/flutter_command.dart';

// The main flutter pkg command.
class PkgCommand extends FlutterCommand {
  PkgCommand() {
    addSubcommand(PkgInstallCommand());
    addSubcommand(PkgUninstallCommand());
    addSubcommand(PkgUpgradeCommand());
  }

  @override
  final name = 'pkg';

  @override
  final description =
      'Install, uninstall, or upgrade Dart and Flutter packages globally (offline friendly).';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<FlutterCommandResult> runCommand() async {
    globals.logger.printStatus('Use `flutter pkg <subcommand>`');
    return FlutterCommandResult.success();
  }
}

// Installs a package globally into ~/.flutter-pkg
class PkgInstallCommand extends FlutterCommand {
  @override
  final name = 'install';

  @override
  String get description => 'Install a Dart or Flutter package globally (offline friendly).';

  Directory get _globalFolder {
    final String home = globals.platform.isWindows
        ? globals.platform.environment['USERPROFILE']!
        : globals.platform.environment['HOME']!;
    final Directory dir = globals.fs.directory(path.join(home, '.flutter-pkg'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      // Initialize Flutter package project.
      globals.processManager.runSync(<String>[
        if (globals.platform.isWindows) 'flutter.bat' else 'flutter',
        'create',
        '--template=package',
        '.',
      ], workingDirectory: dir.path);

      pubspec.writeAsStringSync('''
name: flutter_global_packages
description: Global package managed by flutter pkg
publish_to: none
version: 0.0.1

environment:
  sdk: ">=2.12.0 <4.0.0"
  flutter: ">=1.0.0"

dependencies:
dependency_overrides:
''');
    }
    return dir;
  }

  File get _pubspecFile => File(path.join(_globalFolder.path, 'pubspec.yaml'));

  @override
  Future<FlutterCommandResult> runCommand() async {
    final List<String> args = argResults!.rest;
    if (args.isEmpty) {
      globals.logger.printError('Please provide a package name.');
      return FlutterCommandResult.fail();
    }

    final String packageName = args.first;

    // Initialize Flutter root with correct types.
    Cache.flutterRoot = Cache.defaultFlutterRoot(
      platform: globals.platform,
      fileSystem: globals.fs,
      userMessages: globals.userMessages,
    );

    await _ensurePackageCached(packageName);
    _addPackageToPubspec(packageName);
    await _pubGetOffline();

    globals.logger.printStatus('Package $packageName installed globally!');
    return FlutterCommandResult.success();
  }

  Future<void> _pubGetOffline() async {
    final Status status = globals.logger.startProgress(
      'Resolving dependencies (offline)...',
      progressId: 'pkg-pub-get',
    );

    try {
      final ProcessResult result = await globals.processManager.run(<String>[
        if (globals.platform.isWindows) 'flutter.bat' else 'flutter',
        'pub',
        'get',
        '--offline',
      ], workingDirectory: _globalFolder.path);

      if (result.exitCode != 0) {
        throwToolExit('Failed to install package offline:\n${result.stdout}\n${result.stderr}');
      }
    } finally {
      status.stop();
    }
  }

  Future<bool> _isPackageCached(String packageName) async {
    final String pubCache = path.join(
      globals.platform.isWindows
          ? globals.platform.environment['LOCALAPPDATA']!
          : globals.platform.environment['HOME']!,
      'Pub',
      'Cache',
      'hosted',
      'pub.dev',
    );
    final Directory dir = globals.fs.directory(pubCache);
    if (!dir.existsSync()) {
      return false;
    }
    return dir
        .listSync(recursive: true)
        .whereType<Directory>()
        .any((Directory d) => path.basename(d.path) == packageName);
  }

  Future<void> _ensurePackageCached(String packageName) async {
    if (await _isPackageCached(packageName)) {
      return;
    }

    globals.logger.printStatus('Package $packageName not cached.');

    final Status status = globals.logger.startProgress(
      'Downloading $packageName ...',
      progressId: 'pkg-install',
    );

    try {
      final Directory tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_pkg_temp');
      final String safeName = path.basename(tempDir.path).toLowerCase();

      // flutter create
      ProcessResult result = await globals.processManager.run(<String>[
        if (globals.platform.isWindows) 'flutter.bat' else 'flutter',
        'create',
        '--template=package',
        '--project-name',
        safeName,
        '.',
      ], workingDirectory: tempDir.path);

      if (result.exitCode != 0) {
        tempDir.deleteSync(recursive: true);
        throwToolExit('Failed to create temp Flutter project:\n${result.stdout}\n${result.stderr}');
      }
      // update pubspec
      final pubspec = File(path.join(tempDir.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync('''
name: flutter_pkg_temp
description: Temporary project for pkg install
publish_to: none
version: 0.0.1

environment:
  sdk: ">=2.12.0 <4.0.0"
  flutter: ">=1.0.0"

dependencies:
  $packageName: any
''');

      // flutter pub get command
      result = await globals.processManager.run(<String>[
        if (globals.platform.isWindows) 'flutter.bat' else 'flutter',
        'pub',
        'get',
      ], workingDirectory: tempDir.path);

      if (result.exitCode != 0) {
        tempDir.deleteSync(recursive: true);
        throwToolExit('Failed to download package:\n${result.stdout}\n${result.stderr}');
      }

      tempDir.deleteSync(recursive: true);
    } finally {
      status.stop();
    }

    globals.logger.printStatus('$packageName downloaded successfully into Pub cache.');
  }

  void _addPackageToPubspec(String packageName) {
    final List<String> lines = _pubspecFile.readAsStringSync().split('\n');

    final int depsIndex = lines.indexWhere((String line) => line.trim() == 'dependencies:');
    if (depsIndex == -1) {
      lines.add('dependencies:');
      lines.add('  $packageName: any');
    } else if (!lines.any((String line) => line.contains('$packageName:'))) {
      lines.insert(depsIndex + 1, '  $packageName: any');
    }

    final int overridesIndex = lines.indexWhere(
      (String line) => line.trim() == 'dependency_overrides:',
    );
    if (overridesIndex == -1) {
      lines.add('dependency_overrides:');
      lines.add('  $packageName: any');
    } else if (!lines.any((String line) => line.contains('$packageName:'))) {
      lines.insert(overridesIndex + 1, '  $packageName: any');
    }

    _pubspecFile.writeAsStringSync(lines.join('\n'));
  }
}

// Uninstalls a globally installed package.
class PkgUninstallCommand extends FlutterCommand {
  PkgUninstallCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Also delete package from the global Pub cache (destructive).',
    ); // Uninstall completely using --force flag (Pub/Cache/hosted/pub.dev)
    argParser.addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt when using --force.');
  }

  @override
  String get name => 'uninstall';

  @override
  String get description => 'Uninstall a Flutter package globally.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final List<String> args = argResults!.rest;
    if (args.isEmpty) {
      globals.logger.printError('Please provide a package name.');
      return FlutterCommandResult.fail();
    }
    final String packageName = args.first;
    final force = argResults!['force'] as bool;
    final autoYes = argResults!['yes'] as bool;

    globals.logger.printStatus('Uninstalling package: $packageName');

    try {
      // 1. Remove from ~/.flutter-pkg
      final Directory cacheDir = globals.fs.directory(
        '${Platform.environment['HOME']}/.flutter-pkg/$packageName',
      );
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
        globals.logger.printStatus('Removed from ~/.flutter-pkg.');
      }

      // 2. If --force, remove from PubCache too
      if (force) {
        if (!autoYes) {
          globals.logger.printWarning(
            'WARNING: This will permanently remove $packageName from the global Pub cache.\n'
            'This may break other projects.\n'
            'Continue? (y/N): ',
          );
          final String? input = stdin.readLineSync()?.trim().toLowerCase();
          if (input != 'y' && input != 'yes') {
            globals.logger.printStatus('Aborted.');
            return FlutterCommandResult.success();
          }
        }

        final String pubCache =
            Platform.environment['PUB_CACHE'] ??
            (Platform.isWindows
                ? '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache'
                : '${Platform.environment['HOME']}/.pub-cache');

        final Directory hosted = globals.fs.directory('$pubCache/hosted/pub.dev');
        if (hosted.existsSync()) {
          for (final FileSystemEntity dir in hosted.listSync()) {
            if (dir.basename.startsWith('$packageName-')) {
              dir.deleteSync(recursive: true);
              globals.logger.printStatus('Removed ${dir.basename} from PubCache.');
            }
          }
        }

        // TODO: also clean up hashes/bin if necessary
      }

      return FlutterCommandResult.success();
    } catch (e) {
      globals.logger.printError('Failed to uninstall package: $e');
      return FlutterCommandResult.fail();
    }
  }
}

// Upgrades all globally installed packages.
class PkgUpgradeCommand extends FlutterCommand {
  @override
  final name = 'upgrade';

  @override
  String get description => 'Upgrade all globally installed packages.';

  Directory get _globalFolder {
    final String home = globals.platform.isWindows
        ? globals.platform.environment['USERPROFILE']!
        : globals.platform.environment['HOME']!;
    return globals.fs.directory(path.join(home, '.flutter-pkg'));
  }

  File get _pubspecFile => globals.fs.file(path.join(_globalFolder.path, 'pubspec.yaml'));

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (!_pubspecFile.existsSync()) {
      globals.logger.printError('No global packages installed.');
      return FlutterCommandResult.fail();
    }

    globals.logger.printStatus('Upgrading all global packages offline...');

    final ProcessResult result = await globals.processManager.run(<String>[
      if (globals.platform.isWindows) 'flutter.bat' else 'flutter',
      'pub',
      'upgrade',
      '--offline',
    ], workingDirectory: _globalFolder.path);

    if (result.exitCode != 0) {
      throwToolExit('Failed to upgrade packages:\n${result.stdout}\n${result.stderr}');
    }

    globals.logger.printStatus('All global packages upgraded!');
    return FlutterCommandResult.success();
  }
}
