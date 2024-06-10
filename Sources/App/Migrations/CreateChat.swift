//
//  File.swift
//  
//
//  Created by Иван Доронин on 27.05.2024.
//

import Fluent

struct CreateChats: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Chat.schema)
            .id()
            .field("message", .string, .required)
            .field("creator_id", .uuid, .required, .references(User.schema, "id"))
            .field("music_room_id", .uuid, .required, .references(MusicRoom.schema, "id"))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(Chat.schema).delete()
    }
}
