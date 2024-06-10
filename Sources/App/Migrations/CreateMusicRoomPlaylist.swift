//
//  File.swift
//  
//
//  Created by Иван Доронин on 25.05.2024.
//

import Fluent

struct CreateMusicRoomPlaylist: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MusicRoomPlaylist.schema)
            .id()
            .field("music_room_id", .uuid, .required, .references(MusicRoom.schema, "id"))
            .field("playlist_id", .uuid, .required, .references(Playlist.schema, "id"))
            .unique(on: "id")
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema(MusicRoomPlaylist.schema).delete()
    }
}
