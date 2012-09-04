-define(KeyLength, 8).
-define(Secret, <<"xthyjgjgbr">>).

-define(NOREPLY(Req, State), {ok, Req, State}).
-define(REPLY(Msg, Req, State), {reply, Msg, Req, State}).

-define(DBG(F, A), error_logger:info_msg("DBG: ~p:~p ~w:~b:~n" ++ F ++ "~n", [node(), self(), ?MODULE, ?LINE] ++ A)).
-define(DBG(A), error_logger:info_msg("DBG: ~p:~p ~w:~b:~n ~p ~n", [node(), self(), ?MODULE, ?LINE] ++ [A])).

-define(INFO(F, A), error_logger:info_msg("INFO: ~p:~p ~w:~b:~n" ++ F ++ "~n", [node(), self(), ?MODULE, ?LINE] ++ A)).
-define(INFO(A), error_logger:info_msg("INFO: ~p:~p ~w:~b:~n ~p ~n", [node(), self(), ?MODULE, ?LINE] ++ [A])).

-define(ERR(F, A), error_logger:error_msg("ERROR: ~p:~p ~w:~b:~n" ++ F ++ "~n", [node(), self(), ?MODULE, ?LINE] ++ A)).
-define(ERR(A), error_logger:error_msg("ERROR: ~p:~p ~w:~b:~n ~p ~n", [node(), self(), ?MODULE, ?LINE] ++ [A])).

-define(WARN(F, A), error_logger:warning_msg("WARNING: ~p:~p ~w:~b:~n" ++ F ++ "~n", [node(), self(), ?MODULE, ?LINE] ++ A)).
-define(WARN(A), error_logger:warning_msg("WARNING: ~p:~p ~w:~b:~n ~p ~n", [node(), self(), ?MODULE, ?LINE] ++ [A])).

-define(AMQP_HEADER(Header), element(1, Header) =:='basic.deliver').
-define(AMQP_DELYEVERY_TAG(Header), element(3, Header)).
-define(AMQP_EXCHANGE(Header), element(5, Header)).
-define(AMQP_ROUTING_KEY(Header), element(6, Header)).
-define(AMQP_RK_MATCH(Pattern), {'basic.deliver', _, _, _, _, <<Pattern, _/binary>>}).

-type reply() :: ok | {reply, Message :: binary()}.


-define(WS, <<"ws">>).
-define(XHR, <<"xhr">>).

