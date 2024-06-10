//
//  File.swift
//
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent
import Vapor

final class MusicRoomController: RouteCollection {
    private var connections = Set<WebSocket>()
    
    func boot(routes: RoutesBuilder) throws {
        let musicRooms = routes.grouped("music-rooms")
        let protectedGameRooms = musicRooms.grouped(UserTokenAuthenticator())
        
        protectedGameRooms.post("create", use: create)
        protectedGameRooms.get("list-all", use: listAll)
        protectedGameRooms.post("join-room", use: joinGameRoom)
        protectedGameRooms.post("join-room-code", use: joinGameCodeRoom)
        protectedGameRooms.post("list-members", use: listMembersForGameRoom)
        protectedGameRooms.get("list-public", use: getPublicRooms)
        
        protectedGameRooms.delete("leave-room", use: leaveGameRoom)
        protectedGameRooms.delete("close-room", use: closeGameRoom)
        protectedGameRooms.delete("kick-participant", use: kickParticipant)
        protectedGameRooms.get("rating", use: listAllSortedByUserCount)
        protectedGameRooms.post("search", use: searchByName)
        protectedGameRooms.post("set-dj", use: setDJRoom)
        protectedGameRooms.webSocket("stream", onUpgrade: streamMusic)
        protectedGameRooms.post("playlist-id", use: getPlaylistMusicId)
    }
    
    func getPlaylistMusicId(req: Request) throws -> EventLoopFuture<MusicRoom.PlaylistID> {
        req.headers.contentType = .json
        
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.PlaylistID.self)
        
