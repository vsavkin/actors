library client_actors;

import 'dart:async';
import 'dart:html';
import 'common.dart';
export 'common.dart';

class WebSocketStreamTransformer extends StreamEventTransformer {
  void handleData(MessageEvent event, StreamSink<String> sink) {
    sink.add(event.data);
  }
}

class ActorSystemClient implements ActorSystem {
  WebSocket webSocket;
  Channel channel;

  ActorSystem local;

  ActorSystemClient(this.local);

  static start(String url)
    => new ActorSystemClient(new SyncLocalActorSystem()).connect(url);

  Future connect(String url){
    webSocket = new WebSocket(url)
      ..onClose.listen((e){throw "WebSocket: Close";})
      ..onError.listen((e){throw "WebSocket: Error";});

    var stream = webSocket.onMessage.transform(new WebSocketStreamTransformer());
    var sink = new WebSocketSink(webSocket);
    channel = new Channel(this, stream, sink);

    channel.addEventHandler("messageRequest", (Map m){
      var future = local.send(m["actor"], m["message"], m["args"]);
      future.then((res) => channel.sendResponse(m, {"result": res}));
    });

    return webSocket.onOpen.first.
           then((_) => sendHandshakeMessage()).
           then((_) => this);
  }

  sendHandshakeMessage(){
    return channel.sendRequest("handshake", {});
  }

  send(String actor, String message, List args){
    if(local.hasActor(actor)){
      return local.send(actor, message, args);
    } else {
      return channel.sendRequest("message", {"actor": actor, "message": message, "args": args});
    }
  }

  createActor(String actorName, String descriptor, [List args = const []]){
    var ref = local.createActor(actorName, descriptor, args);
    channel.sendRequest("createActor", {"actorName": actorName});
    return ref;
  }

  createAsyncActor(String actorName, String descriptor, [List args = const []]){
    var ref = local.createAsyncActor(actorName, descriptor, args);
    channel.sendRequest("createActor", {"actorName": actorName});
    return ref;
  }

  hasActor(String actorName) => true;

  actor(String actorName) => new ActorRef(actorName, this);
}