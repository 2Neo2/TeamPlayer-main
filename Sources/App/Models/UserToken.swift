//
//  UserToken.swift
//  
//
//  Created by Иван Доронин on 07.05.2024.
//

import Fluent
import Vapor

final class UserToken: Model, Content {
    static let schema = "user_tokens"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "value")
    var value: String
    
    init() { }
    
    init(id: UUID? = nil, userID: UUID, value: String) {
        self.id = id
        self.$user.id = userID
        self.value = value
    }
}
