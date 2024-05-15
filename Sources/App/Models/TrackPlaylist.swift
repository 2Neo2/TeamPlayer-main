//
//  File.swift
//  
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent
import Vapor

final class TrackPlaylist: Model, Content {
    static let schema = "tracks_playlists"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "track_id")
    var track: Track
    
    @Parent(key: "playlist_id")
    var playlist: Playlist
    
    init() { }
    
    init(id: UUID? = nil, trackID: UUID, playlistID: UUID) {
        self.id = id
        self.$track.id = trackID
        self.$playlist.id = playlistID
    }
}


