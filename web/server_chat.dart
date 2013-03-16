library server_chat;

import 'dart:async';
import 'dart:mirrors';

import 'package:actors/server_actors.dart';
import 'web_server.dart';

class Conversation {
  List<ActorRef> participants = [];

  add(ActorRef participant){
    participants.add(participant);
    participants.forEach((p) => p.setOthers(_othersNames(p.actorName)));
  }

  broadcast(String name, String message) =>
    _others(name).forEach((p) => p.addMessage(name, message));

  findParticipant(String name) =>
    participants.firstMatching((p) => p.actorName == name);


  _others(name) =>
    participants.where((_) => _.actorName != name).toList();

  _othersNames(name) =>
    participants.map((_) => _.actorName).where((_) => _ != name).toList();
}

main(){
  ActorSystemServer.start((system){
    system.createActor("currentConversation", "server_chat:Conversation");
    startServer("web", "127.0.0.1", 9988, system.onConnection);
  });
}