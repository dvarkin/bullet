/*
	Copyright (c) 2011-2012, Loïc Hoguin <essen@ninenines.eu>

	Permission to use, copy, modify, and/or distribute this software for any
	purpose with or without fee is hereby granted, provided that the above
	copyright notice and this permission notice appear in all copies.

	THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
	WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
	ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
	WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
	ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
	OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/

/**
	Bullet is a client-side javascript library AND server-side Cowboy handler
	to manage continuous streaming. It selects the proper transport in a fully
	automated way and makes sure to always reconnect to the server on any
	disconnect. You only need to handle sending messages, receiving them,
	and managing the heartbeat of the stream.

	Usage: $.bullet(url);

	Then you can register one of the 4 event handlers:
	onopen, onmessage, onclose, onheartbeat.

	onopen is called once right after starting the bullet stream.
	onmessage is called once for each message receveid.
	onclose is called once right after you voluntarily close the socket.
	onheartbeat is called once every few seconds to allow you to easily setup
	a ping/pong mechanism.
*/
(function($){$.extend({bullet: function (url, active) {
	var CONNECTING = 0;
	var OPEN = 1;
	var CLOSING = 2;
	var CLOSED = 3;

	var transports = {
		/**
			The websocket transport is disabled for Firefox 6.0 because it
			causes a crash to happen when the connection is closed.
			@see https://bugzilla.mozilla.org/show_bug.cgi?id=662554
		*/
		websocket: function(){
			var ret = false;

			if (window.WebSocket){
				ret = window.WebSocket;
			}

//			if (window.MozWebSocket
//					&& navigator.userAgent.indexOf("Firefox/6.0") == -1){
//				ret = window.MozWebSocket;
//			}

			if (ret){
				return {'heart': true, 'transport': ret};
			}

			return false;
		},

		xhrPolling: function(){
			var timeout;
			var xhr;

			var fake = {
				readyState: CONNECTING,
				ssid: false,
				send: function(data){
					if (this.readyState != OPEN){
						return false;
					}

					var fakeurl = url.replace('ws:', 'http:').replace('wss:', 'https:');
					if (this.ssid) fakeurl += '?s='+ encodeURIComponent(this.ssid);

					$.ajax({
						async: false,
						cache: false,
						type: 'POST',
						url: fakeurl,
						data: data,
						dataType: 'text',
						contentType:
							'application/x-www-form-urlencoded; charset=utf-8',
						headers: {'X-Socket-Transport': 'xhrPolling'}
					});

					return true;
				},
				close: function(){
					this.readyState = CLOSED;
					xhr.abort();
					clearTimeout(timeout);
					fake.onclose();
				},
				onopen: function(){},
				onmessage: function(){},
				onerror: function(){},
				onclose: function(){}
			};

			function decode(data, onframe) {
				var frames = data.split('\n');
				for (i = 0; i < frames.length; i++) {
					var framedata = frames[i].replace('\\n', '\n').replace('\\\\', '\\');
					if (framedata.length > 0) { onframe(framedata); }
				}
			};

			function poll(){
				var fakeurl = url.replace('ws:', 'http:').replace('wss:', 'https:');
				if (fake.ssid) fakeurl += '?s='+ encodeURIComponent(fake.ssid);

				xhr = $.ajax({
					type: 'GET',
					cache: false,
					url: fakeurl,
					dataType: 'text',
					data: {},
					headers: {'X-Socket-Transport': 'xhrPolling'},
					success: function(data){
						if (fake.readyState == CONNECTING){
							fake.readyState = OPEN;
							fake.ssid = data;
							fake.onopen(fake);
						}
						// Decode received packet and trigger onmessage for each frame
						else decode(data, function (frame) {
							fake.onmessage({'data': frame})
						});

						if (fake.readyState == OPEN){
							nextPoll();
						}
					},
					error: function(xhr){
						// don't trigger onerror if transport have been already closed
						if (fake.readyState != CLOSED) {
							fake.onerror();
						}
					}
				});
			}

			function nextPoll(){
				timeout = setTimeout(function(){poll();}, 100);
			}

			poll();
			return {'heart': false, 'transport': function(){ return fake; }};
		}
	};

	var tn = 0;
	if (typeof active == 'object') {
		for (var f in active) { 
			if (active[f]) { active[f] = transports[f]; } else { delete active[f]; };
		};
		transports = active;
	};

	function next(){
		var c = 0;

		for (var f in transports){
			if (tn == c){
				var t = transports[f]();
				if (t){
					var ret = new t.transport(url);
					ret.heart = t.heart;
					return ret;
				}

				tn++;
			}

			c++;
		}

		return false;
	}

	var stream = new function(){
		var isClosed = true;
		var readyState = CLOSED;
		var heartbeat;
		var delay = delayDefault = 80;
		var delayMax = 10000;

		var transport;
		function init(){
			isClosed = false;
			readyState = CONNECTING;
			transport = next();

			if (!transport){
				// Hard disconnect, inform the user and retry later
				delay = delayDefault;
				tn = 0;
				setTimeout(function(){init();}, delayMax);
				return false;
			}

			transport.onopen = function(){
				// We got a connection, reset the poll delay
				delay = delayDefault;

				if (transport.heart){
					heartbeat = setInterval(function(){stream.onheartbeat();}, 20000);
				}

				if (readyState != OPEN){
					readyState = OPEN;
					stream.onopen();
				}
			};
			transport.onclose = function(){
				// Firefox 13.0.1 sends 2 close events.
				// Return directly if we already handled it.
				if (isClosed){
					return;
				}

				clearInterval(heartbeat);

				if (readyState == CLOSING){
					readyState = CLOSED;
					stream.ondisconnect();
					stream.onclose();
				} else{
					// Close happened on connect, select next transport
					if (readyState == CONNECTING){
						tn++;
					}
					// Open transport have closed, trigger ondisconnect
					else if (readyState == OPEN) {
						stream.ondisconnect();
					}

					delay *= 2;
					if (delay > delayMax){
						delay = delayMax;
					}

					isClosed = true;

					setTimeout(function(){
						init();
					}, delay);
				}
			};
			transport.onerror = transport.onclose;
			transport.onmessage = function(e){
				stream.onmessage(e);
			};
		}
		init();

		this.onopen = function(){};
		this.onmessage = function(){};
		this.ondisconnect = function(){};
		this.onclose = function(){};
		this.onheartbeat = function(){};

		this.send = function(data){
			return transport.send(data);
		};
		this.close = function(){
			readyState = CLOSING;
			transport.close();
		};
	};

	return stream;
}})})(jQuery);
