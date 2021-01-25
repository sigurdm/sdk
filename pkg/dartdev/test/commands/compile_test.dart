// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../utils.dart';

const int compileErrorExitCode = 64;

void main() {
  group('compile', defineCompileTests, timeout: longTimeout);
}

const String soundNullSafetyMessage = 'Info: Compiling with sound null safety';
const String unsoundNullSafetyMessage =
    'Info: Compiling without sound null safety';

void defineCompileTests() {
  // *** NOTE ***: These tests *must* be run with the `--use-sdk` option
  // as they depend on a fully built SDK to resolve various snapshot files
  // used by compilation.
  test('Running from built SDK', () {
    final Directory binDir = File(Platform.resolvedExecutable).parent;
    expect(binDir.path, contains('bin'));
  });

  test('Implicit --help', () {
    final p = project();
    var result = p.runSync(
      [
        'compile',
      ],
    );
    expect(result.stderr, contains('Compile Dart'));
    expect(result.exitCode, compileErrorExitCode);
  });

  test('--help', () {
    final p = project();
    final result = p.runSync(
      ['compile', '--help'],
    );
    expect(result.stdout, contains('Compile Dart'));
    expect(result.exitCode, 0);
  });

  test('Compile and run jit snapshot', () {
    final p = project(mainSrc: 'void main() { print("I love jit"); }');
    final outFile = path.join(p.dirPath, 'main.jit');
    var result = p.runSync(
      [
        'compile',
        'jit-snapshot',
        '-o',
        outFile,
        p.relativeFilePath,
      ],
    );
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');

    result = p.runSync(['run', 'main.jit']);
    expect(result.stdout, contains('I love jit'));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });

  test('Compile and run executable', () {
    final p = project(mainSrc: 'void main() { print("I love executables"); }');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'lib', 'main.exe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        inFile,
      ],
    );

    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');

    result = Process.runSync(
      outFile,
      [],
    );

    expect(result.stdout, contains('I love executables'));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });

  test('Compile and run executable with options', () {
    final p = project(
        mainSrc: 'void main() {print(const String.fromEnvironment("life"));}');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '--define',
        'life=42',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');

    result = Process.runSync(
      outFile,
      [],
    );

    expect(result.stdout, contains('42'));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });

  test('Compile and run aot snapshot', () {
    final p = project(mainSrc: 'void main() { print("I love AOT"); }');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'main.aot'));

    var result = p.runSync(
      [
        'compile',
        'aot-snapshot',
        '-o',
        'main.aot',
        inFile,
      ],
    );

    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');

    final Directory binDir = File(Platform.resolvedExecutable).parent;
    result = Process.runSync(
      path.join(binDir.path, 'dartaotruntime'),
      [outFile],
    );

    expect(result.stdout, contains('I love AOT'));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });

  test('Compile and run kernel snapshot', () {
    final p = project(mainSrc: 'void main() { print("I love kernel"); }');
    final outFile = path.join(p.dirPath, 'main.dill');
    var result = p.runSync(
      [
        'compile',
        'kernel',
        '-o',
        outFile,
        p.relativeFilePath,
      ],
    );
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);

    result = p.runSync(['run', 'main.dill']);
    expect(result.stdout, contains('I love kernel'));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });

  test('Compile JS', () {
    final p = project(mainSrc: "void main() { print('Hello from JS'); }");
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'main.js'));

    final result = p.runSync([
      'compile',
      'js',
      '-m',
      '-o',
      outFile,
      '-v',
      inFile,
    ]);
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile exe with error', () {
    final p = project(mainSrc: '''
void main() {
  int? i;
  i.isEven;
}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Error: '));
    // The CFE doesn't print to stderr, so all output is piped to stderr, even
    // including info-only output:
    expect(result.stderr, contains(soundNullSafetyMessage));
    expect(result.exitCode, compileErrorExitCode);
    expect(File(outFile).existsSync(), false,
        reason: 'File not found: $outFile');
  });

  test('Compile exe with warning', () {
    final p = project(mainSrc: '''
void main() {
  int i = 0;
  i?.isEven;
}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains('Warning: '));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile exe with sound null safety', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(soundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile exe with unsound null safety', () {
    final p = project(mainSrc: '''
// @dart=2.9
void main() {}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(unsoundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile exe without info', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myexe'));

    var result = p.runSync(
      [
        'compile',
        'exe',
        '--verbosity=warning',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout,
        predicate((o) => !'$o'.contains(soundNullSafetyMessage)));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile JS with sound null safety', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myjs'));

    var result = p.runSync(
      [
        'compile',
        'js',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(soundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile JS with unsound null safety', () {
    final p = project(mainSrc: '''
// @dart=2.9
void main() {}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myjs'));

    var result = p.runSync(
      [
        'compile',
        'js',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(unsoundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile JS without info', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myjs'));

    var result = p.runSync(
      [
        'compile',
        'js',
        '--verbosity=warning',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout,
        predicate((o) => !'$o'.contains(soundNullSafetyMessage)));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile AOT snapshot with sound null safety', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myaot'));

    var result = p.runSync(
      [
        'compile',
        'aot-snapshot',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(soundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile AOT snapshot with unsound null safety', () {
    final p = project(mainSrc: '''
// @dart=2.9
void main() {}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myaot'));

    var result = p.runSync(
      [
        'compile',
        'aot-snapshot',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(unsoundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile AOT snapshot without info', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myaot'));

    var result = p.runSync(
      [
        'compile',
        'aot-snapshot',
        '--verbosity=warning',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout,
        predicate((o) => !'$o'.contains(soundNullSafetyMessage)));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile kernel with sound null safety', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'mydill'));

    var result = p.runSync(
      [
        'compile',
        'kernel',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(soundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile kernel with unsound null safety', () {
    final p = project(mainSrc: '''
// @dart=2.9
void main() {}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'mydill'));

    var result = p.runSync(
      [
        'compile',
        'kernel',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(unsoundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile JIT snapshot with sound null safety', () {
    final p = project(mainSrc: '''void main() {}''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myjit'));

    var result = p.runSync(
      [
        'compile',
        'jit-snapshot',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(soundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });

  test('Compile JIT snapshot with unsound null safety', () {
    final p = project(mainSrc: '''
// @dart=2.9
void main() {}
''');
    final inFile = path.canonicalize(path.join(p.dirPath, p.relativeFilePath));
    final outFile = path.canonicalize(path.join(p.dirPath, 'myjit'));

    var result = p.runSync(
      [
        'compile',
        'jit-snapshot',
        '-o',
        outFile,
        inFile,
      ],
    );

    expect(result.stdout, contains(unsoundNullSafetyMessage));
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(File(outFile).existsSync(), true,
        reason: 'File not found: $outFile');
  });
}
