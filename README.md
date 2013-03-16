# Actors.Dart - Building Distributed Applications on the Web Platform

Having worked on applications where a large portion of the business logic lives on the client side, I’ve seen how distribution causes pain and adds a great deal of complexity to relatively simple applications. Since distribution is one of the main sources of complexity, easing it will enable developers to write modern web applications more efficiently.
 
Don’t get me wrong! HTTP or WebSocket are great, but they are too low level for most day-to-day use cases. I believe that having higher-level abstractions can significantly reduce the complexity of building distributed applications. 

Sean Kirby and I spent one day building a prototype of an actor library to demonstrate that. This repository contains the result of our work.

### Sample Application Demo
 
This is a simple chat application built using our library.

#### [Watch sample application demo.](http://www.youtube.com/watch?v=wcYQEGf3sSE)


## Sample Application Source Code

The application is not particularly impressive, but it illustrates all the types of communication you see in a typical web application:
 
* Browser -> Server

![Browser->Server](https://lh6.googleusercontent.com/-9soImJ024Bs/UUTCFL1F1SI/AAAAAAAAAjU/x97-9nbAZQY/s428/actors1.png)

* Server -> Browser

![Server -> Browser](https://lh6.googleusercontent.com/-kwA77JU5gjc/UUTCGd9xs2I/AAAAAAAAAjc/zCjTVvXmSJ8/s427/actors2.png)

* Browser -> Browser

![Server -> Browser](https://lh6.googleusercontent.com/-u4sWji4LGq4/UUTCHEREwqI/AAAAAAAAAjk/j-36ZN1qRkg/s458/actors3.png)

 
I'd like to walk you through the implementation of the chat application.

### Server

First, we initialize an actor system and start a web server.

    main(){
      ActorSystemServer.start((system){
        system.createActor("currentConversation", "server_chat:Conversation");
        startServer("web", "127.0.0.1", 9988, system.onConnection);
      });
    }

Creating an actor is done as follows:

    system.createActor("currentConversation", "server_chat:Conversation");

The createActor function creates an actor and returns an instance of ActorRef. You never talk to an actor directly; you use an ActorRef instead. The createActor function creates an object in the current isolate.

![ActorRef](https://lh4.googleusercontent.com/-xBXF3tgYxPo/UUTCIJFwAEI/AAAAAAAAAjs/7YgK6W_ehvI/s410/actors4.png)
 
Creating an actor in a separate isolate is done as follows:

    system.createAcyncActor("currentConversation", "server_chat:Conversation");

Let's look at the Conversation actor:

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

A Conversation has a list of participants, which you can add an object to. It can also broadcast messages to all the registered participants, and find a participant by name.  A conversation is a plain old Dart object. No special classes have to be extended.

That's all we need to do to make the server work. Now let's look at the client.

### Browser

Similarly to the server, we start with creating an actor system.

    main(){
      ActorSystemClient.start("ws://localhost:9988/ws").then((system){
        var chat = new ChatApp(system);
        chat.start();
      });
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
 
        ActorRef conversation = system.actor("currentConversation");
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

ChatApp is a coordinator managing all the interactions.

* EventBus, ChatView, and RegisterForm are used to render the UI. They have nothing to do with the actor library.  You can ignore them.
* When a user joins the current conversation, the ChatApp object will create a new Participant actor for that user. Then, it’ll add it to the Conversation actor.
* When a user sends a message, ChatApp will use the created Participant to deliver it.

The Participant actor is where it gets interesting.

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
        Future<ActorRef> f = conversation.findParticipant(receiverName);
        f.then((p) => p.addMessage(chatSession.userName, message));
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

This actor illustrates the three types of communication of a typical web application:

#### Browser -> Server

The sendPublicMessage function sends a message to the server.

#### Server -> Browser

When a new person registers, the server will send the setOthers message to each client.

#### Browser -> Browser

This is the most interesting one. I can have an ActorRef to an actor "living" in another browser. In this application, I use this capability to send a private message to another participant.

It's definitely not the best idea to mix all the types of communication in one object. It makes this object harder to understand. Here it's done to show that you can communicate with an actor living on the same machine, on the server, or on a different machine in the same way. It allows you to change the communication patterns in a very agile way.

For instance, I can add sendPrivateMessage to the Conversation actor, so the Participant class will look like this:

    class Participant {
      ....
      sendPrivateMessage(String receiverName, String message) {
        conversation.sendPrivateMessage(chatSession.userName, receiverName, message);
      }
    }

By doing that I'll replace the `Browser->Browser` pattern with `Browser->Server`.

Or I can implement broadcasting on the client side as follows:

    class Participant {
      ....
      sendPublicMessage(String message) {
        conversation.getParticipants().then((ps){
          ps.each((p) => p.addMessage(chatSession.userName, message));
        });
      }
    }
 
By doing that I'll replace the `Browser->Server` pattern with `Browser->Browser`.

## What Is Done

* Objects “living” on the client can reference objects “living” on the server and vice versa.
* Objects “living” on Client A can reference objects “living” on Client B.
* Objects "living" on different machines can send each other data or ActorRefs.
* An object can be moved to a separate process or even to another machine without changing its implementation and without affecting its clients!
* No code generation. Everything is done through reflection.
* No need to use HTTP or WebSocket directly.

## Just a Prototype

The library is just a prototype (an experiment) and should not be used in production. There is no error handling, it doesn't handle web socket reconnections, and there are no tests.

## Further Work

Since the library is built in a day, it’s just a prototype. However, it’d be interesting to work on such a library for real, carefully designing every piece of it. I think it may help the Dart community. 

I'd like to mention that in general the Dart platform is mature and a pleasure to work it. The only source of frustration is the incomplete implementation of mirrors. Which I hope will be fixed soon.

 

