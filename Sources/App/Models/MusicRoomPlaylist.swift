//
//  File.swift
//  
//
//  Created by Иван Доронин on 22.05.2024.
//

import Fluent
import Vapor


final class MusicRoomPlaylist: Model, Content {
    static let schema = "music_room_playlists"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "music_room_id")
    var musicRoom: MusicRoom
    
    @Parent(key: "playlist_id")
    var playlist: Playlist
    
    init() { }
    
    init(id: UUID? = nil, musicRoomID: UUID, playlistID: UUID) {
        self.id = id
        self.$musicRoom.id = musicRoomID
        self.$playlist.id = playlistID
    }
}
