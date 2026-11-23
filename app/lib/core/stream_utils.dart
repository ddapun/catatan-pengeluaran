import 'dart:async';

/// Menggabungkan dua stream dengan nilai terakhir masing-masing.
Stream<R> combine2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) build,
) {
  late StreamController<R> controller;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  final subs = <StreamSubscription<dynamic>>[];

  void emit() {
    if (hasA && hasB) controller.add(build(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subs.add(a.listen((value) {
        lastA = value;
        hasA = true;
        emit();
      }));
      subs.add(b.listen((value) {
        lastB = value;
        hasB = true;
        emit();
      }));
    },
    onCancel: () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    },
  );
  return controller.stream;
}
