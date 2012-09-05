-module(bullet).

-behaviour(application).
-export([start/2, stop/1]).

-behaviour(supervisor).
-export([init/1]).

start(_StartType, _StartArgs) ->
	supervisor:start_link({local, bullet_sup}, ?MODULE, []).

stop(_State) -> ok.

init(_Args) ->
	{ok, {{simple_one_for_one, 100, 1}, 
		[{session, {bullet_xhr_session, start_link, []}, temporary, 1000, worker, []}]}}.
