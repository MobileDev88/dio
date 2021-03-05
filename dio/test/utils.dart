// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

/// The current server instance.
HttpServer _server;

Encoding requiredEncodingForCharset(String charset) =>
    Encoding.getByName(charset) ??
        (throw FormatException('Unsupported encoding "$charset".'));

/// The URL for the current server instance.
Uri get serverUrl => Uri.parse('http://localhost:${_server.port}');

/// Starts a new HTTP server.
Future<void> startServer() async {
  _server = (await HttpServer.bind('localhost', 0))
    ..listen((request) async {
      var path = request.uri.path;
      var response = request.response;

      if (path == '/error') {
        response
          ..statusCode = 400
          ..contentLength = 0;
        unawaited(response.close());
        return;
      }

      if (path == '/loop') {
        var n = int.parse(request.uri.query);
        response
          ..statusCode = 302
          ..headers
              .set('location', serverUrl.resolve('/loop?${n + 1}').toString())
          ..contentLength = 0;
        unawaited(response.close());
        return;
      }

      if (path == '/redirect') {
        response
          ..statusCode = 302
          ..headers.set('location', serverUrl.resolve('/').toString())
          ..contentLength = 0;
        unawaited(response.close());
        return;
      }

      if (path == '/no-content-length') {
        response
          ..statusCode = 200
          ..contentLength = -1
          ..write('body');
        unawaited(response.close());
        return;
      }

      if (path == '/list') {
        response.headers.contentType =
            ContentType('application', 'json');
        response
          ..statusCode = 200
          ..contentLength = -1
          ..write('[1,2,3]');
        unawaited(response.close());
        return;
      }

      if (path == "/download") {
        const content = 'I am a text file';
        response
          ..statusCode = 200
          ..contentLength = content.length
          ..write(content);
        unawaited(response.close());
        return;
      }

      var requestBodyBytes = await ByteStream(request).toBytes();
      var encodingName = request.uri.queryParameters['response-encoding'];
      var outputEncoding = encodingName == null
          ? ascii
          : requiredEncodingForCharset(encodingName);

      response.headers.contentType =
          ContentType('application', 'json', charset: outputEncoding.name);
      response.headers.set('single', 'value');

      dynamic requestBody;
      if (requestBodyBytes.isEmpty) {
        requestBody = null;
      } else if (request.headers.contentType?.charset != null) {
        var encoding =
            requiredEncodingForCharset(request.headers.contentType.charset);
        requestBody = encoding.decode(requestBodyBytes);
      } else {
        requestBody = requestBodyBytes;
      }

      var content = <String, dynamic>{
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.query,
        'headers': {}
      };
      if (requestBody != null) content['body'] = requestBody;
      request.headers.forEach((name, values) {
        // These headers are automatically generated by dart:io, so we don't
        // want to test them here.
        if (name == 'cookie' || name == 'host') return;

        content['headers'][name] = values;
      });

      var body = json.encode(content);
      response
        ..contentLength = body.length
        ..write(body);
      unawaited(response.close());
    });
}

/// Stops the current HTTP server.
void stopServer() {
  if (_server != null) {
    _server.close();
    _server = null;
  }
}

/// A matcher for functions that throw SocketException.
final Matcher throwsSocketException =
    throwsA(const TypeMatcher<SocketException>());

/// A stream of chunks of bytes representing a single piece of data.
class ByteStream extends StreamView<List<int>> {
  ByteStream(Stream<List<int>> stream) : super(stream);

  /// Returns a single-subscription byte stream that will emit the given bytes
  /// in a single chunk.
  factory ByteStream.fromBytes(List<int> bytes) =>
      ByteStream(Stream.fromIterable([bytes]));

  /// Collects the data of this stream in a [Uint8List].
  Future<Uint8List> toBytes() {
    var completer = Completer<Uint8List>();
    var sink = ByteConversionSink.withCallback(
        (bytes) => completer.complete(Uint8List.fromList(bytes)));
    listen(sink.add,
        onError: completer.completeError,
        onDone: sink.close,
        cancelOnError: true);
    return completer.future;
  }

  /// Collect the data of this stream in a [String], decoded according to
  /// [encoding], which defaults to `UTF8`.
  Future<String> bytesToString([Encoding encoding = utf8]) =>
      encoding.decodeStream(this);

  Stream<String> toStringStream([Encoding encoding = utf8]) =>
      encoding.decoder.bind(this);
}
