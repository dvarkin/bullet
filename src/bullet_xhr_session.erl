%%%-------------------------------------------------------------------
%%% @author dem <dvarkin@gmail.com>
%%% @copyright (C) 2012, dem
%%% @doc
%%%
%%% @end
%%% Created : 23 Jun 2012 by dem <dvarkin@gmail.com>
%%%-------------------------------------------------------------------
-module(bullet_xhr_session).

-include("include/bullet.hrl").

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
				keep_alive :: pid()
			   }
	   ).

behaviour_info(callbacks) ->
    [{init, 1}, {stream, 2}, {info, 2}, {terminate, 1}];
behaviour_info(_) ->
    undefined.

%%%===================================================================
%%% API
%%%===================================================================

start(Module, MPid, Opts) ->
	gen_server:start(?SERVER, [Module, MPid, Opts], []).

req(Pid, Args) ->
	gen_server:call(Pid, {req, Args}).

send(Pid, Msg) ->
	gen_server:cast(Pid, {send, Msg}).


init([Module, Pid, Opts]) ->
	case Module:init(Opts) of
		 {ok, MState} ->
			TRef = start_keep_alive(),
			State = #state{module = Module, mstate = MState, mqueue = [], mpid = Pid, keep_alive = TRef},
			{ok, State};
		Any ->
			?ERR(Any),
			{stop, Any}
	end;
init(Any) -> {stop, Any}.


handle_call({req, Args}, {_From,_}, #state{module = Module, mstate =  MState} = State) ->
	{Reply, NewState} = Module:stream(Args, MState),
	{reply, Reply, State#state{mstate = NewState}};
handle_call(_Request, _From, State) ->
	?ERR([_Request, State]),
	Reply = ok,
	{reply, Reply, State}.

handle_cast({send, Msg}, #state{mpid = Pid} = State) ->
	send_message(Pid, Msg),
	{noreply, State};
handle_cast(_Msg, State) ->
	?ERR(_Msg),
	{noreply, State}.

handle_info(alive, #state{mpid = Pid } = State) ->
	YesFun = fun() -> {noreply, State} end,
	NoFun = fun() ->  {stop, normal, State} end, %%%% STOP SIGNAL!!!
	babbler_tools:exec_if_alive(Pid, YesFun, NoFun);

%% if not POST
handle_info({init, Pid, _Opts}, #state{mqueue = []} = State) ->
	{noreply, State#state{mpid = Pid}};

handle_info({init, Pid, _Opts}, #state{mqueue = [_ | _] } = State) ->

	%%%% SEND MESSAGE FROM QUEUE
	Json = bulltet_tools:split(State#state.mqueue), %% UNREAL FUNCTION
	send_message(Pid, Json),
	{noreply, State#state{mpid = Pid, mqueue = []}};
handle_info({store_message, Msg}, #state{mqueue = Queue} = State) ->
%	?DBG("store message ~p", [Msg]),
	{noreply, State#state{mqueue = [Msg |  Queue]}};
handle_info(skip_keep_alive, #state{keep_alive = Ref} = State) ->
	timer:cancel(Ref),
	{ok, KL} = start_keep_alive(),
	{noreply, State#state{keep_alive = KL}};
handle_info(keep_alive, #state{mpid = Pid, keep_alive = Ref} = State) ->
	Msg = keep_alive_msg(),
	send_message(Pid, Msg),
	timer:cancel(Ref),
	TRef = start_keep_alive(),
	{noreply, State#state{keep_alive = TRef}};
handle_info(Msg, #state{module = Module, mstate = MState} = State) ->
	{noreply, State#state{mstate = Module:info(Msg, MState)}}.

terminate(_Reason, #state{module = Module, mstate = MState}) ->
	Module:terminate(MState),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%send_message(Pid, Message) -> Pid ! {send, Message}.
send_message(Pid, Message) ->
	YesFun = fun() -> self() ! skip_keep_alive,
					  Pid ! {send, Message} end,
	NoFun  = fun() -> ok  end,
	babbler_tools:exec_if_alive(Pid, YesFun, NoFun).

keep_alive_msg() ->
	T = calendar:datetime_to_gregorian_seconds(erlang:localtime()),
	babbler_tools:json_encode([{ts, T}]).
	
start_keep_alive() ->
	KeepAliveInterval = babbler:envdef(keep_alive_interval, 10000),
	timer:send_after(KeepAliveInterval, keep_alive).
