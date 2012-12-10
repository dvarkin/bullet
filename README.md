Bullet
======

Bullet is a Cowboy handler and associated Javascript library for
maintaining a persistent connection between a client and a server.

Bullet abstracts a general transport protocol familiar to WebSockets, and
is equipped with several "fallback" transports. Bullet will automatically
use one of these when the browser used is not able to support WebSockets.

A common interface is defined for both client and server-side to easily
facilitate the handling of such connections. Bullet additionally takes care
of reconnecting automatically whenever a connection is lost, and also
provides an optional heartbeat which is managed on the client side.

Today Bullet only supports websocket and long-polling transports.

This is a fork of [original Bullet](https://github.com/extend/bullet) project. 
The major goal of forking is to implement server-side session process for long-polling transport. 
This allows server-side handler for long-polling transport to share the same persistent connection semantics with 
websocket transport. This project doesn't provide backward compatibility with the original Bullet. 

Starting Bullet
---------------

Bullet is an ordinary OTP application, so it have to be started before usage as follows:
``` erlang
application:start(bullet)
```

Dispatch options
----------------

Similar to any other handler, you need to setup the dispatch list before
you can access your Bullet handlers. Bullet itself is a Cowboy HTTP
handler that translates some of the lower-level functions into a
simplified higher-level interface.

The dispatch options for a Bullet handler looks as follow:

``` erlang
{[<<"path">>, <<"to">>, <<"bullet">>], bullet_handler,
	[{handler, my_stream}]}
```

Simply define this in your dispatch list and your handler will be
available and handled by Bullet properly.

Cowboy handler
--------------

Similar to websocket handlers, you need to define 4 functions.
A very simple bullet handler would look like the following:

``` erlang
-module(stream_handler).
-export([init/1, stream/2, info/2, terminate/1]).

init(_Opts) ->
	{ok, undefined_state}.

stream(Data, State) ->
	{reply, Data, State}.

info(_Info, State) ->
	{ok, State}.

terminate(_Req, _State) ->
	ok.
```
The handler provides an abstraction of persistent connection between client and server with the ability
to transmit data in both directions. All server-side processing is done in a separate erlang process 
(websocket handler process for websocket transport and special session process for long-polling).
Bullet processes should be considered temporary as you never know when a connection is going to close
and therefore lose your State.

Of note is that the init/1 and terminate/1 functions are called
everytime a connection is made or closed, respectively, which can
happen many times over the course of a bullet connection's life,
as Bullet will reconnect everytime it detects a disconnection.

Note that you do not need to handle a heartbeat server-side, it
is automatically done when needed by the Bullet client as explained
later in this document.

Client-side javascript
----------------------

Bullet requires the jQuery library to be used. Initializing a
bullet connection is quite simple and can be done directly from
a document.ready function like this:

``` js
$(document).ready(function(){
	var bullet = $.bullet('ws://localhost/path/to/bullet/handler');
	bullet.onopen = function(){
		console.log('WebSocket: opened');
	};
	bullet.onclose = function(){
		console.log('WebSocket: closed');
	};
	bullet.onmessage = function(e){
		alert(e.data);
	};
	bullet.onheartbeat = function(){
		bullet.send('ping');
	}
});
```

Bullet works especially well when it is used to send JSON data
formatted with the jQuery JSON plugin.

``` js
bullet.send($.toJSON({type: 'event', data: 'hats!'}));
```

When receiving JSON you would typically receive a list of events,
in which case your onmessage handler can look like this, assuming
you previously defined a handlers function array for all your events:

``` js
	bullet.onmessage = function(e){
		var obj = $.parseJSON(e.data);
		for (i = 0; i < obj.length; i++){
			handlers[obj[i].type](obj[i]);
		}
	};
```
