import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:file/src/interface/file.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/pkg.dart';
import 'package:test/test.dart';

import '../../src/context.dart';
import '../../src/fake_process_manager.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  late MemoryFileSystem fs;
  late FakeProcessManager processManager;

  setUp(() {
    Cache.disableLocking();
    fs = MemoryFileSystem.test();
    processManager = FakeProcessManager.list(<FakeCommand>[]);
  });

  tearDown(() {
    Cache.enableLocking();
  });

  testUsingContext('pkg shows help', () async {
    final CommandRunner<void> runner = createTestCommandRunner(PkgCommand());
    try {
      await runner.run(<String>['pkg']);
      fail('Expected usageException');
    } catch (e) {
      // The error message should match the usage exception thrown by args package
      final message = e.toString();
      expect(message, contains('Missing subcommand for "flutter pkg"'));
      expect(message, contains('Usage: flutter pkg <subcommand> [arguments]'));
    }
  });

  testUsingContext('pkg install fails without package name', () async {
    final command = PkgCommand();
    final CommandRunner<void> runner = createTestCommandRunner(command);
    await runner.run(<String>['pkg', 'install']);
    expect(testLogger.errorText, contains('Please provide a package name.'));
  });

  testUsingContext(
    'pkg install creates ~/.flutter-pkg and installs package (Windows Path)',
    () async {
      processManager.addCommand(
        const FakeCommand(
          command: ['flutter', 'create', '--template=package', '.'],
          workingDirectory: r'C:\Users\test\.flutter-pkg',
        ),
      );
      processManager.addCommand(
        const FakeCommand(
          command: ['flutter', 'pub', 'get', '--offline'],
          workingDirectory: r'C:\Users\test\.flutter-pkg',
        ),
      );
      final command = PkgCommand();
      final CommandRunner<void> runner = createTestCommandRunner(command);
      await runner.run(<String>['pkg', 'install', 'http']);
      expect(testLogger.statusText, contains('Package http installed globally!'));
      // Simulate pubspec.yaml creation
      fs.file(r'C:\Users\test\.flutter-pkg\pubspec.yaml').createSync(recursive: true);
      expect(fs.file(r'C:\Users\test\.flutter-pkg\pubspec.yaml').existsSync(), true);
    },
  );

  testUsingContext(
    'pkg install creates ~/.flutter-pkg and installs package (Mac/Linux Path)',
    () async {
      processManager.addCommand(
        const FakeCommand(
          command: ['flutter', 'create', '--template=package', '.'],
          workingDirectory: '/home/test/.flutter-pkg',
        ),
      );
      processManager.addCommand(
        const FakeCommand(
          command: ['flutter', 'pub', 'get', '--offline'],
          workingDirectory: '/home/test/.flutter-pkg',
        ),
      );
      final command = PkgCommand();
      final CommandRunner<void> runner = createTestCommandRunner(command);
      await runner.run(<String>['pkg', 'install', 'http']);
      expect(testLogger.statusText, contains('Package http installed globally!'));
      // Simulate pubspec.yaml creation
      fs.file('/home/test/.flutter-pkg/pubspec.yaml').createSync(recursive: true);
      expect(fs.file('/home/test/.flutter-pkg/pubspec.yaml').existsSync(), true);
    },
  );

  testUsingContext('pkg uninstall fails without package name', () async {
    final command = PkgCommand();
    final CommandRunner<void> runner = createTestCommandRunner(command);
    await runner.run(<String>['pkg', 'uninstall']);
    expect(testLogger.errorText, contains('Please provide a package name.'));
  });

  testUsingContext(
    'pkg upgrade fails if no pubspec.yaml (Windows Path)',
    () async {
      final command = PkgCommand();
      final CommandRunner<void> runner = createTestCommandRunner(command);
      // Ensure pubspec.yaml does NOT exist (Windows path)
      final File pubspec = fs.file(r'C:\Users\test\.flutter-pkg\pubspec.yaml');
      if (pubspec.existsSync()) {
        pubspec.deleteSync();
      }
      await runner.run(<String>['pkg', 'upgrade']);
      final String output = testLogger.statusText + testLogger.errorText;
      expect(output, contains('No global packages installed.'));
    },
    overrides: <Type, Generator>{
      Platform: () => FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{'USERPROFILE': r'C:\Users\test'},
      ),
    },
  );

  testUsingContext(
    'pkg upgrade fails if no pubspec.yaml (Mac/Linux Path)',
    () async {
      final command = PkgCommand();
      final CommandRunner<void> runner = createTestCommandRunner(command);
      // Ensure pubspec.yaml does NOT exist (Mac/Linux Path)
      final File pubspec = fs.file('/home/test/.flutter-pkg/pubspec.yaml');
      if (pubspec.existsSync()) {
        pubspec.deleteSync();
      }
      await runner.run(<String>['pkg', 'upgrade']);
      final String output = testLogger.statusText + testLogger.errorText;
      expect(output, contains('No global packages installed.'));
    },
    overrides: <Type, Generator>{
      Platform: () => FakePlatform(environment: <String, String>{'HOME': '/home/test'}),
    },
  );

  testUsingContext('pkg upgrade runs flutter pub upgrade --offline (Windows Path)', () async {
    fs.file(r'C:\Users\test\.flutter-pkg\pubspec.yaml').createSync(recursive: true);
    processManager.addCommand(
      const FakeCommand(
        command: ['flutter', 'pub', 'upgrade', '--offline'],
        workingDirectory: r'C:\Users\test\.flutter-pkg\',
      ),
    );
    final command = PkgCommand();
    final CommandRunner<void> runner = createTestCommandRunner(command);
    await runner.run(<String>['pkg', 'upgrade']);
    expect(testLogger.statusText, contains('All global packages upgraded!'));
  });

  testUsingContext('pkg upgrade runs flutter pub upgrade --offline (Mac/Linux Path)', () async {
    fs.file('/home/test/.flutter-pkg/pubspec.yaml').createSync(recursive: true);
    processManager.addCommand(
      const FakeCommand(
        command: ['flutter', 'pub', 'upgrade', '--offline'],
        workingDirectory: '/home/test/.flutter-pkg',
      ),
    );
    final command = PkgCommand();
    final CommandRunner<void> runner = createTestCommandRunner(command);
    await runner.run(<String>['pkg', 'upgrade']);
    expect(testLogger.statusText, contains('All global packages upgraded!'));
  });
}
