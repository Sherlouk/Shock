//
//  MockNIOHTTPServer.swift
//  Shock
//
//  Created by Antonio Strijdom on 30/09/2020.
//

import Foundation
import NIO
import NIOHTTP1

/// SwiftNIO implementation of mock HTTP server
class MockNIOHttpServer: MockNIOBaseServer, MockHttpServer {
    
    private let responseFactory: ResponseFactory
    private var httpHandler: MockNIOHTTPHandler?
    private var router = MockNIOHTTPRouter()
    private var middleware = [Middleware]()
    private var routeMiddleware: MockRoutesMiddleware?
    var notFoundHandler: HandlerClosure?
    
    init(responseFactory: ResponseFactory) {
        self.responseFactory = responseFactory
        super.init()
    }
    
    func start(_ port: Int, forceIPv4: Bool, priority: DispatchQoS.QoSClass) throws -> Void {
        try start(port) { (channel) -> EventLoopFuture<Void> in
            channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                self.httpHandler = MockNIOHTTPHandler(responseFactory: self.responseFactory,
                                                      router: self.router,
                                                      middleware: self.middleware,
                                                      notFoundHandler: self.notFoundHandler)
                return channel.pipeline.addHandler(self.httpHandler!)
            }
        }
    }
    
    func register(route: MockHTTPRoute, handler: HandlerClosure?) {
        if let urlPath = route.urlPath, urlPath.isEmpty {
            return
        }
        self.router.register(route: route, handler: handler)
    }
    
    func add(middleware: Middleware) {
        self.middleware.append(middleware)
    }
    
    func has<T>(middlewareOfType type: T.Type) -> Bool where T: Middleware {
        return (self.middleware ?? []).contains { $0 is T }
    }
}

struct MockNIOHTTPRequest: MockHttpRequest {
    var eventLoop: EventLoop
    var path: String
    var queryParams: [(String, String)]
    var method: String
    var headers: [String : String]
    var body: [UInt8]
    var address: String?
    var params: [String : String]
}

struct RouteHandlerMapping {
    let route: MockHTTPRoute
    let handler: HandlerClosure
}

class MockNIOHTTPRouter: MockHttpRouter {
    private let lockQueue = DispatchQueue(label: "routes.lock.queue")
    private var _routesOnlyAvailableViaLockQueue = [MockHTTPMethod: [RouteHandlerMapping]]()
    private var routes: [MockHTTPMethod: [RouteHandlerMapping]] {
        get {
            var value = [MockHTTPMethod: [RouteHandlerMapping]]()
            lockQueue.sync { [weak self] in
                guard let self else { return }
                value = self._routesOnlyAvailableViaLockQueue
            }
            return value
        }
        set(newValue) {
            lockQueue.async { [weak self] in
                guard let self else { return }
                self._routesOnlyAvailableViaLockQueue = newValue
            }
        }
    }
    
    var requiresRouteMiddleware: Bool {
        !routes.isEmpty
    }
    
    func handlerForMethod(_ method: String, path: String, params: [String:String], headers: [String:String]) -> HandlerClosure? {
        guard let httpMethod = MockHTTPMethod(rawValue: method.uppercased()) else { return nil }
        let methodRoutes = routes[httpMethod] ?? [RouteHandlerMapping]()
        for mapping in methodRoutes {
            if mapping.route.matches(method: httpMethod, path: path, params: params, headers: headers) {
                return mapping.handler
            }
        }
        return nil
    }
    
    func register(route: MockHTTPRoute, handler: HandlerClosure?) {
        guard let method = route.method else { return }
        var methodRoutes = routes[method] ?? [RouteHandlerMapping]()
        if methodRoutes.contains() { $0.route == route } {
            methodRoutes = methodRoutes.filter({ $0.route != route })
        }
        if let handler = handler {
            methodRoutes.append(RouteHandlerMapping(route: route, handler: handler))
        }
        routes[method] = methodRoutes
    }
}
