-module(bullet_xhr_session).
-export([start_link/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
		 terminate/2, code_change/3]).

-record(state, {
	handler ::module(),
	handler_state ::term(),
	key ::binary(),
	timer ::reference(),
	buffer ::binary(),
	poll ::pid()
}).

-define(term, 10).
-define(slash, 92).

start_link(Key, Opts) ->
	gen_server:start_link(?MODULE, {Key, Opts}, []).

init({Key, Opts}) ->
	Handler = proplists:get_value(handler, Opts),
	erlang:put(poll_wait_timeout, proplists:get_value(poll_wait_timeout, Opts, 1000)),
	erlang:put(poll_timeout, proplists:get_value(poll_timeout, Opts, 60000)),

	case Handler:init(Opts) of
		{ok, HandlerState} ->
			{ok, reset_timer(#state{ 
				handler=Handler, handler_state=HandlerState, key = Key, buffer = <<>>}, poll_wait)};

		{shutdown, _HandlerState} -> {stop, normal}
	end.

%% poll wait timeout - close session
handle_info({timeout, Ref, poll_wait}, #state{ timer=Ref } = S) -> {stop, normal, S};

%% poll request with non-matched key
handle_info({poll, K, Pid}, #state{ key = Key } = State)
	when K /= Key -> Pid ! {wrong_key, self(), K}, {noreply, State};

%% same Pid requests poll again - just ignore it
handle_info({poll, _, Pid}, #state{ poll=Pid } = State) ->
	{noreply, State};

%% new poll request
handle_info({poll, _, Pid}, #state{ poll=undefined } = State) ->
	case State#state.buffer of
		<<>>	-> {noreply, reset_timer(State#state{ poll=Pid }, poll)};
		_Data	-> handle_poll_reply(State#state{ poll=Pid })
	end;

%% new poll request when previous still hanging
handle_info({poll, K, Pid}, State) ->
	{noreply, State0} = handle_poll_reply(State),
	handle_info({poll, K, Pid}, State0);

%% poll timeout exceeded
handle_info({timeout, Ref, poll}, #state{ timer=Ref } = State) ->
	handle_poll_reply(State);

%% non-matched timeouts
handle_info({timeout, _, poll_wait}, State) -> {noreply, State};
handle_info({timeout, _, poll}, State) -> {noreply, State};

%% stream received
handle_info({stream, K, Data}, State) ->
	case State#state.key of	%% match key
		K	-> handle_module(stream, Data, State);
		_	-> {noreply, State} 
	end;

%% pass other Info to module
handle_info(Info, State) ->
	handle_module(info, Info, State).

%% handle client module result
handle_module(Fun, Arg, #state{ handler=Handler, poll=Pid, buffer=Buffer } = State) ->
	case erlang:apply(Handler, Fun, [Arg, State#state.handler_state]) of
		{ok, HandlerState0}				-> {noreply, State#state{ handler_state=HandlerState0 }};
		{reply, Reply, HandlerState0} 	->
			Reply0 = escape(iolist_to_binary(Reply)),
			case Pid of
				undefined -> 
					%% no poll - accumulate reply in buffer
					Buffer0 = <<Buffer/binary, ?term, Reply0/binary>>,
					{noreply, State#state{ handler_state=HandlerState0, buffer=Buffer0 }};

				_Pid -> handle_poll_reply(State#state{ handler_state=HandlerState0, buffer=Reply0 })
			end
	end.

%% send poll reply
handle_poll_reply(#state{ poll=Pid, buffer=Data } = State) ->
	Pid ! {reply, self(), Data},
	{noreply, reset_timer(State#state{ poll=undefined, buffer = <<>> }, poll_wait)}.

%% unused:
handle_call(_Req, _From, State) -> {noreply, State}.
handle_cast(_Req, State) -> {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(_, #state{ handler=Handler, handler_state=HandlerState }) ->
	Handler:terminate(HandlerState).

%% utilities:
escape(Data) ->
	binary:replace(binary:replace(Data, <<?slash>>, <<?slash, ?slash>>, [global]), <<?term>>, <<?slash, ?term>>, [global]).

reset_timer(#state{ timer=undefined } = S, poll_wait) -> S#state{ timer=erlang:start_timer(erlang:get(poll_wait_timeout), self(), poll_wait) };
reset_timer(#state{ timer=undefined } = S, poll) 	-> S#state{ timer=erlang:start_timer(erlang:get(poll_timeout), self(), poll) };
reset_timer(#state{ timer=undefined } = S, _) -> S;

reset_timer(#state{ timer=TimerRef } = S, M) ->
	erlang:cancel_timer(TimerRef),
	reset_timer(S#state{ timer=undefined }, M).	


