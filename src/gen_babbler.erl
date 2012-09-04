%%%-------------------------------------------------------------------
%%% @author dem <dvarkin@gmail.com>
%%% @copyright (C) 2012, dem
%%% @doc
%%%
%%% @end
%%% Created : 23 Jun 2012 by dem <dvarkin@gmail.com>
%%%-------------------------------------------------------------------
-module(gen_babbler).

-include("include/babbler.hrl").

-behaviour(gen_server).

-export([behaviour_info/1]).

%% API

-export([start/3, req/2, send/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
		 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {module :: atom(),
				mstate :: term(),
				mqueue = [],
				mpid :: pid(),
				keep_alive :: pid(),
				is_ws :: boolean(),
				stat_fun :: function(),
				system_queue = []:: list()
			   }
	   ).


behaviour_info(callbacks) ->
    [{init, 0}, {handle_request, 2}, {handle_message, 2}, {info, 2}, {terminate, 2}];
behaviour_info(_) ->
    undefined.

%%%===================================================================
%%% API
%%%===================================================================

start(Module, MPid, Active) ->
	gen_server:start(?SERVER, [Module, MPid, Active], []).

req(Pid, Args) ->
	gen_server:call(Pid, {req, Args}).

send(Pid, Msg) ->
	gen_server:cast(Pid, {send, Msg}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Module, Pid, Active]) ->
	case Module:init() of
		 {ok, MState} ->
%			?DBG("init with ~p pid", [Pid]),
			Stat = babbler:envdef(system_stat, false),
			Ws = babbler_tools:transport(Active),
			StatFunction = send_alive(Ws, Stat),
			AliveInterval = babbler:envdef(alive_interval, 20000),
			timer:send_interval(AliveInterval, alive),
			KL = start_keep_alive(),
%			SystemExchange = babbler:envdef(stat_exchange, <<"system">>),
%			SystemRk = <<"alive.ping">>,
%			{ok, System} = mq:subscribe(SystemExchange, SystemRk, self()),
			State = #state{stat_fun = StatFunction, module = Module, mstate = MState, mqueue = [], mpid = Pid, is_ws = Ws, keep_alive = KL, system_queue = []},
			{ok, State};
		Any ->
			?ERR(Any),
			{stop, Any}
	end;
init(Any) -> {stop, Any}.



%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({req, Args}, {_From,_}, #state{module = Module, mstate =  MState} = State) ->
	{Reply, NewState} = Module:handle_request(Args, MState),
	{reply, Reply, State#state{mstate = NewState}};
handle_call(_Request, _From, State) ->
	?ERR([_Request, State]),
	Reply = ok,
	{reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({send, Msg}, #state{mpid = Pid} = State) ->
	send_message(Pid, Msg, undefined),
	{noreply, State};
handle_cast(_Msg, State) ->
	?ERR(_Msg),
	{noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'basic.consume_ok', _}, State) ->
	{noreply, State};
handle_info({'basic.cancel_ok', _}, State) ->
	{noreply, State};
handle_info(alive, #state{mpid = Pid , is_ws = _Ws} = State) ->
	YesFun = fun() -> {noreply, State} end,
	NoFun = fun() ->  {stop, normal, State} end, %%%% STOP SIGNAL!!!
	babbler_tools:exec_if_alive(Pid, YesFun, NoFun);

handle_info({_Header,{amqp_msg, _, <<"ping">>}}, #state{stat_fun = F} = State) ->
	F(),
	{noreply, State};
handle_info({Header,{amqp_msg, _, Message}}, #state{module = Module, mstate = Mstate, mpid = Pid} = State) when ?AMQP_HEADER(Header) ->
	Exchange = ?AMQP_EXCHANGE(Header),
	Rk = ?AMQP_ROUTING_KEY(Header),
	case Module:handle_message({Exchange, Rk, Message}, Mstate) of
		{ok, NewState} ->
			{noreply, State#state{mstate = NewState}};
		{reply, Msg, NewState} ->
			send_message(Pid, Msg, {store_message, Msg}),
			{noreply, State#state{mstate = NewState}}
	end;

%% if not POST
handle_info({init, Pid, Active}, #state{mqueue = []} = State) when Active == once orelse Active == true ->
	{noreply, State#state{mpid = Pid}};
handle_info({init, Pid, Active}, #state{mqueue = [_ | _] } = State) when Active == once orelse Active == true ->
	Messages = [babbler_tools:json_decode(M) ||
				   M <- lists:reverse(State#state.mqueue), babbler_tools:is_json(M)],
%	?DBG("send message from queue ~p", [Message]),
	Json = babbler_tools:json_encode([{pkg, Messages}]),
	send_message(Pid, Json, undefined),
	{noreply, State#state{mpid = Pid, mqueue = []}};
handle_info({store_message, Msg}, #state{mqueue = Queue} = State) ->
%	?DBG("store message ~p", [Msg]),
	{noreply, State#state{mqueue = cache_filter(Msg ,  Queue)}};
handle_info(skip_keep_alive, #state{keep_alive = Ref} = State) ->
	timer:cancel(Ref),
	{ok, KL} = start_keep_alive(),
	{noreply, State#state{keep_alive = KL}};
handle_info(keep_alive, #state{mpid = Pid} = State) ->
	Msg = keep_alive_msg(),
	send_message(Pid, Msg, undefined),
	{noreply, State};
handle_info(Msg, #state{module = Module, mstate = MState} = State) ->
	{noreply, State#state{mstate = Module:info(Msg, MState)}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(Reason, #state{module = Module, mstate = MState, stat_fun = _F, system_queue = Queue}) ->
	Module:terminate(Reason, MState),
	[mq:unsubscribe(Q) || Q <- Queue],
	ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%send_message(Pid, Message, _) -> Pid ! {send, Message}.
send_message(Pid, Message, undefined) ->
	YesFun = fun() -> self() ! skip_keep_alive,
					  Pid ! {send, Message} end,
	NoFun  = fun() -> ok  end,
	babbler_tools:exec_if_alive(Pid, YesFun, NoFun);
send_message(Pid, Message, Noevent) ->
	YesFun = fun() ->
					 self() ! skip_keep_alive,
					 Pid ! {send, Message} end,
	NoFun  = fun() -> self() ! Noevent  end,
	babbler_tools:exec_if_alive(Pid, YesFun, NoFun).

keep_alive_msg() ->
	T = calendar:datetime_to_gregorian_seconds(erlang:localtime()),
	babbler_tools:json_encode([{ts, T}]).
	
start_keep_alive() ->
	KeepAliveInterval = babbler:envdef(keep_alive_interval, 10000),
	timer:send_after(KeepAliveInterval, keep_alive).

send_alive(Transport, true) ->
	alive(Transport);
send_alive(_, _) -> alive(false).


alive(false) -> fun() -> false end;
alive(Ws) ->
	Plist = [{pid, pid_to_list(self())}, {ws, Ws}, {node, atom_to_binary(node(), latin1)}],
	Msg = babbler_tools:json_encode(Plist),
	Exchange = babbler:envdef(stat_exchange, <<"system">>),
	Rk = babbler:envdef(stat_route_key, <<"alive">>),
	F = fun() ->
				mq:send(Exchange, Rk, Msg) end,
	F(),
	F.
			
cache_filter(Message, Queue) ->
	case lists:member(Message, Queue) of
		true ->
			Queue;
		false ->
			[Message | Queue]
	end.
