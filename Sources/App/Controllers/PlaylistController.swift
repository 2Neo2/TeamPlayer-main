//
//  File.swift
//
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent
import Vapor

struct PlaylistController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let playlists = routes.grouped("playlists")
        let protectedPlaylists = playlists.grouped(UserTokenAuthenticator())
        
        protectedPlaylists.post("create", use: create)
        protectedPlaylists.post("storage", use: addTrackToStorage)
        protectedPlaylists.get("list-all", use: listAll)
        protectedPlaylists.post("tracks", use: getTracks)
        protectedPlaylists.post("add-track", use: addTrackToPlaylist)
        protectedPlaylists.delete("remove-track", use: removeTrackFromPlaylist)
        protectedPlaylists.delete("remove-playlist", use: removePlaylist)
    }
    
    func addTrackToStorage(req: Request) throws -> EventLoopFuture<Track> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Track.self)
        
        let track = Track(
            trackID: input.trackID,
            title: input.title,
            artist: input.artist,
            imgLink: input.imgLink,
            musicLink: input.musicLink
        )
        return track.save(on: req.db).map { track }
    }
    
    func addTrackToPlaylist(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Track.TrackToPlaylist.self)
        
        let media = TrackPlaylist(trackID: input.trackID, playlistID: input.playlistID)
        
        return media.save(on: req.db).transform(to: Status(message: "ok"))
    }
    
    func removeTrackFromPlaylist(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Track.TrackToPlaylist.self)
        
        return TrackPlaylist.query(on: req.db)
            .filter(\.$track.$id == input.trackID)
            .filter(\.$playlist.$id == input.playlistID)
            .delete()
            .map {
                Status(message: "ok")
            }
    }
    
    func getTracks(req: Request) throws -> EventLoopFuture<[Track]> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Playlist.PlaylistID.self)
        
        return TrackPlaylist.query(on: req.db)
            .filter(\.$playlist.$id == input.id)
            .all()
            .flatMap { trackPlaylists in
                let trackIDs = trackPlaylists.map { $0.$track.id }
                return Track.query(on: req.db)
                    .filter(\.$id ~~ trackIDs)
                    .all()
            }
    }
    
    func create(req: Request) throws -> EventLoopFuture<Status> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Playlist.Create.self)
        
        let playlist = Playlist(name: input.name, imageData: input.imageData, creatorID: user.id!)
        return playlist.save(on: req.db).map { Status(message: "ok") }
    }
    
    func listAll(req: Request) throws -> EventLoopFuture<[Playlist.Public]> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return Playlist.query(on: req.db)
            .filter(\.$creator.$id == user.id!)
            .all()
            .flatMapThrowing { playlists in
                playlists.map { playlist in
                    return Playlist.Public(
                        id: playlist.id,
                        name: playlist.name,
                        imageData: playlist.imageData ?? "",
                        creatorID: playlist.$creator.id
                    )
                }
            }
    }
    
    func removePlaylist(req: Request) throws -> EventLoopFuture<Status> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Playlist.PlaylistID.self)
        
        return TrackPlaylist.query(on: req.db)
            .filter(\.$playlist.$id == input.id)
            .delete()
            .flatMap {
                Playlist.find(input.id, on: req.db)
                    .flatMap { playlist in
                        guard let playlist = playlist else {
                            return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "Playlist not found"))
                        }
                        return playlist.delete(on: req.db).map {
                            return Status(message: "ok")
                        }
                    }
            }
    }
}

extension Playlist {
    struct Public: Content {
        var id: UUID?
        var name: String
        var imageData: String
        var creatorID: UUID
    }
    
    struct Create: Content {
        var name: String
        var imageData: String
    }
    
    struct PlaylistID: Content {
        var id: UUID
    }
}


extension Track {
    struct TrackToPlaylist: Content {
        var trackID: UUID
        var playlistID: UUID
    }
}
