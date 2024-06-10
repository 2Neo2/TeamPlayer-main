import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(.postgres(hostname: "localhost", username: "postgres", password: "postgres", database: "teamPlayerDb"), as: .psql)
    
    app.middleware.use(UserTokenAuthenticator())
    
    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserToken())
    app.migrations.add(CreateMusicRoom())
    app.migrations.add(CreateMusicRoomUser())
    app.migrations.add(CreatePlaylist())
    app.migrations.add(CreateTrack())
    app.migrations.add(CreateTrackPlaylist())
    app.migrations.add(CreateMusicRoomPlaylist())
    app.migrations.add(CreateChats())
    
    // register routes
    try routes(app)
}
