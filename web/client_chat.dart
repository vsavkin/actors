library client_chat;

import 'dart:async';
import 'dart:html';

import 'package:actors/client_actors.dart';
import 'package:vint/vint.dart';

class ChatSession extends Model {
  ChatSession(String userName) : super({
      "userName" : userName,
      "othersNames" : [],
      "messages" : []});

  addMessage(String userName, String message) {
    messages.add(new Message(userName, message));
    events.fireChange(new ChangeEvent(this, "messages", null, null));
  }
}

class Message {
  String senderName, message;

  Message(this.senderName, this.message);

  String format(ChatSession session) {
    if(session.userName == senderName){
      return "You >> ${message}";
    } else {
      return "${senderName} >> ${message}";
    }
  }
}

class Participant {
  ChatSession chatSession;
  ActorRef conversation;
  Participant(this.chatSession, this.conversation);

  //browser -> server
  sendPublicMessage(String message) {
    conversation.broadcast(chatSession.userName, message);
  }

  //browser -> browser
  sendPrivateMessage(String receiverName, String message) {
    conversation.
      findParticipant(receiverName).
      then((p) => p.addMessage(chatSession.userName, message));
  }

  //server -> browser
  setOthers(List names){
    chatSession.othersNames = names;
  }

  //server -> browser OR browser -> browser
  addMessage(String senderName, String message) {
    chatSession.addMessage(senderName, message);
  }
}

class ChatApp {
  EventBus eventBus;
  ActorSystem system;
  ActorRef participant;

  ChatApp(this.system){
    eventBus = new EventBus()
               ..stream("register").first.then(joinConversation)
               ..stream("message").listen(onMessage);
  }

  void start(){
    new RegisterForm(query("#content"), eventBus).render();
  }

  joinConversation(name){
    var chatSession = new ChatSession(name);

    var conversation = system.actor("currentConversation");
    participant = system.createActor(name, 'client_chat:Participant', [chatSession, conversation]);
    conversation.add(participant);

    new ChatView(chatSession, query("#content"), eventBus).render();
  }

  onMessage(e){
    if(e["receiver"] == "All"){
      participant.sendPublicMessage(e["message"]);
    } else {
      participant.sendPrivateMessage(e["receiver"], e["message"]);
    }
  }
}


main(){
  ActorSystemClient.start("ws://localhost:9988/ws").then((system){
    var chat = new ChatApp(system);
    chat.start();
  });
}








class RegisterForm extends Presenter {
  EventBus eventBus;

  RegisterForm(el, this.eventBus) : super(null, el, registerTemplate);

  get ui => {
      "name" : "input"
  };

  get events => {
      "click button" : register,
      "keypress input": maybeRegister
  };

  register(e){
    eventBus.sink("register").add(name.value);
  }

  maybeRegister(e){
    if(e.keyCode == 13)
      register(e);
  }

  render(){
    super.render();
    name.focus();
  }
}

class ChatView extends Presenter<ChatSession> {
  var eventBus;

  ChatView(chatSession, el, this.eventBus) : super(chatSession, el, chatTemplate);

  subscribeToModelEvents(){
    model.events.onChange.listen((e) => render());
  }

  get ui => {
      "message" : "input"
  };

  get events => {
      "click button" : addMessage,
      "keypress input": maybeSendMessage
  };

  addMessage(e){
    var receiver = e.toElement.attributes["data-actor"];
    addMessageTo(receiver, message.value);
  }

  maybeSendMessage(e){
    if(e.keyCode == 13){
      addMessageTo('All', message.value);
    }
  }

  addMessageTo(receiver, message){
    eventBus.sink("message").add({"message" : message, "receiver" : receiver});
    model.addMessage(model.userName, message);
  }

  render(){
    super.render();
    message.focus();
  }
}

registerTemplate(m){
  return """
        <div class="input-append" style='text-align:center;'>
          <input type='text' placeholder='Name'/>
          <button class='btn'>Join</button>
        </div>
      """;
}

chatTemplate(m){
  var others = m.othersNames.map((_) => "<button class='btn' data-actor='${_}'>Send to ${_}</li>").join("\n");
  var messages = m.messages.reversed.map((_) => "<p class='well well-small'>${_.format(m)}</p>").join("\n");

  return """
    <div class='row'>
      <div class='span2'>
        <p style='text-align: right;'>${m.userName} says</p>
      </div>
      <div class='span4'>
        <input type="text" placeholder='Message..' class="input-block-level">
      </div>
      <div class="btn-group span2">
        <button class="btn" data-actor='All'>Send to All</button>
        ${others}
      </div>
    </div>
    <div style='width:100%;'>${messages}</div>
  """;
}
