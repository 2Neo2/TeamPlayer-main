//
//  CreateTrack.swift
//  
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent

struct CreateTrack: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Track.schema)
            .id()
            .field("track_id", .string, .required)
            .field("title", .string, .required)
            .field("artist", .string, .required)
            .field("img_link", .string, .required)
            .field("music_link", .string, .required)
            .unique(on: "track_id")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(Track.schema).delete()
    }
}

struct CreateTrackPlaylist: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(TrackPlaylist.schema)
            .id()
            .field("track_id", .uuid, .required, .references(Track.schema, "id"))
            .field("playlist_id", .uuid, .required, .references(Playlist.schema, "id"))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(TrackPlaylist.schema).delete()
    }
}
