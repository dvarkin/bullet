%% Feel free to use, reuse and abuse the code in this file.

%% @doc Stream handler for clock synchronizing.
-module(stream_handler).

-export([init/1]).
-export([stream/2]).
-export([info/2]).
-export([terminate/1]).

-define(PERIOD, 1000).

init(_Opts) ->
	io:format("bullet init~n"),
	_ = erlang:send_after(?PERIOD, self(), refresh),
	{ok, undefined}.

stream(<<"ping">>, State) ->
	io:format("ping received~n"),
	{reply, <<"pong">>, State};
stream(Data, State) ->
	io:format("stream received ~s~n", [Data]),
	{ok, State}.

info(refresh, State) ->
	_ = erlang:send_after(?PERIOD, self(), refresh),
	DateTime = cowboy_clock:rfc1123(),
	io:format("clock refresh timeout: ~s~n", [DateTime]),
	{reply, DateTime, State};
info(Info, State) ->
	io:format("info received ~p~n", [Info]),
	{ok, State}.

terminate(_State) ->
	io:format("bullet terminate~n"),
	ok.
