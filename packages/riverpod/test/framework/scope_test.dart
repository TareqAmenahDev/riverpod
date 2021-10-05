// Tests related to scoping providers

import 'package:expect_error/expect_error.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../utils.dart';

Future<void> main() async {
  final library = await Library.parseFromStacktrace();

  group('Scoping non-family providers', () {
    test('can override a provider with a reference to the provider directly',
        () {
      final provider = Provider((ref) => 0);
      final container = createContainer();
      final child = createContainer(overrides: [provider]);

      expect(child.read(provider), 0);

      expect(child.getAllProviderElements(), [
        isA<ProviderElement>().having((e) => e.provider, 'provider', provider)
      ]);
      expect(container.getAllProviderElements(), isEmpty);
    });

    test('use latest override on mount', () {
      final provider = Provider((ref) => 0);
      final root = createContainer();
      final container = createContainer(parent: root, overrides: [
        provider.overrideWithValue(42),
      ]);

      container.updateOverrides([
        provider.overrideWithValue(21),
      ]);

      expect(container.read(provider), 21);
    });

    test('updating scoped override does not mount the provider', () {
      final provider = Provider((ref) => 0);
      final root = createContainer();
      final container = createContainer(parent: root, overrides: [
        provider.overrideWithValue(42),
      ]);

      container.updateOverrides([
        provider.overrideWithValue(21),
      ]);

      expect(container.getAllProviderElements(), isEmpty);
      expect(root.getAllProviderElements(), isEmpty);
    });

    test(
        'does not re-initialize a provider if read by an intermediary container',
        () {
      var callCount = 0;
      final provider = Provider((ref) {
        callCount++;
        return 42;
      });
      final root = createContainer();
      final mid = createContainer(parent: root, overrides: [provider]);
      final container = createContainer(parent: mid);

      expect(mid.read(provider), 42);
      expect(callCount, 1);

      expect(container.read(provider), 42);
      expect(callCount, 1);

      expect(root.getAllProviderElements(), isEmpty);
    });
  });

  group('Scoping family', () {
    test('use latest override on mount', () {
      final dep = Provider((ref) => 0);
      final provider = Provider.family<String, int>(
        (ref, value) => '$value ${ref.watch(dep)}',
      );
      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [
          dep.overrideWithValue(1),
          provider,
        ],
      );

      container.updateOverrides([
        dep.overrideWithValue(2),
        provider,
      ]);

      expect(container.read(provider(0)), '0 2');
    });

    test('updating scoped override does not mount the provider', () {
      final dep = Provider((ref) => 0);
      final provider = Provider.family<String, int>(
        (ref, value) => '$value ${ref.watch(dep)}',
      );
      final root = createContainer();
      final container = createContainer(parent: root, overrides: [
        dep.overrideWithValue(1),
        provider,
      ]);

      container.updateOverrides([
        dep.overrideWithValue(2),
        provider,
      ]);

      expect(container.getAllProviderElements(), isEmpty);
      expect(root.getAllProviderElements(), isEmpty);
    });

    test('can override a family with a reference to the provider directly', () {
      final provider = Provider.family<int, int>((ref, param) => 0);
      final container = createContainer();
      final child = createContainer(overrides: [provider]);

      expect(child.read(provider(0)), 0);

      expect(child.getAllProviderElements(), [
        isA<ProviderElement>()
            .having((e) => e.provider, 'provider', provider(0))
      ]);
      expect(container.getAllProviderElements(), isEmpty);
    });

    test(
        'does not re-initialize a provider if read by an intermediary container',
        () {
      final dep = Provider((ref) => 0);
      var callCount = 0;
      final provider = Provider.family<String, int>((ref, value) {
        callCount++;
        return '$value ${ref.watch(dep)}';
      });
      final root = createContainer();
      final mid = createContainer(parent: root, overrides: [
        dep.overrideWithValue(1),
        provider,
      ]);
      final container = createContainer(parent: mid);

      expect(mid.read(provider(0)), '0 1');
      expect(callCount, 1);

      expect(container.read(provider(0)), '0 1');
      expect(callCount, 1);
    });
  });

  group('When specifying "dependencies"', () {
    test('auto scope direct provider dependencies', () {
      final dep = Provider((ref) => 0, name: 'dep');
      var buildCount = 0;
      final provider = Provider((ref) {
        buildCount++;
        return ref.watch(dep);
      }, dependencies: [dep], name: 'provider');
      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );
      final child = createContainer(parent: container);
      final subChild = createContainer(parent: child);

      expect(buildCount, 0);
      expect(container.read(provider), 42);
      expect(buildCount, 1);
      expect(root.read(provider), 0);
      expect(buildCount, 2);
      expect(child.read(provider), 42);
      expect(buildCount, 2);
      expect(subChild.read(provider), 42);
      expect(buildCount, 2);

      final lateChild = createContainer(parent: container);

      expect(lateChild.read(provider), 42);
      expect(buildCount, 2);
    });

    test(
        'auto scope still works if the first read of the auto-override is through a child container',
        () {
      final dep = Provider((ref) => 0, name: 'dep');
      var buildCount = 0;
      final provider = Provider((ref) {
        buildCount++;
        return ref.watch(dep);
      }, dependencies: [dep], name: 'provider');
      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );
      final child = createContainer(parent: container);
      final subChild = createContainer(parent: child);

      expect(subChild.read(provider), 42);
      expect(buildCount, 1);
      expect(child.read(provider), 42);
      expect(buildCount, 1);
      expect(container.read(provider), 42);
      expect(buildCount, 1);
      expect(root.read(provider), 0);
      expect(buildCount, 2);
    });

    test('auto scope transitive provider dependency', () {
      var depBuildCount = 0;
      final dep = Provider((ref) {
        depBuildCount++;
        return 0;
      }, name: 'dep');
      var dep2BuildCount = 0;
      final dep2 = Provider.family<int, int>(
        (ref, multiplier) {
          dep2BuildCount++;
          return ref.watch(dep) * multiplier;
        },
        name: 'dep2',
        dependencies: [dep],
      );
      var dep3BuildCount = 0;
      final dep3 = Provider(
        (ref) {
          dep3BuildCount++;
          return ref.watch(dep2(2));
        },
        name: 'dep3',
        dependencies: [dep2],
      );
      var buildCount = 0;
      final provider = Provider((ref) {
        buildCount++;
        return ref.watch(dep3).toString();
      }, dependencies: [dep3], name: 'provider');

      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );
      final child = createContainer(parent: container);
      final subChild = createContainer(parent: child);

      expect(buildCount, 0);

      expect(container.read(provider), '84');
      expect(container.read(dep3), 84);
      expect(container.read(dep2(2)), 84);
      expect(container.read(dep), 42);
      expect(buildCount, 1);
      expect(dep3BuildCount, 1);
      expect(dep2BuildCount, 1);
      expect(depBuildCount, 0);

      expect(root.read(provider), '0');
      expect(root.read(dep3), 0);
      expect(root.read(dep2(2)), 0);
      expect(root.read(dep), 0);
      expect(buildCount, 2);
      expect(dep3BuildCount, 2);
      expect(dep2BuildCount, 2);
      expect(depBuildCount, 1);

      expect(child.read(provider), '84');
      expect(child.read(dep3), 84);
      expect(child.read(dep2(2)), 84);
      expect(child.read(dep), 42);
      expect(buildCount, 2);
      expect(dep3BuildCount, 2);
      expect(dep2BuildCount, 2);
      expect(depBuildCount, 1);

      expect(subChild.read(provider), '84');
      expect(subChild.read(dep3), 84);
      expect(subChild.read(dep2(2)), 84);
      expect(subChild.read(dep), 42);
      expect(buildCount, 2);
      expect(dep3BuildCount, 2);
      expect(dep2BuildCount, 2);
      expect(depBuildCount, 1);

      final lateChild = createContainer(parent: container);

      expect(lateChild.read(provider), '84');
      expect(container.read(dep3), 84);
      expect(buildCount, 2);
      expect(dep3BuildCount, 2);
    });

    test(
        'when provider depends on multiple overrides, is placed on the deepest container',
        () {
      final dep = Provider((ref) => 0, name: 'dep');
      final dep2 = Provider((ref) => 0, name: 'dep2');
      final a = Provider(
        (ref) => ref.watch(dep) + ref.watch(dep2),
        dependencies: [dep, dep2],
        name: 'a',
      );
      final b = Provider(
        (ref) => ref.watch(dep) - ref.watch(dep2),
        dependencies: [
          dep2,
          dep
        ], // checking that the 'dependencies' order doesn't matter
        name: 'b',
      );
      final root = createContainer();
      final mid = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );
      final mid2 = createContainer(
        parent: mid,
        overrides: [dep2.overrideWithValue(21)],
      );
      final container = createContainer(parent: mid2);

      expect(container.read(a), 63);
      expect(container.read(b), 21);

      expect(container.getAllProviderElements(), isEmpty);
      expect(
        mid2.getAllProviderElements(),
        unorderedEquals(<Object?>[
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', dep2),
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', a),
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', b)
        ]),
      );
      expect(mid.getAllProviderElements(), [
        isA<ProviderElementBase>().having((e) => e.origin, 'origin', dep),
      ]);
      expect(root.getAllProviderElements(), isEmpty);
    });

    test('skips containers with overrides that do not match the "dependencies"',
        () {
      final dep = Provider((ref) => 0, name: 'dep');
      final dep2 = Provider((ref) => 0, name: 'dep2');
      final a = Provider(
        (ref) => ref.watch(dep),
        dependencies: [dep],
        name: 'a',
      );
      final root = createContainer();
      final mid = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );
      final mid2 = createContainer(
        parent: mid,
        overrides: [dep2.overrideWithValue(21)],
      );
      final container = createContainer(parent: mid2);

      expect(container.read(a), 42);

      expect(container.getAllProviderElements(), isEmpty);
      expect(mid2.getAllProviderElements(), isEmpty);
      expect(
        mid.getAllProviderElements(),
        unorderedEquals(<Object?>[
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', dep),
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', a),
        ]),
      );
      expect(root.getAllProviderElements(), isEmpty);
    });

    test(
        'when a provider with dependencies is overridden with a value, '
        'it is no-longer automatically overridden if a lower container overrides a dependency',
        () {
      final dep = Provider((ref) => 0);
      final provider = Provider((ref) => ref.watch(dep), dependencies: [dep]);
      final root = createContainer();
      final mid = createContainer(
        parent: root,
        overrides: [provider.overrideWithValue(42)],
      );
      final container = createContainer(
        parent: mid,
        overrides: [dep.overrideWithValue(84)],
      );

      expect(container.read(provider), 42);
      expect(mid.read(provider), 42);

      expect(container.getAllProviderElements(), isEmpty);
      expect(
        mid.getAllProviderElements(),
        [
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', provider)
        ],
      );
    });

    test('auto scope direct family dependencies', () {
      final family = Provider.family<int, int>((ref, id) => id * 2);
      final provider = Provider(
        (ref) => ref.watch(family(21)),
        dependencies: [family],
      );
      final root = createContainer();
      final mid = createContainer(
        parent: root,
        overrides: [family],
      );
      final container = createContainer(parent: mid);

      expect(container.read(provider), 42);
      expect(mid.read(provider), 42);

      expect(container.getAllProviderElements(), isEmpty);
      expect(
        mid.getAllProviderElements(),
        unorderedEquals(<Object>[
          isA<ProviderElementBase>()
              .having((e) => e.origin, 'origin', provider),
          isA<ProviderElementBase>()
              .having((e) => e.origin, 'origin', family(21))
        ]),
      );
    });

    test('auto scope transitive family dependencies', () {
      final family = Provider.family<int, int>((ref, id) => id * 2);
      final dep = Provider(
        (ref) => ref.watch(family(21)),
        dependencies: [family],
      );
      final provider = Provider((ref) => ref.watch(dep), dependencies: [dep]);
      final root = createContainer();
      final mid = createContainer(
        parent: root,
        overrides: [family],
      );
      final container = createContainer(parent: mid);

      expect(container.read(provider), 42);
      expect(mid.read(provider), 42);

      expect(container.getAllProviderElements(), isEmpty);
      expect(
        mid.getAllProviderElements(),
        unorderedEquals(<Object>[
          isA<ProviderElementBase>()
              .having((e) => e.origin, 'origin', provider),
          isA<ProviderElementBase>().having((e) => e.origin, 'origin', dep),
          isA<ProviderElementBase>()
              .having((e) => e.origin, 'origin', family(21))
        ]),
      );
    });

    test('accepts only providers or families', () async {
      expect(library.withCode('''
import 'package:riverpod/riverpod.dart';

final a = Provider((ref) => 0);

final b = Provider(
  (ref) => 0,
  dependencies: [
    // expect-error: LIST_ELEMENT_TYPE_NOT_ASSIGNABLE
    42,
    // expect-error: LIST_ELEMENT_TYPE_NOT_ASSIGNABLE
    a.select((value) => 42),
  ],
);
'''), compiles);
    });

    test(
        'ProviderRef methods throw if trying to read a provider that is not in the dependencies list',
        () {},
        skip: true);

    test(
        'WidgetRef asserts that all providers in the graph are respecting "dependencies"',
        () {},
        skip: true);
  });
}