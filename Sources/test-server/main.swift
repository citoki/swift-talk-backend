import Foundation
import NIOWrapper

struct User {
    var name: String
}

struct Session {
    var user: User
}

enum Node<I> {
    case node(Element<I>)
    case withInput((I) -> Node<I>)
    case raw(String)
}

struct Element<I> {
    var name: String
    var children: [Node<I>]
    
    func render() -> String {
        return "<\(name)>\(children.map { $0.render() }.joined(separator: " "))</\(name)>"
    }
    
    func apply(_ input: I) -> Element<()> {
        return Element<()>(name: name, children: children.map { $0.apply(input) })
    }
}

extension Node {
    static func p(_ children: [Node]) -> Node {
        return .node(Element(name: "p", children: children))
    }
    
    func render() -> String {
        switch self {
        case let .node(e):
            return e.render()
        case let .raw(str):
            return str
        case .withInput:
            fatalError()
        }
    }
    
    func apply(_ input: I) -> Node<()> {
        switch self {
        case let .node(n):
            return .node(n.apply(input))
        case let .withInput(f):
            return f(input).apply(input)
        case let .raw(t):
            return .raw(t)
        }
    }
}

protocol Response: NIOWrapper.Response {
    static func write(html: Node<()>) -> Self
}

extension NIOInterpreter: Response {
    static func write(html: Node<()>) -> NIOInterpreter {
        return NIOInterpreter.write(html.render())
    }
}

struct Reader<Value, Result> {
    var run: (Value) -> Result
    
    init(_ run: @escaping (Value) -> Result) {
        self.run = run
    }
}

extension Reader: NIOWrapper.Response where Result: NIOWrapper.Response {
    static func write(_ string: String, status: HTTPResponseStatus, headers: [String : String]) -> Reader {
        return Reader { _ in .write(string, status: status, headers: headers) }
    }
}
extension Reader: Response where Result: Response {
    static func write(html: Node<()>) -> Reader {
        return Reader { _ in .write(html: html) }
    }
}

extension Reader where Result: Response {
    static func write(html: Node<Value>) -> Reader {
        return Reader { value in .write(html: html.apply(value)) }
    }
}


extension Node where I == Session {
    static func withSession(_ f: @escaping (Session) -> Node) -> Node {
        return Node.withInput { f($0) }
    }
}

func accountView() -> Node<Session> {
    return .withSession { session in
        .p([.raw("Your name: \(session.user.name)")])
    }
}

func interpret() -> Reader<Session, NIOInterpreter> {
    return .write(html: accountView())
}

let server = Server(resourcePaths: []) { request in
    let session  = Session(user: User(name: "Chris"))
    let reader = interpret()
    let x = reader.run(session)
    return x
}



try server.listen(port: 9999)
