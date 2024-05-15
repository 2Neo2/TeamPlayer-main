import Fluent
import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: UsersController())
    try app.register(collection: MusicRoomController())
    try app.register(collection: PlaylistController())
    app.routes.defaultMaxBodySize = "20mb"
}