        return MusicRoomPlaylist.query(on: req.db)
            .filter(\.$musicRoom.$id == input.playlistID)
            .first()
            .flatMapThrowing { playlist in
                guard let playlist = playlist else {
                    throw Abort(.notFound, reason: "Music room not found for musicRoomId \(input.playlistID)")
                }
                return MusicRoom.PlaylistID(playlistID: playlist.$playlist.id)
            }
    }

    
    func streamMusic(req: Request, socket: WebSocket) {
        socket.pingInterval = .seconds(10)
        self.connections.insert(socket)
        
        socket.onText { [weak self] socket, text in
            guard let self = self else { return }
            connections.insert(socket)
            if let trackNumber = Int(text) {
                self.streamTrack(trackNumber, socket: socket)
            } else {
                if text == "play" || text == "pause" || text == "next" || text == "back" {
                    connections.forEach {
                        $0.send(text)
                    }
                } else {
                    socket.send("Invalid track number")
                }
            }
        }
        
        socket.onClose.whenComplete { [weak self] _ in
            guard let self = self else { return }
            self.connections.remove(socket)
            print("WebSocket closed")
        }
    }

    private func streamTrack(_ trackNumber: Int, socket: WebSocket) {
        let directory = "/Users/ivandoronin/Desktop/TeamPlayer-main/Sources/App/Music/"
        let fileName = "\(trackNumber).mp3"
        let filePath = directory + fileName
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            socket.send("Track not found")
            return
        }
        
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            socket.send("Unable to open file")
            return
        }
        
        defer {
            try? fileHandle.close()
        }
        
        let chunkSize = 1024 * 4
        var isStreaming = true
        
        let closeHandler = { [weak self] in
            guard let self = self else { return }
            isStreaming = false
            connections.forEach {
                $0.send(Data())
            }
            
            connections = Set<WebSocket>()
            try? fileHandle.close()
        }
        
        socket.onClose.whenComplete { _ in closeHandler() }
        
        while isStreaming {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.count > 0 {
                connections.forEach {
                    $0.send(data)
                }
            } else {
                closeHandler()
            }
        }
    }
    
    func kickParticipant(req: Request) throws -> EventLoopFuture<Status> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.KickParticipant.self)
        
        return MusicRoom.query(on: req.db)
            .filter(\.$id == input.roomId)
            .filter(\.$creator.$id == user.id!)
            .first()
            .flatMap { musicRoom in
                guard let musicRoom = musicRoom else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "Only the game room admin can kick participants"))
                }
                
                return MusicRoomUser.query(on: req.db)
                    .filter(\.$user.$id == input.userIdToKick)
                    .filter(\.$musicRoom.$id == musicRoom.id!)
                    .delete()
                    .map {
                        return Status(message: "ок")
                    }
            }
    }
    
    func searchByName(req: Request) throws -> EventLoopFuture<[MusicRoom]> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.MusicRoomName.self)
        
        return MusicRoom.query(on: req.db)
            .filter(\.$name ~~ input.name)
            .all()
    }
    
    func getPublicRooms(req: Request) throws -> EventLoopFuture<[MusicRoom.Public]> {
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return MusicRoom.query(on: req.db)
            .filter(\.$isPrivate == false)
            .all()
            .flatMapThrowing { musicRooms in
                musicRooms.map { musicRoom in
                    MusicRoom.Public(id: musicRoom.id,
                                     name: musicRoom.name,
                                     creator: musicRoom.$creator.id,
                                     isPrivate: musicRoom.isPrivate,
                                     invitationCode: musicRoom.invitationCode,
                                     description: musicRoom.description,
                                     imageData: musicRoom.imageData ?? "")
                }
            }
    }
    
    func setDJRoom(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.MusicRoomDJ.self)
        
        return req.db.transaction { db in
            MusicRoom.find(input.musicRoomId, on: db)
                .flatMap { foundMusicRoom -> EventLoopFuture<Status> in
                    guard let musicRoom = foundMusicRoom else {
                        return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Music room not found"))
                    }
                    
                    guard musicRoom.$creator.id == user.id else {
                        return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "Only the current DJ can change the DJ"))
                    }
                    
                    return User.find(input.userId, on: db).flatMap { newDJ in
                        guard let newDJ = newDJ else {
                            return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "New DJ not found"))
                        }
                    
                        musicRoom.$creator.id = newDJ.id!
                        
                        return musicRoom.save(on: db).flatMap {
                            return MusicRoomPlaylist.query(on: db)
                                .filter(\.$musicRoom.$id == musicRoom.id!)
                                .first()
                                .flatMap { musicRoomPlaylist in
                                    guard let musicRoomPlaylist = musicRoomPlaylist else {
                                        return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "Playlist for music room not found"))
                                    }
                                    
                                    return Playlist.find(musicRoomPlaylist.$playlist.id, on: db).flatMap { playlist in
                                        guard let playlist = playlist else {
                                            return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "Playlist not found"))
                                        }
                                        
                                        playlist.$creator.id = newDJ.id!
                                        
                                        return playlist.save(on: db).flatMap {
                                            return MusicRoomUser.query(on: db)
                                                .filter(\.$musicRoom.$id == musicRoom.id!)
                                                .filter(\.$user.$id == user.id!)
                                                .first()
                                                .flatMap { musicRoomUser in
                                                    guard let musicRoomUser = musicRoomUser else {
                                                        return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "MusicRoomUser not found"))
                                                    }
                                                    
                                                    musicRoomUser.$user.id = newDJ.id!
                                                    
                                                    return musicRoomUser.save(on: db).map {
                                                        Status(message: "DJ changed successfully")
                                                    }
                                                }
                                        }
                                    }
                                }
                        }
                    }
                }
        }
    }

    
    func leaveGameRoom(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let musicRoomId = try req.content.decode(MusicRoom.Close.self)
        return MusicRoom.find(musicRoomId.musicRoomId, on: req.db)
            .flatMap { foundMusicRoom in
                if let musicRoom = foundMusicRoom {
                    return MusicRoomUser.query(on: req.db)
                        .filter(\.$musicRoom.$id == musicRoom.id!)
                        .filter(\.$user.$id == user.id!)
                        .delete()
                        .map {
                            Status(message: "ok")
                        }
                } else {
                    return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Game room not found"))
                }
            }
    }
    
    func closeGameRoom(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.Close.self)
        
        return req.db.transaction { db in
            MusicRoom.find(input.musicRoomId, on: db)
                .flatMap { foundMusicRoom in
                    guard let musicRoom = foundMusicRoom else {
                        return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Game room not found"))
                    }
                    
                    guard musicRoom.$creator.id == user.id else {
                        return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "Only the game room admin can close the game room"))
                    }
                    
                    return MusicRoomUser.query(on: db)
                        .filter(\.$musicRoom.$id == musicRoom.id!)
                        .delete()
                        .flatMap {
                            return MusicRoomPlaylist.query(on: db)
                                .filter(\.$musicRoom.$id == musicRoom.id!)
                                .first()
                                .flatMap { musicRoomPlaylist in
                                    
                                    let playlistID = musicRoomPlaylist!.$playlist.id
                                    
                                    return musicRoomPlaylist!.delete(on: db).flatMap {
                                        return TrackPlaylist.query(on: db)
                                            .filter(\.$playlist.$id == playlistID)
                                            .delete()
                                            .flatMap {
                                                Playlist.find(playlistID, on: db)
                                                    .flatMap { playlist in
                                                        guard let playlist = playlist else {
                                                            return req.eventLoop.makeSucceededFuture(())
                                                        }
                                                        return playlist.delete(on: db)
                                                    }
                                            }
                                    }
                                }
                        }
                        .flatMap {
                            musicRoom.delete(on: db).map { Status(message: "ok") }
                        }
                }
        }
    }

    
    func create(req: Request) throws -> EventLoopFuture<MusicRoom> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }

        let input = try req.content.decode(MusicRoom.Create.self)
        var countUsers = 0

        switch user.plan {
        case "basic":
            countUsers = 5
        case "standart":
            countUsers = 15
        case "premium":
            countUsers = 100
        default:
            countUsers = 100
        }

        let musicRoom = MusicRoom(name: input.name,
                                  creatorID: user.id!,
                                  code: generateInvitationCode(),
                                  isPrivate: input.isPrivate,
                                  usersInRoom: countUsers,
                                  imageData: input.imageData ?? "",
                                  description: input.description)
        return musicRoom.save(on: req.db).flatMap {
            MusicRoom.query(on: req.db).filter(\.$id == musicRoom.id!)
                .first()
                .unwrap(or: Abort(.internalServerError))
                .flatMap { fetchedMusicRoom in
                    let musicRoomUser = MusicRoomUser(userID: user.id!, musicRoomID: fetchedMusicRoom.id!)
                    return musicRoomUser.save(on: req.db).flatMap {
                        let playlist = Playlist(name: "\(input.name)Playlist", imageData: "", creatorID: user.id!, description: input.description)
                        return playlist.save(on: req.db).flatMap {
                            Playlist.query(on: req.db).filter(\.$id == playlist.id!)
                                .first()
                                .unwrap(or: Abort(.internalServerError))
                                .flatMap { fetchedPlaylist in
                                    let musicRoomPlaylist = MusicRoomPlaylist(musicRoomID: fetchedMusicRoom.id!, playlistID: fetchedPlaylist.id!)
                                    return musicRoomPlaylist.save(on: req.db).map { fetchedMusicRoom }
                                }
                        }
                    }
                }
        }
    }

    
    func listAll(req: Request) throws -> EventLoopFuture<[MusicRoom.Public]> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return MusicRoomUser.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .all()
            .flatMap { musicRoomUsers in
                let musicRoomIds = musicRoomUsers.map { $0.$musicRoom.id }
                
                return MusicRoom.query(on: req.db)
                    .filter(\.$id ~~ musicRoomIds)
                    .all()
            }
            .flatMapThrowing { joinedRooms in
                var uniqueRoomsDict = [UUID: MusicRoom]()
                
                joinedRooms.forEach { room in
                    uniqueRoomsDict[room.id!] = room
                }
                
                let uniqueRooms = Array(uniqueRoomsDict.values)
                return uniqueRooms.map { musicRoom in
                    return MusicRoom.Public(id: musicRoom.id!,
                                            name: musicRoom.name,
                                            creator: musicRoom.$creator.id,
                                            isPrivate: musicRoom.isPrivate,
                                            invitationCode: musicRoom.invitationCode,
                                            description: musicRoom.description,
                                            imageData: musicRoom.imageData ?? "")
                }
            }
    }
    
    func joinGameRoom(req: Request) throws -> EventLoopFuture<MusicRoom.JoinResponse> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.Join.self)
        
        let musicRoomQuery = MusicRoom.query(on: req.db)
            .filter(\.$id == input.id)
        
        return musicRoomQuery.first().flatMap { foundMusicRoom in
            if let musicRoom = foundMusicRoom {
                let existingUserQuery = MusicRoomUser.query(on: req.db)
                    .filter(\.$user.$id == user.id!)
                    .filter(\.$musicRoom.$id == musicRoom.id!)
                
                return existingUserQuery.first().flatMap { existingUser in
                    if existingUser != nil {
                        return User.find(musicRoom.$creator.id, on: req.db).map { creator in
                            MusicRoom.JoinResponse(
                                id: musicRoom.id,
                                name: musicRoom.name,
                                creator: creator?.$name.value ?? "default value",
                                isPrivate: musicRoom.isPrivate,
                                invitationCode: musicRoom.invitationCode,
                                description: musicRoom.description
                            )
                        }
                    } else {
                        if musicRoom.isPrivate && musicRoom.invitationCode != input.invitationCode {
                            return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "Invalid invitation code for private game room"))
                        }
                        
                        let musicRoomUser = MusicRoomUser(userID: user.id!, musicRoomID: musicRoom.id!)
                        return musicRoomUser.save(on: req.db).flatMap { _ in
                            return User.find(musicRoom.$creator.id, on: req.db).map { creator in
                                MusicRoom.JoinResponse(
                                    id: musicRoom.id,
                                    name: musicRoom.name,
                                    creator: creator?.$name.value ?? "default value",
                                    isPrivate: musicRoom.isPrivate,
                                    invitationCode: musicRoom.invitationCode,
                                    description: musicRoom.description
                                )
                            }
                        }
                    }
                }
            } else {
                return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Game room not found"))
            }
        }
        
        //        func addTrackToPlaylist(req: Request) throws -> EventLoopFuture<Status> {
        //
        //        }
    }
    
    func joinGameCodeRoom(req: Request) throws -> EventLoopFuture<MusicRoom.JoinResponse> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(MusicRoom.JoinCode.self)
        
        let musicRoomQuery = MusicRoom.query(on: req.db)
            .filter(\.$invitationCode == input.invitationCode)
        
        return musicRoomQuery.first().flatMap { foundMusicRoom in
            if let musicRoom = foundMusicRoom {
                let existingUserQuery = MusicRoomUser.query(on: req.db)
                    .filter(\.$user.$id == user.id!)
                    .filter(\.$musicRoom.$id == musicRoom.id!)
                
                return existingUserQuery.first().flatMap { existingUser in
                    if existingUser != nil {
                        return User.find(musicRoom.$creator.id, on: req.db).map { creator in
                            MusicRoom.JoinResponse(
                                id: musicRoom.id,
                                name: musicRoom.name,
                                creator: creator?.$name.value ?? "default value",
                                isPrivate: musicRoom.isPrivate,
                                invitationCode: musicRoom.invitationCode,
                                description: musicRoom.description
                            )
                        }
                    } else {
                        let musicRoomUser = MusicRoomUser(userID: user.id!, musicRoomID: musicRoom.id!)
                        return musicRoomUser.save(on: req.db).flatMap { _ in
                            return User.find(musicRoom.$creator.id, on: req.db).map { creator in
                                MusicRoom.JoinResponse(
                                    id: musicRoom.id,
                                    name: musicRoom.name,
                                    creator: creator?.$name.value ?? "default value",
                                    isPrivate: musicRoom.isPrivate,
                                    invitationCode: musicRoom.invitationCode,
                                    description: musicRoom.description
                                )
                            }
                        }
                    }
                }
            } else {
                return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Game room not found"))
            }
        }
    }
    
    func listMembersForGameRoom(req: Request) throws -> EventLoopFuture<[User.Public]> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let musicRoomId = try req.content.decode(MusicRoom.Close.self)
        
        return MusicRoomUser.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$musicRoom.$id == musicRoomId.musicRoomId)
            .first()
            .flatMapThrowing { musicRoomUser in
                if musicRoomUser == nil {
                    throw Abort(.forbidden, reason: "User is not in the game room")
                }
            }
            .flatMap { _ in
                MusicRoomUser.query(on: req.db)
                    .filter(\.$musicRoom.$id == musicRoomId.musicRoomId)
                    .with(\.$user)
                    .all()
                    .flatMapThrowing { musicRoomUsers in
                        musicRoomUsers.map { musicRoomUser in
                            User.Public(id: musicRoomUser.user.id!, name: musicRoomUser.user.name)
                        }
                    }
            }
    }
    
    func listAllSortedByUserCount(req: Request) throws -> EventLoopFuture<[MusicRoom.RatingModel]> {
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return MusicRoomUser.query(on: req.db)
            .all()
            .flatMap { musicRoomUsers in
                var roomUserCounts = [UUID: Int]()
                
                for musicRoomUser in musicRoomUsers {
                    roomUserCounts[musicRoomUser.$musicRoom.id, default: 0] += 1
                }
                
                let uniqueRoomIds = Array(roomUserCounts.keys)
                
                return MusicRoom.query(on: req.db)
                    .filter(\.$id ~~ uniqueRoomIds)
                    .all()
                    .map { rooms in
                        
                        let sortedRooms = rooms.sorted { roomUserCounts[$0.id!]! > roomUserCounts[$1.id!]! }
                        
                        return sortedRooms.prefix(10).map { musicRoom in
                            MusicRoom.RatingModel(
                                id: musicRoom.id,
                                name: musicRoom.name,
                                creator: musicRoom.$creator.id,
                                isPrivate: musicRoom.isPrivate,
                                invitationCode: musicRoom.invitationCode,
                                imageData: musicRoom.imageData ?? "",
                                countOfPeople: roomUserCounts[musicRoom.id!]!
                            )
                        }
                    }
            }
    }
    
    private func generateInvitationCode() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<5).map{ _ in letters.randomElement()! })
    }
}

