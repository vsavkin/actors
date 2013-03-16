library server_actors;

import 'dart:io';
import 'dart:async';
import 'common.dart';
export 'common.dart';

class Connection {
  ActorSystem system;
  Set<String> actors = new Set();
  Channel channel;

  Connection(WebSocket socket, this.system){
    channel = new Channel(system, socket, new WebSocketSink(socket));

    channel.addEventHandler("handshakeRequest", (m){
      channel.sendResponse(m, {});
    });

    channel.addEventHandler("createActorRequest", (m){
      actors.add(m["actorName"]);
      channel.sendResponse(m, {});
    });

    channel.addEventHandler("messageRequest", (m){
      var future = system.send(m["actor"], m["message"], m["args"]);
      future.then((res) => channel.sendResponse(m, {"result": res}));
    });
  }

  send(String actor, String message, List args){
    return channel.sendRequest("message", {"actor": actor, "message": message, "args": args});
  }
}

class ActorSystemServer implements ActorSystem {
  ActorSystem local;
  List<Connection> connections = [];

  ActorSystemServer(this.local);

  static start(Function func)
    => func(new ActorSystemServer(new SyncLocalActorSystem()));

  onConnection(WebSocket conn) {
    print('new ws connection');
    var connection = new Connection(conn, this);
    connections.add(connection);
  }

  send(String actorName, String message, List args) {
    if(local.hasActor(actorName)){
      return local.send(actorName, message, args);
    }
    var c = connections.firstMatching((_) => _.actors.contains(actorName));
    return c.send(actorName, message, args);
  }

  createActor(String actorName, String descriptor, [List args = const []]) =>
    local.createActor(actorName, descriptor, args);

  createAsyncActor(String actorName, String descriptor, [List args = const []]) =>
    local.createAsyncActor(actorName, descriptor, args);

  actor(String actorName) => new ActorRef(actorName, this);

  hasActor(String actorName) => true;
}
