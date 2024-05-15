//
//  CreatePlaylist.swift
//  
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent

struct CreatePlaylist: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Playlist.schema)
            .id()
            .field("name", .string, .required)
            .field("image_data", .string, .required)
            .field("creator_id", .uuid, .required, .references(User.schema, "id"))
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(Playlist.schema).delete()
    }
}