extension MusicRoom {
    struct KickParticipant: Content {
        var roomId: UUID
        var userIdToKick: UUID
    }
    
    struct Public: Content {
        var id: UUID?
        var name: String
        var creator: UUID
        var isPrivate: Bool
        var invitationCode: String?
        var description: String
        var imageData: String
    }
    
    struct Create: Content {
        var name: String
        var isPrivate: Bool
        var imageData: String?
        var description: String
    }
    
    struct Join: Content {
        var id: UUID
        var invitationCode: String?
    }
    
    struct JoinCode: Content {
        var invitationCode: String
    }
    
    struct Close: Content {
        var musicRoomId: UUID
    }
    
    struct PlaylistID: Content {
        var playlistID: UUID
    }
    
    struct JoinResponse: Content {
        var id: UUID?
        var name: String
        var creator: String
        var isPrivate: Bool
        var invitationCode: String?
        var description: String
    }
    
    struct RatingModel: Content {
        var id: UUID?
        var name: String
        var creator: UUID
        var isPrivate: Bool
        var invitationCode: String?
        var imageData: String
        var countOfPeople: Int
    }
    
    struct MusicRoomDJ: Content {
        var musicRoomId: UUID
        var userId: UUID
    }
    
    struct MusicRoomName: Content {
        var name: String
    }
}
