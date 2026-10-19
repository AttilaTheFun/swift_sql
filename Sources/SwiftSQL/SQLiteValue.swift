/// A value as SQLite stores it: one of its five storage classes.
public enum SQLiteValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The integer, or nil for anything else.
    public var int64: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The integer, or nil for anything else (or one past `Int`'s range).
    public var int: Int? { int64.flatMap { Int(exactly: $0) } }

    /// The number: a real, or an integer as a real; nil for anything else.
    public var double: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    /// The text, or nil for anything else.
    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    /// The bytes, or nil for anything else.
    public var blob: [UInt8]? {
        if case .blob(let value) = self { return value }
        return nil
    }
}

/// A Swift value that binds to a statement's parameter.
public protocol SQLiteBindable {
    var sqliteValue: SQLiteValue { get }
}

extension SQLiteValue: SQLiteBindable {
    public var sqliteValue: SQLiteValue { self }
}

extension Int: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Int64: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(self) }
}

extension Int32: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Int16: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Int8: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension UInt32: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension UInt16: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension UInt8: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Bool: SQLiteBindable {
    /// 1 or 0, as SQLite keeps booleans.
    public var sqliteValue: SQLiteValue { .integer(self ? 1 : 0) }
}

extension Double: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .real(self) }
}

extension Float: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .real(Double(self)) }
}

extension String: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .text(self) }
}

extension Substring: SQLiteBindable {
    public var sqliteValue: SQLiteValue { .text(String(self)) }
}

extension Array: SQLiteBindable where Element == UInt8 {
    public var sqliteValue: SQLiteValue { .blob(self) }
}

extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {
    /// The wrapped value's, or NULL.
    public var sqliteValue: SQLiteValue { self?.sqliteValue ?? .null }
}
