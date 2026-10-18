/// Synthetic-only DPAPI primitive probe. Does not open the Qesto/plugin vault.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class _Blob extends Struct {
  @Uint32()
  external int length;
  external Pointer<Uint8> bytes;
}

typedef _CryptNative =
    Int32 Function(
      Pointer<_Blob>,
      Pointer<Void>,
      Pointer<_Blob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_Blob>,
    );
typedef _CryptDart =
    int Function(
      Pointer<_Blob>,
      Pointer<Void>,
      Pointer<_Blob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_Blob>,
    );

class WindowsKeyProbe {
  static Uint8List protect(List<int> bytes) => _transform(bytes, false);
  static Uint8List unprotect(List<int> bytes) => _transform(bytes, true);

  static Uint8List _transform(List<int> bytes, bool decrypt) {
    if (!Platform.isWindows) throw UnsupportedError('Windows DPAPI only');
    final input = calloc<_Blob>();
    final output = calloc<_Blob>();
    final data = calloc<Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    input.ref
      ..length = bytes.length
      ..bytes = data;
    final crypt = DynamicLibrary.open('crypt32.dll')
        .lookupFunction<_CryptNative, _CryptDart>(
          decrypt ? 'CryptUnprotectData' : 'CryptProtectData',
        );
    final localFree = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree');
    try {
      final ok = crypt(input, nullptr, nullptr, nullptr, nullptr, 1, output);
      if (ok == 0 || output.ref.bytes == nullptr)
        throw StateError('DPAPI failed; do not regenerate key');
      return Uint8List.fromList(
        output.ref.bytes.asTypedList(output.ref.length),
      );
    } finally {
      data.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      if (output.ref.bytes != nullptr) {
        output.ref.bytes
            .asTypedList(output.ref.length)
            .fillRange(0, output.ref.length, 0);
        localFree(output.ref.bytes.cast());
      }
      calloc.free(data);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
