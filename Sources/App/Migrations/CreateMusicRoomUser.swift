//
//  File.swift
//  
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent

struct CreateMusicRoomUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MusicRoomUser.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id"))
            .field("music_room_id", .uuid, .required, .references(MusicRoom.schema, "id"))
            .unique(on: "user_id")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(MusicRoomUser.schema).delete()
    }
}
