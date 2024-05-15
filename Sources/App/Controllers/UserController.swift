import Foundation
import Fluent
import Vapor
import Crypto

struct UsersController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.post("register", use: register)
        users.post("login", use: login)
        users.post("userById", use: userById)
        
        let protectedUsers = users.grouped(UserTokenAuthenticator())
        protectedUsers.get("profile", use: getProfile)
        protectedUsers.post("logout", use: logout)
        protectedUsers.post("update", use: updateUserData)
    }
    
    func userById(req: Request) throws -> EventLoopFuture<User> {
        req.headers.contentType = .json
        let input = try req.content.decode(User.UserID.self)
        
        return User.find(input.id, on: req.db)
            .unwrap(or: Abort(.notFound))
    }
    
    func register(req: Request) throws -> EventLoopFuture<User> {
        req.headers.contentType = .json
        try User.Create.validate(content: req)
        let data = try req.content.decode(User.Create.self)
        
        let passwordHash = try Bcrypt.hash(data.password)
        let user = User(name: data.name, email: data.email, plan: data.plan, passwordHash: passwordHash, imageData: "")
        return user.save(on: req.db).map { user }
    }
    
    func login(req: Request) throws -> EventLoopFuture<UserToken> {
        req.headers.contentType = .json
        try User.Login.validate(content: req)
        let data = try req.content.decode(User.Login.self)
        
        return User.query(on: req.db)
            .filter(\.$email == data.email)
            .first()
            .flatMap { user in
                guard let user = user else {
                    return req.eventLoop.future(error: Abort(.unauthorized))
                }
                
                do {
                    if try Bcrypt.verify(data.password, created: user.passwordHash) {
                        let token = try self.generateToken()
                        let userToken = UserToken(userID: user.id!, value: token)
                        return userToken.save(on: req.db).transform(to: userToken)
                    } else {
                        return req.eventLoop.future(error: Abort(.unauthorized))
                    }
                } catch {
                    return req.eventLoop.future(error: Abort(.internalServerError))
                }
            }
    }
    
    func getProfile(req: Request) throws -> EventLoopFuture<User> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return req.eventLoop.future(user)
    }
    
    func updateUserData(req: Request) throws -> EventLoopFuture<User> {
        req.headers.contentType = .json
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(User.Update.self)
        
        if try Bcrypt.verify(input.old, created: user.passwordHash) == false {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Не верный пароль"))
        }
        
        return User.find(input.id, on: req.db)
            .flatMap { foundUser -> EventLoopFuture<User> in
                guard let newUser = foundUser else {
                    return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Пользователь не найден"))
                }
                
                if let name = input.name {
                    if name.isEmpty == false {
                        newUser.name = name
                    }
                }
                if let email = input.email {
                    if email.isEmpty == false {
                        newUser.email = email
                    }
                }
                if let pass = input.password {
                    if pass.isEmpty == false {
                        do {
                            let passwordHash = try Bcrypt.hash(pass)
                            newUser.passwordHash = passwordHash
                        } catch {
                            return req.eventLoop.makeFailedFuture(error)
                        }
                    }
                }
                if let plan = input.plan {
                    if plan.isEmpty == false {
                        newUser.plan = plan
                    }
                }
                
                if let imageData = input.imageData {
                    if imageData.isEmpty == false {
                        newUser.imageData = imageData
                    }
                }
                
                return newUser.save(on: req.db).map { newUser }
            }
    }
    
    func logout(req: Request) throws -> EventLoopFuture<Status> {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        return UserToken.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .delete()
            .transform(to: Status(message: "Успешный выход из аккаунта"))
    }
    
    private func generateToken() throws -> String {
        let token = SymmetricKey(size: .bits256)
        let tokenString = token.withUnsafeBytes { body in
            Data(body).base64EncodedString()
        }
        return tokenString
    }
}
