//
//  File.swift
//  
//
//  Created by Иван Доронин on 27.05.2024.
//

import Fluent
import Vapor

final class Chat: Model, Content {
    static let schema = "chats"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "message")
    var message: String
    
    @Parent(key: "creator_id")
    var creator: User
    
    @Parent(key: "music_room_id")
    var musicRoom: MusicRoom
    
    init() { }
    
    init(id: UUID? = nil,
         message: String,
         creatorID: UUID,
         musicRoomID: UUID) {
        self.id = id
        self.message = message
        self.$creator.id = creatorID
        self.$musicRoom.id = musicRoomID
    }
}
