//
//  Postgres.swift
//  SwiftTalkServerLib
//
//  Created by Florian Kugler on 01-02-2019.
//

import Foundation
import PostgreSQL
import Base

public struct Postgres {
    private let postgreSQL: PostgreSQL.Database
    
    public init(url: String) {
        let connInfo = ConnInfo.raw(url)
        postgreSQL = try! PostgreSQL.Database(connInfo: connInfo)
    }
    
    public init(host: String, name: String, user: String, password: String) {
        let connInfo = ConnInfo.params([
            "host": host,
            "dbname": name,
            "user": user,
            "password": password,
            "connect_timeout": "1",
            ])
        postgreSQL = try! PostgreSQL.Database(connInfo: connInfo)
    }
    
    public func withConnection<A>(_ x: (ConnectionProtocol) throws -> A) throws -> A {
        let conn = try postgreSQL.makeConnection()
        let result = try x(conn)
        try conn.close()
        return result
    }
    
    public func lazyConnection() -> Lazy<ConnectionProtocol> {
        return Lazy<ConnectionProtocol>({ () throws -> ConnectionProtocol in
            return try self.postgreSQL.makeConnection()
        }, cleanup: { conn in
            try? conn.close()
        })
    }
}

public struct DatabaseError: Error, LocalizedError {
    let err: Error
    let query: String
    
    public init(err: Error, query: String) {
        self.err = err
        self.query = query
    }
    
    public var errorDescription: String? {
        return "\(err), query: \(query)"
    }
}

public protocol ConnectionProtocol {
    func execute(_ query: String, _ values: [PostgreSQL.Node]) throws -> PostgreSQL.Node
    func execute<A>(_ query: Query<A>) throws -> A
    func close() throws
}

extension ConnectionProtocol {
    public func execute(_ query: String) throws -> PostgreSQL.Node {
        return try execute(query, [])
    }
}

extension Connection: ConnectionProtocol { }

public struct FieldValues {
    private var _fields: [(name: String, value: NodeRepresentable)]
    
    init(_ fields: [(name: String, value: NodeRepresentable)]) {
        self._fields = fields
    }
    
    var fields: [String] {
        return _fields.map { $0.name }
    }
    
    public var fieldList: String {
        return fields.sqlJoined
    }
    
    var values: [NodeRepresentable] {
        return _fields.map { $0.value }
    }
}

extension Encodable {
    public var fieldValues: FieldValues {
        let m = Mirror(reflecting: self)
        let children = Array(m.children)
        let names = children.map { $0.label!.snakeCased }
        let values = children.map { $0.value as! NodeRepresentable }
        return FieldValues(Array(zip(names, values)))
    }
}

extension Decodable {
    private static var fieldNames: [String] {
        return try! PropertyNamesDecoder.decode(Self.self).map { $0.snakeCased }
    }
    
    public static func fieldList(_ transform: (String) -> String = { $0 }) -> String {
        return fieldNames.map(transform).sqlJoined
    }
}

extension Connection {
    @discardableResult
    public func execute<A>(_ query: Query<A>) throws -> A {
        return try execute(query, loggingTreshold: 0.1)
    }
    
    @discardableResult
    func execute<A>(_ query: Query<A>, loggingTreshold: TimeInterval) throws -> A {
        //        print(query.query)
        let node = try measure(message: "query: \(query.query)", treshold: loggingTreshold) { () throws -> PostgreSQL.Node in
            do {
                return try execute(query.query, query.values)
            } catch {
                throw DatabaseError(err: error, query: query.query)
            }
        }
        return query.parse(node)
    }
}


