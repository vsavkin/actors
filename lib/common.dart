library common;

import 'dart:async';
import 'dart:mirrors';
import 'dart:json' as json;
import 'package:uuid/uuid.dart';
import 'dart:isolate';

InstanceMirror buildObject(String descriptor, List args){
  var p = descriptor.split(":");
  var mirrors = currentMirrorSystem();
  ClassMirror cm = mirrors.libraries[p[0]].classes[p[1]];

  var argsMirrors = args.map((_) => reflect(_)).toList();
  return deprecatedFutureValue(cm.newInstance("", argsMirrors));
}

spawnAsyncActor(){
  InstanceMirror actorObjectMirror;

  port.receive((message, reply){
    if(actorObjectMirror == null){
      actorObjectMirror = buildObject(message['descriptor'], message['args']);

    } else {
      actorObjectMirror.invoke(message["message"], message["args"]).then((res){
        reply.send(res.reflectee);
      });
    }
  });
}

class ActorRef {
  String actorName;
  ActorSystem actorSystem;

  ActorRef(this.actorName, this.actorSystem);

  ActorRef.fromJson(json, actorSystem) : this(json["actorName"], actorSystem);

  toJson() => {"__actor__" : true, "actorName" : actorName};

  noSuchMethod(InvocationMirror m) =>
    actorSystem.send(actorName, m.memberName, m.positionalArguments.toList());
}

abstract class ActorSystem {
  bool hasActor(String actorName);
  send(String actorName, String message, List args);

  ActorRef createActor(String actorName, String descriptor, [List args]);
  ActorRef createAsyncActor(String actorName, String descriptor, [List args]);
  ActorRef actor(String actorName);
}

abstract class Actor {
  Future invoke(String message, List args);
}

class SyncActor implements Actor {
  var receiverMirror;

  SyncActor(String descriptor, List args){
    receiverMirror = buildObject(descriptor, args);
  }

  Future invoke(String message, List args) {
    var argsMirrors = args.map((_) => reflect(_)).toList();
    var future = receiverMirror.invoke(message, argsMirrors);
    return future.then((res) => res.reflectee);
  }
}

class AsyncActor implements Actor {
  SendPort port;

  AsyncActor(String descriptor, List args){
    this.port = spawnFunction(spawnAsyncActor);
    this.port.send({"descriptor": descriptor, "args": args});
  }

  Future invoke(String message, List args) {
    return port.call({"message" : message, "args" : args});
  }
}

class SyncLocalActorSystem implements ActorSystem {
  Map<String, Actor> actorMirrors = {};

  createActor(String actorName, String descriptor, [List args = const []]){
    actorMirrors[actorName] = new SyncActor(descriptor, args);
    return new ActorRef(actorName, this);
  }

  createAsyncActor(String actorName, String descriptor, [List args = const []]){
    actorMirrors[actorName] = new AsyncActor(descriptor, args);
    return new ActorRef(actorName, this);
  }

  send(String actorName, String message, List args){
    var actor = actorMirrors[actorName];
    if(actor == null){
      throw "No actor ${actorName} defined";
    }
    return actor.invoke(message, args);
  }

  actor(String actorName) => new ActorRef(actorName, this);

  hasActor(String actorName) => actorMirrors.containsKey(actorName);
}

class Serializer {
  ActorSystem system;

  Serializer(this.system);

  parse(String m)
    => json.parse(m, (k, v){
      if(v is Map && v.containsKey("__actor__")){
        return new ActorRef.fromJson(v, system);
      } else {
        return v;
      }
    });
}

class Channel {
  ActorSystem system;
  Stream<String> stream;
  StreamSink<String> sink;
  StreamSubscription subscription;

  Map<String, Completer> pendingRequests = {};
  Map<String, Function> eventHandlers = {};

  Channel(this.system, this.stream, this.sink){
    subscription = this.stream.listen(onMessage);
  }

  addEventHandler(String type, Function f){
    eventHandlers[type] = f;
  }

  Future sendRequest(String type, Map map){
    return sendMessage(generateMessageId(), "${type}Request", map);
  }

  Future sendResponse(Map original, Map map){
    var type = original["messageType"].split("Request")[0];
    return sendMessage(original["messageId"], "${type}Response", map);
  }

  Future sendMessage(messageId, messageType, map){
    map["messageId"] = messageId;
    map["messageType"] = messageType;

    var message = json.stringify(map);
    print('Sending Message ${message}');

    var c = new Completer();
    pendingRequests[messageId] = c;
    sink.add(message);
    return c.future;
  }

  onMessage(String message){
    print('Received Message ${message}');

    var s = new Serializer(system);
    var m = s.parse(message);
    var type = m["messageType"];

    if(eventHandlers.containsKey(type)){
      eventHandlers[type](m);
    } else {
      processResponse(m);
    }
  }
  processResponse(m) {
    var completer = pendingRequests.remove(m["messageId"]);
    completer.complete(m["result"]);
  }

  generateMessageId() => new Uuid().v1();
}


class WebSocketSink implements StreamSink<String> {
  var socket;
  WebSocketSink(this.socket);

  void add(String event){
    socket.send(event);
  }

  void signalError(AsyncError errorEvent){
    throw "Implement";
  }

  void close(){
    socket.close();
  }
}
