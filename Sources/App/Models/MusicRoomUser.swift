//
//  MusicRoomUser.swift
//  
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent
import Vapor

final class MusicRoomUser: Model, Content {
    static let schema = "music_room_users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Parent(key: "music_room_id")
    var musicRoom: MusicRoom
    
    init() { }
    
    init(id: UUID? = nil, userID: UUID, musicRoomID: UUID) {
        self.id = id
        self.$user.id = userID
        self.$musicRoom.id = musicRoomID
    }
}
