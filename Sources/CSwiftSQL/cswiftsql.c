/* SQLite's amalgamation, built wherever the system has no SQLite of its own
   (Linux, Android, Windows, WebAssembly). On Apple's platforms this file is
   empty: the system's libsqlite3 is linked instead.

   The options live here rather than in a build file, so that Bazel and
   SwiftPM build the same SQLite. */
#if !defined(__APPLE__)

/* Full-text search, as the system SQLite of Apple's platforms has it. */
#define SQLITE_ENABLE_FTS5 1
#define SQLITE_OMIT_LOAD_EXTENSION 1

#if defined(__wasi__)
/* WASI: no dlopen, no shared memory for a write-ahead log, no mmap, and the
   "unix-none" VFS (no locks). SQLite's WASI default, "unix-dotfile", locks
   with a directory beside the database; a host that keeps an app's files
   past its process (a browser keeping them in IndexedDB) would keep that
   directory too if the process ended inside a transaction, and the database
   would stay locked. One process opens a database on a WASI host. */
#define SQLITE_OMIT_WAL 1
#define SQLITE_MAX_MMAP_SIZE 0
#define SQLITE_OMIT_SHARED_CACHE 1
#define SQLITE_DEFAULT_UNIX_VFS "unix-none"
#define _WASI_EMULATED_SIGNAL 1
#define _WASI_EMULATED_PROCESS_CLOCKS 1
#define _WASI_EMULATED_GETPID 1
#define _WASI_EMULATED_MMAN 1
/* Thread-safe over wasi-libc's pthreads where the module has threads
   (wasm32-wasip1-threads, whose atomics feature Clang reports); without
   them there is one thread and nothing to guard. */
#if defined(__wasm_atomics__)
#define SQLITE_THREADSAFE 1
#else
#define SQLITE_THREADSAFE 0
#endif
#endif

#include "amalgamation/sqlite3.c.h"

#endif
