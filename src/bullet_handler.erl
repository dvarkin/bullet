%% Copyright (c) 2011-2012, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
-module(bullet_handler).

-behaviour(cowboy_http_handler).
-export([init/3, handle/2, info/3, terminate/2]).

-behaviour(cowboy_http_websocket_handler).
-export([websocket_init/3, websocket_handle/3,
	websocket_info/3, websocket_terminate/3]).

-record(state, {
	handler :: module(),
	handler_state :: term()
}).

%% HTTP.

init(_Transport, Req, Opts) ->
	case cowboy_http_req:header('Upgrade', Req) of
		{undefined, _} ->
			{Method, Req0} = cowboy_http_req:method(Req),
			{S, Req1} = cowboy_http_req:qs_val(<<"s">>, Req0),

			case Method of
				'GET'	-> init_poll(Req1, Opts, try_decode_pid(S));
				'POST'	-> {ok, Req1, {stream, try_decode_pid(S)}}
			end;

		{Proto, _} when is_binary(Proto) ->
			case cowboy_bstr:to_lower(Proto) of
				<<"websocket">> ->
					{upgrade, protocol, cowboy_http_websocket};
				_Any ->
					{ok, Req0} = cowboy_http_req:reply(501, [], [], Req),
					{shutdown, Req0, undefined}
			end
	end.

init_poll(Req, Opts, undefined)	-> {ok, Req, {start_session, Opts}};
init_poll(Req, _, {K, Pid})		->
	Mon = erlang:monitor(process, Pid),
	Pid ! {poll, K, self()},
	{loop, Req, {poll, Pid, Mon}, hibernate}.
	
handle(Req, {start_session, Opts}) ->
	Key = generate_key(),
	{ok, Pid} = supervisor:start_child(bullet_sup, [Key, Opts]),
	{ok, Req0} = cowboy_http_req:reply(200, [], encode_pid(Key, Pid), Req),
	{ok, Req0, pass};

handle(Req, {stream, undefined}) ->
	{ok, Req0} = cowboy_http_req:reply(404, Req),
	{ok, Req0, undefined};

handle(Req, {stream, {K, Pid}}) ->
	case cowboy_http_req:body(Req) of
		{ok, Data, Req0} ->
			Pid ! {stream, K, Data},
			{ok, Req1} = cowboy_http_req:reply(200, Req0),
			{ok, Req1, undefined};

		{error, _}	->
			{ok, Req0} = cowboy_http_req:reply(400, Req),
			{ok, Req0, undefined}
	end.

info({'DOWN', Mon, _, _, _}, Req, {poll, _, Mon}) ->
	{ok, Req0} = cowboy_http_req:reply(404, Req),
	{ok, Req0, undefined};

info({wrong_key, Pid, _}, Req, {poll, Pid, Mon}) ->
	erlang:demonitor(Mon),
	{ok, Req0} = cowboy_http_req:reply(403, Req),
	{ok, Req0, undefined};

info({reply, Pid, Data}, Req, {poll, Pid, Mon}) ->
	erlang:demonitor(Mon),
	{ok, Req0} = cowboy_http_req:reply(200, [], Data, Req),
	{ok, Req0, undefined}.

terminate(_, _) -> ok. 

%% utils

-define(keylen, 8).
generate_key() -> crypto:strong_rand_bytes(?keylen).

try_decode_pid(S) when is_binary(S) ->
	case base64:decode(cowboy_http:urldecode(S)) of
		<<K:?keylen/binary, PidBinary/binary>> ->
			try binary_to_term(PidBinary) of
				P when is_pid(P)	-> {K, P};
				_Other 				-> undefined
			catch _:_ 				-> undefined
			end;
		_Other	-> undefined
	end;
try_decode_pid(_)	-> undefined.

encode_pid(Key, Pid) when is_pid(Pid) and is_binary(Key) ->
	PidBinary = term_to_binary(Pid),
	cowboy_http:urlencode(base64:encode(<<Key/binary, PidBinary/binary>>)).

%% Websocket.

websocket_init(_Transport, Req, Opts) ->
	{handler, Handler} = lists:keyfind(handler, 1, Opts),
	State = #state{handler=Handler},
	case Handler:init(Opts) of
		{ok, HandlerState} ->
			Req0 = cowboy_http_req:compact(Req),
			{ok, Req0, State#state{handler_state=HandlerState}, hibernate};
		{shutdown, _HandlerState} ->
			{shutdown, Req}
	end.

websocket_handle({text, Data}, Req,
		State=#state{handler=Handler, handler_state=HandlerState}) ->
	case Handler:stream(Data, HandlerState) of
		{ok, HandlerState2} ->
			{ok, Req, State#state{handler_state=HandlerState2}, hibernate};
		{reply, Reply, HandlerState2} ->
			{reply, {text, Reply}, Req,
				State#state{handler_state=HandlerState2}, hibernate}
	end;
websocket_handle(_Frame, Req, State) ->
	{ok, Req, State, hibernate}.

websocket_info(Info, Req, State=#state{
		handler=Handler, handler_state=HandlerState}) ->
	case Handler:info(Info, HandlerState) of
		{ok, HandlerState2} ->
			{ok, Req, State#state{handler_state=HandlerState2}, hibernate};
		{reply, Reply, HandlerState2} ->
			{reply, {text, Reply}, Req,
				State#state{handler_state=HandlerState2}, hibernate}
	end.

websocket_terminate(_Reason, _Req,
		#state{handler=Handler, handler_state=HandlerState}) ->
	Handler:terminate(HandlerState).
