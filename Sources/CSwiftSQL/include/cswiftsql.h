/* CSwiftSQL: SQLite's C API as one module. The system's SQLite on Apple's
   platforms (the SDK's sqlite3.h, libsqlite3); everywhere else SQLite's
   amalgamation, built by cswiftsql.c from the copy in amalgamation/. */
#ifndef CSQLITE_H
#define CSQLITE_H

#if defined(__APPLE__)
#include <sqlite3.h>
#else
#include "../amalgamation/sqlite3.h"
#endif

/* SQLITE_TRANSIENT, which Swift cannot import (it casts -1 to a function
   pointer): SQLite copies the bytes before the bind call returns. */
static inline sqlite3_destructor_type cswiftsql_transient(void) {
    return (sqlite3_destructor_type)-1;
}

#endif
