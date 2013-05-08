-module(sysmon).
-export([start/0, stop/0]).

start() ->
    application:start(sysmon).

stop() ->
    application:stop(sysmon).
