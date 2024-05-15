import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("name", .string, .required)
            .field("email", .string, .required)
            .unique(on: "email")
            .field("plan", .string, .required)
            .field("password_hash", .string, .required)
            .field("image_data", .string, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(User.schema).delete()
    }
}

struct CreateUserToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserToken.schema)
            .id()
            .field("user_id", .uuid, .required,
                   .references(User.schema, "id"))
            .unique(on: "user_id")
            .field("value", .string, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(UserToken.schema).delete()
    }
}
