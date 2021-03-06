%%%-------------------------------------------------------------------
%%% @author benoitc
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Jul 2017 12:23
%%%-------------------------------------------------------------------
-module(barrel_id_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).


-export([init/1]).

-define(ALLOWABLE_DOWNTIME, 2592000000).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).


init([]) ->
  AllowableDowntime = application:get_env(barrel, ts_allowable_downtime, ?ALLOWABLE_DOWNTIME),
  {ok, LastTs} = barrel_ts:read_timestamp(),
  Now = barrel_ts:curr_time_millis(),
  TimeSinceLastRun = Now - LastTs,
  
  _ = lager:debug(
    "timestamp: now: ~p, last: ~p, delta: ~p~n, allowable_downtime: ~p",
    [Now, LastTs, TimeSinceLastRun, AllowableDowntime]
  ),
  
  %% restart if we detected a clock change
  ok = check_for_clock_error(Now >= LastTs, TimeSinceLastRun < AllowableDowntime),
  
  PersistTimeServer = #{
    id => persist_time_server,
    start => {barrel_ts, start_link, []},
    restart => permanent,
    shutdown => 5000,
    type => worker,
    modules => [barrel_flake_ts]
  },
  
  IdServer = #{
    id => server,
    start => {barrel_id, start_link, []},
    restart => permanent,
    shutdown => 5000,
    type => worker,
    modules => [barrel_flake]
  },
  
  SupFlags = #{ strategy => one_for_one, intensity => 10, period => 10},
  {ok, {SupFlags, [PersistTimeServer, IdServer]}}.


check_for_clock_error(true, true) -> ok;
check_for_clock_error(false, _) ->
  _ = lager:error(
    "~s: system running backwards, failing startup of flake service~n",
    [?MODULE_STRING]
  ),
  exit(clock_running_backwards);
check_for_clock_error(_, false) ->
  _ = lager:error(
    "~s: system clock too far advanced, failing startup of snowflake service~n",
    [?MODULE_STRING]
  ),
  exit(clock_advanced).