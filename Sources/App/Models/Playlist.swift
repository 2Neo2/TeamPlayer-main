//
//  Playlist.swift
//  
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent
import Vapor

final class Playlist: Model, Content {
    static let schema = "playlists"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    
    @Field(key: "image_data")
    var imageData: String?
    
    @Parent(key: "creator_id")
    var creator: User
    
    init() { }
    
    init(id: UUID? = nil, name: String, imageData: String?, creatorID: UUID) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.$creator.id = creatorID
    }
}
