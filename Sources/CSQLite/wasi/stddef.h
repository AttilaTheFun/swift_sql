/* <stddef.h> for the WebAssembly build of SQLite (see stdarg.h here). It
   follows the compiler's protocol: with a __need_ macro set, it defines only
   what was asked for, as the C library's headers expect. */
#if defined(__need_size_t) || defined(__need_ptrdiff_t) || defined(__need_wchar_t) \
    || defined(__need_NULL) || defined(__need_wint_t) || defined(__need_max_align_t)
#define SWIFT_SQLITE_STDDEF_PARTIAL 1
#else
#define __need_size_t
#define __need_ptrdiff_t
#define __need_wchar_t
#define __need_NULL
#define __need_max_align_t
#define SWIFT_SQLITE_STDDEF_WHOLE 1
#endif

#ifdef __need_size_t
#ifndef _SIZE_T
#define _SIZE_T
typedef __SIZE_TYPE__ size_t;
#endif
#undef __need_size_t
#endif

#ifdef __need_ptrdiff_t
#ifndef _PTRDIFF_T
#define _PTRDIFF_T
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#endif
#undef __need_ptrdiff_t
#endif

#ifdef __need_wchar_t
#ifndef __cplusplus
#ifndef _WCHAR_T
#define _WCHAR_T
typedef __WCHAR_TYPE__ wchar_t;
#endif
#endif
#undef __need_wchar_t
#endif

#ifdef __need_wint_t
#ifndef _WINT_T
#define _WINT_T
typedef __WINT_TYPE__ wint_t;
#endif
#undef __need_wint_t
#endif

#ifdef __need_NULL
#undef NULL
#ifdef __cplusplus
#define NULL __null
#else
#define NULL ((void *)0)
#endif
#undef __need_NULL
#endif

#ifdef __need_max_align_t
#ifndef SWIFT_SQLITE_MAX_ALIGN_T
#define SWIFT_SQLITE_MAX_ALIGN_T
typedef struct {
  long long __ll;
  long double __ld;
} max_align_t;
#endif
#undef __need_max_align_t
#endif

#ifdef SWIFT_SQLITE_STDDEF_WHOLE
#undef SWIFT_SQLITE_STDDEF_WHOLE
#ifndef offsetof
#define offsetof(t, d) __builtin_offsetof(t, d)
#endif
#endif
#undef SWIFT_SQLITE_STDDEF_PARTIAL
