//
//  File.swift
//  
//
//  Created by Иван Доронин on 27.05.2024.
//

import Fluent
import Vapor

final class ChatController: RouteCollection {
    private var connections = Set<WebSocket>()

    func boot(routes: RoutesBuilder) throws {
        let chats = routes.grouped("chats")
        let protectedChats = chats.grouped(UserTokenAuthenticator())
        protectedChats.webSocket("connect", onUpgrade: handleWebSocketConnect)
        protectedChats.post("history", use: getHistory)
    }
    
    func getHistory(req: Request) throws -> EventLoopFuture<[Chat]> {
        req.headers.contentType = .json
        guard let _ = req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }
        
        let input = try req.content.decode(Chat.HistoryRequest.self)
        
        return Chat.query(on: req.db)
            .filter(\.$musicRoom.$id == input.musicRoomID)
            .all()
    }

    func handleWebSocketConnect(req: Request, socket: WebSocket) {
        socket.pingInterval = .seconds(10)
        self.connections.insert(socket)

        socket.onText { socket, text in
            do {
                let message = try JSONDecoder().decode(Chat.MessageResponse.self, from: text.data(using: .utf8)!)
                print("Received message: \(message.message)")

                let newMessage = Chat(
                    message: message.message,
                    creatorID: UUID(uuidString: message.creator)!,
                    musicRoomID: UUID(uuidString: message.musicRoom)!)
                newMessage.save(on: req.db).map {
                    do {
                        let messageData = try JSONEncoder().encode(message)
                        if let messageString = String(data: messageData, encoding: .utf8) {
                            for connection in self.connections {
                                connection.send(messageString)
                            }
                        }
                    } catch {
                        print("Failed to encode message: \(error)")
                    }
                }.whenFailure { error in
                    print("Failed to save message: \(String(reflecting: error))")
                }
            } catch {
                print("Failed to decode message: \(error)")
            }
        }

        socket.onClose.whenComplete { [weak self] _ in
            guard let self = self else { return }
            self.connections.remove(socket)
            print("WebSocket closed")
        }
    }
}


extension WebSocket: Hashable {
    public static func == (lhs: WebSocket, rhs: WebSocket) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}


extension Chat {
    struct HistoryRequest: Content {
        let musicRoomID: UUID
    }
    
    struct MessageResponse: Content {
        let message: String
        let creator: String
        let musicRoom: String
    }
}
