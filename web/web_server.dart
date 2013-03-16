library web_server;

import 'dart:io';
import 'dart:async';

class StaticFileHandler {
  String folder;

  StaticFileHandler(this.folder);

  onRequest(request) {
    var response = request.response;
    var path = request.uri.toString();
    var file = new File('${folder}${path}');

    print('Static File: ${folder}${path}');

    file.exists().then((exists) {
      if (exists) {
        file.openRead().pipe(response);
      } else {
        response.close();
      }
    });
  }
}

startServer(String folder, String host, int port, Function onConnection) {
  var fileHandler = new StaticFileHandler(folder);

  HttpServer.bind(host, port).
  then((HttpServer server) {
    print("listening for connections on ${port}");

    var sc = new StreamController();
    sc.stream.transform(new WebSocketTransformer()).listen(onConnection);

    server.listen((req) {
      (req.uri.path == '/ws') ? sc.add(req) : fileHandler.onRequest(req);
    });
  }).

  catchError((error){
    print("Error starting HTTP server: $error");
  });
}
