//
//  File.swift
//  
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent

struct CreateMusicRoom: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MusicRoom.schema)
            .id()
            .field("name", .string, .required)
            .field("creator_id", .uuid, .required, .references(User.schema, "id"))
            .field("invitation_code", .string, .required)
            .field("is_private", .bool, .required)
            .field("users_in_room", .int32, .required)
            .field("image_data", .string, .required)
            .field("description", .string, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(MusicRoom.schema).delete()
    }
}
