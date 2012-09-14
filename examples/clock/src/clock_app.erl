%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(clock_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).

%% API.

start(_Type, _Args) ->
	Port = case application:get_env(clock, port) of
		undefined	-> application:set_env(clock, port, 8000), 8000;
		{ok, V}		-> V
	end,
	Dispatch = [
		{'_', [
			{[], toppage_handler, []},
			{[<<"bullet">>], bullet_handler, [{handler, stream_handler}]},
			{[<<"static">>, '...'], cowboy_http_static, [
				{directory, {priv_dir, bullet, []}},
				{mimetypes, [
					{<<".js">>, [<<"application/javascript">>]}
				]}
			]}
		]}
	],
	{ok, _} = cowboy:start_listener(http, 100,
		cowboy_tcp_transport, [{port, Port}],
		cowboy_http_protocol, [{dispatch, Dispatch}]
	),
	clock_sup:start_link().

stop(_State) ->
	ok.
