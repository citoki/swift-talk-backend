//
//  Model.swift
//  Bits
//
//  Created by Chris Eidhof on 06.08.18.
//

import Foundation
import CommonMark


struct Session {
    var sessionId: UUID
    var user: Row<UserData>
    var csrfToken: String = "TODO" // todo
}

let teamDiscount = 30

struct Id<A>: RawRepresentable, Codable, Equatable {
    var rawValue: String
}

struct Guest: Codable, Equatable {
    var name: String
    // todo
}

struct Collaborator: Codable, Equatable {
    var id: Id<Collaborator>
    var name: String
    var url: URL
    var role: Role
}

enum Role: String, Codable, Equatable, Comparable {
    case host = "host"
    case guestHost = "guest-host"
    case transcript = "transcript"
    case copyEditing = "copy-editing"
    case technicalReview = "technical-review"
    case shooting = "shooting"

    static private let order: [Role] = [.host, .guestHost, .technicalReview, .transcript, .copyEditing, .shooting]

    static func <(lhs: Role, rhs: Role) -> Bool {
        return Role.order.index(of: lhs)! < Role.order.index(of: rhs)!
    }

    
    var name: String {
        switch self {
        case .host:
            return "Host"
        case .guestHost:
            return "Guest Host"
        case .transcript:
            return "Transcript"
        case .copyEditing:
            return "Copy Editing"
        case .technicalReview:
            return "Technical Review"
        case .shooting:
            return "Shooting"
        }
    }
}

struct Episode: Codable, Equatable {
    var collections: [Id<Collection>]
    var collaborators: [Id<Collaborator>]
    var media_duration: TimeInterval?
    var media_src: String?
    var number: Int
    var poster_uid: String?
    var release_at: String?
    var released: Bool
    var sample_src: String?
    var sample_duration: TimeInterval?
//    var small_poster_url: URL?
    var subscription_only: Bool
    var synopsis: String
    var title: String
    var video_id: String?
//    var guests: [Guest]?
    var resources: PostgresArray<Resource>
}

struct PostgresArray<A>: Codable, Equatable where A: Codable, A: Equatable {
    var values: [A]
    
    init(from decoder: Decoder) throws {
        do {
            values = try .init(from: decoder)
        } catch {
        	values = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }
}

struct Resource: Codable, Equatable {
    var title: String
    var subtitle: String
    var url: URL
}

extension Episode {
    var id: Id<Episode> {
        return Id(rawValue: "S01E\(number)-\(title.asSlug)")
    }
    
    var fullTitle: String {
        guard let p = primaryCollection, p.use_as_title_prefix else { return title }
        return "\(p.title): \(title)"
    }
    var releasedAt: Date? {
        let formatter = DateFormatter.iso8601
        return release_at.flatMap { formatter.date(from: $0) }
    }
    
    var poster_url: URL? {
        // todo
        return URL(string: "https://d2sazdeahkz1yk.cloudfront.net/assets/media/W1siZiIsIjIwMTgvMDYvMTQvMTAvMDEvNDEvYjQ1Njc3YWQtNDRlMS00N2E1LWI5NDYtYWFhOTZiOTYxOWM4LzExMSBEZWJ1Z2dlciAzLmpwZyJdLFsicCIsInRodW1iIiwiNTkweDI3MCMiXV0?sha=bb0917beee87a929")
    }
    
    var media_url: URL? {
        return URL(string: "https://d2sazdeahkz1yk.cloudfront.net/videos/5dbf3160-fb5b-4e5a-88da-3163ea09883b/1/hls.m3u8")
    }
    
    var theCollections: [Collection] {
        return collections.compactMap { cid in
            Collection.all.first { $0.id ==  cid }
        }
    }
    
    var theCollaborators: [Collaborator] {
        return collaborators.compactMap { cid in
            Collaborator.all.first { $0.id == cid }
        }
    }
    
    var primaryCollection: Collection? {
        return theCollections.first
    }
    
    func title(in coll: Collection) -> String {
        guard let p = primaryCollection, p != coll else { return title }
        return p.title + ": " + title
    }
    
    static func scoped(for user: UserData?) -> [Episode] {
        guard let u = user, u.admin || u.collaborator else { return all.filter { $0.released } }
        return Episode.all
    }
    
    var transcript: CommonMark.Node? {
        return Transcript.forEpisode(number: number)?.contents
    }
    
    var tableOfContents: [(TimeInterval, title: String)] {
        return Transcript.forEpisode(number: number)?.tableOfContents ?? []
    }

    func canWatch(session: Session?) -> Bool {
        return session.premiumAccess || !subscription_only
    }
}

struct Collection: Codable, Equatable {
    var id: Id<Collection>
    var title: String
    var `public`: Bool
    var description: String
    var position: Int
    var new: Bool
    var use_as_title_prefix: Bool
}

extension Collection {
    var artwork: String {
        return "/assets/images/collections/\(title).svg"
    }
    
    func episodes(for user: UserData?) -> [Episode] {
        return Episode.scoped(for: user).filter { $0.collections.contains(id) }
    }    
}

extension Sequence where Element == Episode {
    var totalDuration: TimeInterval {
        return lazy.map { $0.media_duration ?? 0 }.reduce(0, +)
    }
}

extension String {
    func scanTimePrefix() -> (minutes: Int, seconds: Int, remainder: String)? {
        let s = Scanner(string: self)
        var minutes: Int = 0
        var seconds: Int = 0
        if s.scanInt(&minutes), s.scanString(":", into: nil), s.scanInt(&seconds) {
            return (minutes, seconds, s.remainder)
        } else {
            return nil
        }
    }
}


struct Transcript {
    var number: Int
    var contents: CommonMark.Node
    var tableOfContents: [(TimeInterval, title: String)]
    
    init?(fileName: String, raw: String) {
        guard let number = Int(fileName.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) else { return nil }
        self.number = number
        
        // Add timestamp links
        guard let nodes = CommonMark.Node(markdown: raw) else { return nil }
        self.contents = CommonMark.Node(blocks: nodes.elements.deepApply({ (inl: Inline) -> [Inline] in
            guard case let .text(t) = inl else { return [inl] }
            if let (m, s, remainder) = t.scanTimePrefix() {
                let totalSeconds = m * 60 + s
                let pretty = "\(m.padded):\(s.padded)"
                return [Inline.link(children: [.text(text: pretty)], title: "", url: "#\(totalSeconds)"), .text(text: remainder)]
            } else {
                return [inl]
            }
        }))
        
        // Extract table of contents
        var result: [(TimeInterval, title: String)] = []
        var currentTitle: String?
        for el in self.contents.elements {
            switch el {
            case let .heading(text: text, _):
                let strs = text.deep(collect: { (i: Inline) -> [String] in
                    guard case let Inline.text(text: t) = i else { return [] }
                    return [t]
                })
                currentTitle = strs.joined(separator: " ")
            case let .paragraph(text: c) where currentTitle != nil:
                if case let .link(lc, _, _)? = c.first, case let .text(t)? = lc.first, let (minutes, seconds, _) = t.scanTimePrefix() {
                    result.append((TimeInterval(minutes*60 + seconds), title: currentTitle!))
                    currentTitle = nil
                }
            default:
                ()
            }
        }
        self.tableOfContents = result
    }
}

