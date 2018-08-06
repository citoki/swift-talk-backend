//
//  Model.swift
//  Bits
//
//  Created by Chris Eidhof on 06.08.18.
//

import Foundation

struct Id<A>: RawRepresentable, Codable, Equatable {
    var rawValue: String
}

struct Episode: Codable, Equatable {
    var collection: Id<Collection>?
    var created_at: Int
    var furthest_watched: Double?
    var id: Id<Episode>
    var media_duration: TimeInterval?
    var media_url: URL?
    var name: String?
    var number: Int
    var play_position: Double?
    var poster_url: URL?
    var released_at: TimeInterval?
    var sample: Bool
    var sample_duration: TimeInterval?
    var season: Int
    var small_poster_url: URL?
    var subscription_only: Bool
    var synopsis: String
    var title: String
    var updated_at: Int
}

extension Episode {
    var releasedAt: Date? {
        return released_at.map { Date(timeIntervalSince1970: $0) }
    }
}


struct Collection: Codable, Equatable {
    var id: Id<Collection>
    var artwork: String // todo this is a weird kind of URL we get from JSON
    var description: String
    var title: String
}