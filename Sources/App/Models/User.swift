import Fluent
import Vapor
import Crypto

final class User: Model, Content, Authenticatable {
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    
    @Field(key: "email")
    var email: String
    
    @Field(key: "plan")
    var plan: String
    
    @Field(key: "password_hash")
    var passwordHash: String
    
    @Field(key: "image_data")
    var imageData: String?
    
    init() { }
    
    init(id: UUID? = nil, name: String, email: String, plan: String, passwordHash: String, imageData: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.plan = plan
        self.passwordHash = passwordHash
        self.imageData = imageData
    }
    
    struct Create: Content {
        var name: String
        var email: String
        var plan: String
        var password: String
    }
    
    struct Login: Content {
        var email: String
        var password: String
    }
    
    struct Update: Content {
        var id: UUID
        var name: String?
        var email: String?
        var imageData: String?
        var plan: String?
        var password: String?
        var old: String
    }
    
    struct Public: Content {
        var id: UUID
        var name: String
        var imageData: String?
    }
    
    struct UserID: Content {
        var id: UUID
    }
}

extension User.Create: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}

extension User.Login: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}
