//
//  MusicRoom.swift
//
//
//  Created by Иван Доронин on 10.04.2024.
//

import Fluent
import Vapor

final class MusicRoom: Model, Content {
    static let schema = "music_rooms"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    
    @Field(key: "invitation_code")
    var invitationCode: String
    
    @Field(key: "is_private")
    var isPrivate: Bool
    
    @Parent(key: "creator_id")
    var creator: User
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "users_in_room")
    var usersInRoom: Int
    
    @Field(key: "image_data")
    var imageData: String?
    
    init() { }
    
    init(id: UUID? = nil,
         name: String,
         creatorID: UUID,
         code: String,
         isPrivate: Bool,
         usersInRoom: Int,
         imageData: String,
         description: String) {
        self.id = id
        self.name = name
        self.$creator.id = creatorID
        self.invitationCode = code
        self.isPrivate = isPrivate
        self.usersInRoom = usersInRoom
        self.imageData = imageData
        self.description = description
    }
}
