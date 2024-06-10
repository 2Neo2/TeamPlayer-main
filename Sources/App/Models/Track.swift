//
//  Track.swift
//
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent
import Vapor

final class Track: Model, Content {
    static let schema = "tracks"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "track_id")
    var trackID: String
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "artist")
    var artist: String
    
    @Field(key: "img_link")
    var imgLink: String
    
    @Field(key: "music_link")
    var musicLink: String
    
    @Field(key: "duration")
    var duration: Int
    
    init() { }
    
    init(id: UUID? = nil,
         trackID: String,
         title: String,
         artist: String,
         imgLink: String,
         musicLink: String,
         duration: Int) {
        self.id = id
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.imgLink = imgLink
        self.musicLink = musicLink
        self.duration = duration
    }
}
