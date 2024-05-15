//
//  File.swift
//
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent
import Vapor

struct MusicRoomController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let musicRooms = routes.grouped("music-rooms")
        let protectedGameRooms = musicRooms.grouped(UserTokenAuthenticator())
        
        protectedGameRooms.post("create", use: create)
        protectedGameRooms.get("list-all", use: listAll)
        protectedGameRooms.post("join-room", use: joinGameRoom)
        protectedGameRooms.get("list-members", use: listMembersForGameRoom)
        protectedGameRooms.get("list-public", use: getPublicRooms)
        
        protectedGameRooms.delete("leave-room", use: leaveGameRoom)
        protectedGameRooms.delete("close-room", use: closeGameRoom)
        protectedGameRooms.delete("kick-participant", use: kickParticipant)
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
                                     imageData: musicRoom.imageData ?? "")
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
                            musicRoom.delete(on: db).map {
                                return Status(message: "ok")
                            }
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
                                  imageData: input.imageData ?? "")
        return musicRoom.save(on: req.db).flatMap {
            MusicRoom.query(on: req.db).filter(\.$id == musicRoom.id!).first().flatMapThrowing { fetchedMusicRoom in
                guard let fetchedMusicRoom = fetchedMusicRoom else {
                    throw Abort(.internalServerError)
                }
                let musicRoomUser = MusicRoomUser(userID: user.id!, musicRoomID: fetchedMusicRoom.id!)
                return musicRoomUser.save(on: req.db).map { fetchedMusicRoom }
            }.flatMap { $0 }
        }
    }
    
    func listAll(req: Request) throws -> EventLoopFuture<[MusicRoom.Public]> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return MusicRoom.query(on: req.db)
            .filter(\.$creator.$id == user.id!)
            .all().flatMapThrowing { musicRooms in
                musicRooms.map { musicRoom in
                    return MusicRoom.Public(id: musicRoom.id,
                                            name: musicRoom.name,
                                            creator: musicRoom.$creator.id,
                                            isPrivate: musicRoom.isPrivate,
                                            invitationCode: musicRoom.invitationCode,
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
                            invitationCode: musicRoom.invitationCode)
                    }
                }
            } else {
                return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Game room not found"))
            }
        }
    }
    
    func listMembersForGameRoom(req: Request) throws -> EventLoopFuture<[User.Public]> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let musicRoomId = try req.content.get(UUID.self, at: "musicRoomId")
        
        return MusicRoomUser.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$musicRoom.$id == musicRoomId)
            .first()
            .flatMapThrowing { musicRoomUser in
                if musicRoomUser == nil {
                    throw Abort(.forbidden, reason: "User is not in the game room")
                }
            }
            .flatMap { _ in
                MusicRoomUser.query(on: req.db)
                    .filter(\.$musicRoom.$id == musicRoomId)
                    .with(\.$user)
                    .all()
                    .flatMapThrowing { musicRoomUsers in
                        musicRoomUsers.map { musicRoomUser in
                            User.Public(id: musicRoomUser.user.id!, name: musicRoomUser.user.name)
                        }
                    }
            }
    }
    
    // MARK: Private
    // Private function that generate invitation code length of 5
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
        var imageData: String
    }
    
    struct Create: Content {
        var name: String
        var isPrivate: Bool
        var imageData: String?
    }
    
    struct Join: Content {
        var id: UUID
        var invitationCode: String?
    }
    
    struct Close: Content {
        var musicRoomId: UUID
    }
    
    struct JoinResponse: Content {
        var id: UUID?
        var name: String
        var creator: String
        var isPrivate: Bool
        var invitationCode: String?
    }
}
