/* <stdarg.h> for the WebAssembly build of SQLite: Clang's own copy lives in
   its resource directory, which the WebAssembly C toolchain does not list
   (Bazel refuses headers from there), and the WASI C library has none. */
#ifndef SWIFT_SQLITE_WASI_STDARG_H
#define SWIFT_SQLITE_WASI_STDARG_H
typedef __builtin_va_list va_list;
typedef __builtin_va_list __gnuc_va_list;
#define va_start(ap, param) __builtin_va_start(ap, param)
#define va_end(ap) __builtin_va_end(ap)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#define va_copy(dest, src) __builtin_va_copy(dest, src)
#define __va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
