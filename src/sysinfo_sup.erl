%%%-------------------------------------------------------------------
%%% File    : sysinfo_sup.erl
%%% Description : System status & statistics information.
%%% Author  : physacco
%%% Created : 30 May 2011
%%%-------------------------------------------------------------------
-module(sysinfo_sup).
-vsn("0.1.0").

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([list/0, list/1]).
-export([enable/1, disable/1, call/1, call/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%--------------------------------------------------------------------
-include("sysinfo.hrl").

%%--------------------------------------------------------------------
-define(SERVER, ?MODULE). 
-define(ETS,    sysinfo_services).

%%--------------------------------------------------------------------
-opaque tref() :: {integer(), reference()}.

-record(core, {}).

-type core() :: #core{}.

-record(service, {
    name    :: atom(),
    state   :: tuple(),
    enabled :: boolean(),
    period  :: integer(),
    timer   :: tref(),
    initfun :: function(),
    pollfun :: function(),
    callfun :: function(),
    stopfun :: function()
}).

-type service() :: #service{}.

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {'ok', pid()} | 'ignore' | {'error', any()}.

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Stop the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> 'ok'.

stop() ->
    gen_server:call(?SERVER, stop).

%%--------------------------------------------------------------------
%% @doc
%% List the names of enabled services.
%% @end
%%--------------------------------------------------------------------
-spec list() -> [atom()].

list() ->
    gen_server:call(?SERVER, {list, [enabled]}).

%%--------------------------------------------------------------------
%% @doc
%% List some services according to Options.
%%
%% Spec   list(Options) -> Names | Services.
%%
%% Types  Names = [ atom() ]
%%        Services = [ service() ]
%%        Options = [ Option ]
%%        Option = all | enabled | disabled | detailed
%%
%% About Options
%%   all | enabled | disabled
%%     all: select all services, (all = enabled or disabled)
%%     enabled: select enabled services, this is default
%%     disabled: select disabled services
%%   detailed
%%     return Services if present; otherwise Names is returned
%% @end
%%--------------------------------------------------------------------
-spec list(list()) -> [atom()] | [service()].

list(Options) when is_list(Options) ->
    gen_server:call(?SERVER, {list, Options}).

%%--------------------------------------------------------------------
%% @doc
%% Enable some services.
%% It returns {ok, EnabledServices}.
%% This function is idempotent.
%% @end
%%--------------------------------------------------------------------
-spec enable(atom() | [atom()]) -> {'ok', [atom()]}.

enable(Service) when is_atom(Service) ->
    gen_server:call(?SERVER, {enable, [Service]});
enable(Services) when is_list(Services) ->
    gen_server:call(?SERVER, {enable, Services}).

%%--------------------------------------------------------------------
%% @doc
%% Disable some services.
%% It returns {ok, DisabledServices}.
%% This function is idempotent.
%% @end
%%--------------------------------------------------------------------
-spec disable(atom() | [atom()]) -> {'ok', [atom()]}.

disable(Service) when is_atom(Service) ->
    gen_server:call(?SERVER, {disable, [Service]});
disable(Services) when is_list(Services) ->
    gen_server:call(?SERVER, {disable, Services}).

%%--------------------------------------------------------------------
%% @doc
%% Call the server for some request.
%% Examples:
%%   sysinfo_sup:call(poll).
%% @end
%%--------------------------------------------------------------------
-spec call(any()) -> any().

call(Request) ->
    gen_server:call(?SERVER, {call, Request}).

%%--------------------------------------------------------------------
%% @doc
%% Call a service.
%% It might return:
%%   Reply::term();
%%   {error, {not_found, Service::atom()}};
%%   {error, {bad_request, Request::any()}};
%%   {error, OtherError::any()}.
%% Examples:
%%   sysinfo_sup:call(loadavg, poll).
%%   sysinfo_sup:call(cputime, poll).
%%   sysinfo_sup:call(memfree, poll).
%%   sysinfo_sup:call(diskfree, poll).
%%   sysinfo_sup:call(iostat, poll).
%%   sysinfo_sup:call(netstat, poll).
%% @end
%%--------------------------------------------------------------------
-spec call(atom(), any()) -> any().

call(Service, Request) ->
    gen_server:call(?SERVER, {call, Service, Request}).

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
init([]) ->
    State = i_init(),
    {ok, State}.

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
handle_call({list, Options}, _From, State) ->
    Services = case proplists:get_value(all, Options, false) of
    true ->
        i_list_services(all);
    false ->
        case proplists:get_value(disabled, Options, false) of
        true ->
            case proplists:get_value(enabled, Options, false) of
            true ->
                i_list_services(all);
            false ->
                i_list_services(disabled)
            end;
        false ->
            i_list_services(enabled)
        end
    end,
    Reply = case proplists:get_value(detailed, Options, false) of
    true ->
        Services;
    false ->
        [S#service.name || S <- Services]
    end,
    {reply, Reply, State};

handle_call({enable, Names}, _From, State) ->
    Find = fun(Name) ->
        Condition1 = {'=:=', Name, {element, 2, '$1'}},
        Condition2 = {'=:=', false, {element, 4, '$1'}},
        Condition  = {'andalso', Condition1, Condition2},
        ets:select(?ETS, [{'$1', [Condition], ['$1']}])
    end,
    Services = lists:append([Find(Name) || Name <- Names]),
    i_enable_services(Services),
    Reply = {ok, [S#service.name || S <- Services]},
    {reply, Reply, State};

handle_call({disable, Names}, _From, State) ->
    Find = fun(Name) ->
        Condition1 = {'=:=', Name, {element, 2, '$1'}},
        Condition2 = {'=:=', true, {element, 4, '$1'}},
        Condition  = {'andalso', Condition1, Condition2},
        ets:select(?ETS, [{'$1', [Condition], ['$1']}])
    end,
    Services = lists:append([Find(Name) || Name <- Names]),
    i_disable_services(Services),
    Reply = {ok, [S#service.name || S <- Services]},
    {reply, Reply, State};

handle_call({call, poll}, _From, State) ->
    Reply = i_call_poll(),
    {reply, Reply, State};

handle_call({call, Service, Request}, _From, State) ->
    Reply = i_call_service(Service, Request),
    {reply, Reply, State};

handle_call(stop, _From, State) ->
    Reply = ok,
    {stop, normal, Reply, State};

handle_call(_Request, _From, State) ->
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
handle_cast(_Msg, State) ->
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
handle_info({timeout, Name}, State) ->
    i_poll_service(Name),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

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
terminate(_Reason, _State) ->
    i_stop_services(ets:tab2list(?ETS)),
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
    Services = i_list_services(enabled),
    i_disable_services(Services),
    i_enable_services(Services),
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%--------------------------------------------------------------------
i_builtin_services() ->
    LA = #service{name    = loadavg,
                  state   = undefined,
                  enabled = false,
                  period  = 10000,
                  timer   = undefined,
                  initfun = fun loadavg_init/0,
                  pollfun = fun loadavg_poll/1,
                  callfun = fun loadavg_call/2,
                  stopfun = fun loadavg_stop/1},

    CT = #service{name    = cputime,
                  state   = undefined,
                  enabled = false,
                  period  = 10000,
                  timer   = undefined,
                  initfun = fun cputime_init/0,
                  pollfun = fun cputime_poll/1,
                  callfun = fun cputime_call/2,
                  stopfun = fun cputime_stop/1},

    MF = #service{name    = memfree,
                  state   = undefined,
                  enabled = false,
                  period  = 20000,
                  timer   = undefined,
                  initfun = fun memfree_init/0,
                  pollfun = fun memfree_poll/1,
                  callfun = fun memfree_call/2,
                  stopfun = fun memfree_stop/1},

    DF = #service{name    = diskfree,
                  state   = undefined,
                  enabled = false,
                  period  = 50000,
                  timer   = undefined,
                  initfun = fun diskfree_init/0,
                  pollfun = fun diskfree_poll/1,
                  callfun = fun diskfree_call/2,
                  stopfun = fun diskfree_stop/1},

    IS = #service{name    = iostat,
                  state   = undefined,
                  enabled = false,
                  period  = 10000,
                  timer   = undefined,
                  initfun = fun iostat_init/0,
                  pollfun = fun iostat_poll/1,
                  callfun = fun iostat_call/2,
                  stopfun = fun iostat_stop/1},

    NS = #service{name    = netstat,
                  state   = undefined,
                  enabled = false,
                  period  = 10000,
                  timer   = undefined,
                  initfun = fun netstat_init/0,
                  pollfun = fun netstat_poll/1,
                  callfun = fun netstat_call/2,
                  stopfun = fun netstat_stop/1},

    [LA, CT, MF, DF, IS, NS].

%%--------------------------------------------------------------------
%% gen_server initialization
%%--------------------------------------------------------------------
-spec i_init() -> core().

i_init() ->
    ets:new(?ETS, [set, named_table, {keypos,2}]),
    Services = i_builtin_services(),
    i_start_services(Services),
    #core{}.

%%--------------------------------------------------------------------
%% Start and enable services
%%--------------------------------------------------------------------
-spec i_start_services([service()]) -> [service() | 'false'].

i_start_services(Services) ->
    [i_start_service(S) || S <- Services].

-spec i_start_service(service()) -> service() | 'false'.

i_start_service(Service) ->
    case catch apply(Service#service.initfun, []) of
    {ok, State} ->
        i_enable_service(Service#service{state=State});
    _ ->  %% failed
        false
    end.

%%--------------------------------------------------------------------
%% Enable services
%%--------------------------------------------------------------------
-spec i_enable_services([service()]) -> [service()].

i_enable_services(Services) ->
    [i_enable_service(S) || S <- Services].

-spec i_enable_service(service()) -> service().

i_enable_service(Service) ->
    case Service#service.enabled of
    true ->
        Service;
    false ->
        Name   = Service#service.name,
        Period = Service#service.period,
        {ok,T} = timer:send_interval(Period, {timeout, Name}),
        Record = Service#service{enabled=true, timer=T},
        ets:insert(?ETS, Record),
        Record
    end.

%%--------------------------------------------------------------------
%% Disable services
%%--------------------------------------------------------------------
-spec i_disable_services([service()]) -> [service()].

i_disable_services(Services) ->
    [i_disable_service(S) || S <- Services].

-spec i_disable_service(service()) -> service().

i_disable_service(Service) ->
    case Service#service.enabled of
    true ->
        timer:cancel(Service#service.timer),
        Record = Service#service{enabled=false, timer=undefined},
        ets:insert(?ETS, Record),
        Record;
    false ->
        Service
    end.

%%--------------------------------------------------------------------
%% Disable and stop services
%%--------------------------------------------------------------------
-spec i_stop_services([service()]) -> [service()].

i_stop_services(Services) ->
    [i_stop_service(S) || S <- Services].

-spec i_stop_service(service()) -> service().

i_stop_service(Service) ->
    i_stop_service1(i_disable_service(Service)).

i_stop_service1(Service) ->
    catch apply(Service#service.stopfun, [Service#service.state]),
    ets:delete(?ETS, Service#service.name),
    Service.

%%--------------------------------------------------------------------
i_call_poll() ->
    LoadAvg  = i_call_service(loadavg,  poll),
    CpuTime  = i_call_service(cputime,  poll),
    MemInfo  = i_call_service(memfree,  poll),
    DiskFree = i_call_service(diskfree, poll),
    IOStat   = i_call_service(iostat,   poll),
    NetStat  = i_call_service(netstat,  poll),
    [{loadavg,  LoadAvg},
     {cputime,  CpuTime},
     {memfree,  MemInfo},
     {diskfree, DiskFree},
     {IOStat,   iostat},
     {NetStat,  netstat}].

%%--------------------------------------------------------------------
%% Call service.
%% The callfun of a service should return {reply, Reply, State}.
%%--------------------------------------------------------------------
-spec i_call_service(atom(), term()) -> term().

i_call_service(Name, Request) ->
    case ets:lookup(?ETS, Name) of
    [] ->
        {error, {not_found, Name}};
    [Service] ->
        State = Service#service.state,
        CallFun = Service#service.callfun,
        case catch apply(CallFun, [Request, State]) of
        {reply, Reply, State} ->
            Reply;
        {reply, Reply, NewState} ->
            ets:insert(?ETS, Service#service{state=NewState}),
            Reply;
        {'EXIT', {function_clause, _}} ->
            {error, {bad_request, Request}};
        Error ->
            {error, Error}
        end
    end.

%%--------------------------------------------------------------------
%% Polling
%% The pollfun of a service should return {reply, Reply, State}.
%%--------------------------------------------------------------------
-spec i_poll_service(atom()) -> 'ok' | {'error', any()}.

i_poll_service(Name) ->
    case ets:lookup(?ETS, Name) of
    [] ->
        {error, {not_found, Name}};
    [Service] ->
        State = Service#service.state,
        PollFun = Service#service.pollfun,
        case catch apply(PollFun, [State]) of
        {reply, Reply, NewState} ->
            if NewState =/= State ->
                ets:insert(?ETS, Service#service{state=NewState});
            true ->
                ok
            end,
            i_consume_poll_result(Reply),
            ok;
        Error ->
            {error, Error}
        end
    end.

%%--------------------------------------------------------------------
%% Consume polling result of a serivce.
%% Usually the result is packed and sent to plugin_evtmgr.
%%--------------------------------------------------------------------
i_consume_poll_result({error,_Reason}) ->  % {error,eagain}
    ignore;
i_consume_poll_result({sysinfo,_,_}=Record) ->
    i_consume_poll_result([Record]);
i_consume_poll_result([]) ->
    ignore;
i_consume_poll_result(Records) when is_list(Records) ->
    case hd(Records) of
    {sysinfo, _, KVList} when is_list(KVList) ->
        Msg = {sysinfo_report, self(), Records},

        %% TODO: send the report to a subscriber
        io:format("~p~n", [Msg]);
    _ ->
        ignore
    end;
i_consume_poll_result(_) ->
    ignore.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% List services.
%% Used by handle_call({list, ...}, ...)
%% @end
%%--------------------------------------------------------------------
i_list_services(all) ->
    ets:tab2list(?ETS);
i_list_services(enabled) ->
    Condition = {'=:=', true, {element, 4, '$1'}},
    ets:select(?ETS, [{'$1', [Condition], ['$1']}]);
i_list_services(disabled) ->
    Condition = {'=:=', false, {element, 4, '$1'}},
    ets:select(?ETS, [{'$1', [Condition], ['$1']}]).

%%%===================================================================
%%% Services
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 1: loadavg
%% @end
%%--------------------------------------------------------------------
-record(loadavg_core, {pollnum}).

loadavg_init() ->
    {ok, #loadavg_core{pollnum=0}}.

%% The Return value is {reply, Reply, NewState}.
%% Reply is a record contains Plugin, Service, and data fields.
%% Sample Reply:
%%  {sysinfo,loadavg,
%%           [{avg1,{real,0.17}},
%%            {avg5,{real,0.11}},
%%            {avg15,{real,0.03}},
%%            {prun,{int,4}},
%%            {ptot,{int,386}},
%%            {plast,{int,10019}},
%%            {ctime,{time,{{2011,9,27},{8,7,27}}}}]}
loadavg_poll(State) ->
    {ok, LoadAvg} = sysinfo:loadavg_raw(),
    CTime  = calendar:universal_time(),
    Record = [{avg1,  LoadAvg#loadavg_raw.avg1},
              {avg5,  LoadAvg#loadavg_raw.avg5},
              {avg15, LoadAvg#loadavg_raw.avg15},
              {prun,  LoadAvg#loadavg_raw.prun},
              {ptot,  LoadAvg#loadavg_raw.ptot},
              {plast, LoadAvg#loadavg_raw.plast},
              {ctime, CTime}],
    Reply   = {sysinfo, loadavg, Record},
    PollNum = State#loadavg_core.pollnum + 1,
    {reply, Reply, State#loadavg_core{pollnum=PollNum}}.

loadavg_call(poll, State) ->
    loadavg_poll(State).

loadavg_stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 2: cputime
%% @end
%%--------------------------------------------------------------------
-record(cputime_core, {pollnum, prev, poll}).

cputime_init() ->
    {ok, #cputime_core{pollnum=0, prev=undefined, poll={error,eagain}}}.

cputime_poll(State) ->
    CpuTimeLY = sysinfo:cpustats(),
    case State#cputime_core.prev of
    undefined ->
        Reply = {error, eagain},
        NewState = State#cputime_core{prev=CpuTimeLY},
        {reply, Reply, NewState};
    CpuTimeLX ->
        Diffs    = sysinfo:cpustats_diff(CpuTimeLY, CpuTimeLX),
        ETag     = generate_etag(),
        CTime    = calendar:universal_time(),
        Reply    = [cputime_mkrecord(Cpu, ETag, CTime) || Cpu <- Diffs],
        PollNum  = State#cputime_core.pollnum + 1,
        NewState = State#cputime_core{pollnum=PollNum, prev=CpuTimeLY, poll=Reply},
        {reply, Reply, NewState}
    end.

cputime_mkrecord(CpuTimeDiff, ETag, CTime) ->
    {Kind, CpuTime} = CpuTimeDiff,
    CpuId = if Kind =:= all -> -1; true -> Kind end,
    Record = [{cpu,   CpuId},
              {user,  CpuTime#cputime.us},
              {sys,   CpuTime#cputime.sy},
              {nice,  CpuTime#cputime.ni},
              {idle,  CpuTime#cputime.id},
              {wait,  CpuTime#cputime.wa},
              {hirq,  CpuTime#cputime.hi},
              {sirq,  CpuTime#cputime.si},
              {steal, CpuTime#cputime.st},
              {etag,  ETag},
              {ctime, CTime}],
    {sysinfo, cputime, Record}.


cputime_call(poll, State) ->
    {reply, State#cputime_core.poll, State}.

cputime_stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 3: memfree
%% @end
%%--------------------------------------------------------------------
-record(memfree_core, {pollnum}).

memfree_init() ->
    {ok, #memfree_core{pollnum=0}}.

memfree_poll(State) ->
    MemInfo = sysinfo:memfree(),
    CTime   = calendar:universal_time(),
    Record  = [{mem_total,   MemInfo#meminfo.mem_total},
               {mem_free,    MemInfo#meminfo.mem_free},
               {mem_buffers, MemInfo#meminfo.mem_buffers},
               {mem_cached,  MemInfo#meminfo.mem_cached},
               {swap_total,  MemInfo#meminfo.swap_total},
               {swap_free,   MemInfo#meminfo.swap_free},
               {ctime,       CTime}],
    Reply   = {sysinfo, memfree, Record},
    PollNum = State#memfree_core.pollnum + 1,
    {reply, Reply, State#memfree_core{pollnum=PollNum}}.

memfree_call(poll, State) ->
    memfree_poll(State).

memfree_stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 4: diskfree
%% @end
%%--------------------------------------------------------------------
-record(diskfree_core, {pollnum}).

diskfree_init() ->
    {ok, #diskfree_core{pollnum=0}}.

diskfree_poll(State) ->
    DiskFree = sysinfo:diskfree(),
    ETag     = generate_etag(),
    CTime    = calendar:universal_time(),
    Reply    = [diskfree_mkrecord(DI, ETag, CTime) || DI <- DiskFree],
    PollNum  = State#diskfree_core.pollnum + 1,
    {reply, Reply, State#diskfree_core{pollnum=PollNum}}.

diskfree_mkrecord(DI, ETag, CTime) ->
    Record = [{fs,    DI#diskinfo.fs},
              {type,  DI#diskinfo.type},
              {size,  DI#diskinfo.size},
              {used,  DI#diskinfo.used},
              {free,  DI#diskinfo.free},
              {pct,   DI#diskinfo.pct},
              {mnt,   DI#diskinfo.mnt},
              {etag,  ETag},
              {ctime, CTime}],
    {sysinfo, diskfree, Record}.

diskfree_call(poll, State) ->
    diskfree_poll(State).

diskfree_stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 5: iostat
%% @end
%%--------------------------------------------------------------------
-record(iostat_core, {pollnum, prev, poll}).

iostat_init() ->
    {ok, #iostat_core{pollnum=0, prev=undefined, poll={error,eagain}}}.

iostat_poll(State) ->
    DiskStatsLY = sysinfo:diskstats(),
    ETag = generate_etag(),
    DiskStats = [iostat_mkrecord_diskstats(D, ETag) || D <- DiskStatsLY],
    Reply = case State#iostat_core.prev of
    undefined ->
        DiskStats;
    DiskStatsLX ->
        Diffs = sysinfo:iostat(DiskStatsLY, DiskStatsLX),
        IOStat = [iostat_mkrecord_iostat(D, ETag) || D <- Diffs],
        lists:append(DiskStats, IOStat)
    end,
    PollNum = State#iostat_core.pollnum + 1,
    NewState = State#iostat_core{pollnum=PollNum, prev=DiskStatsLY, poll=Reply},
    {reply, Reply, NewState}.

iostat_mkrecord_diskstats(DiskStats, ETag) ->
    DevName = atom_to_list(DiskStats#diskstats.dev_name),
    CTime = calendar:now_to_universal_time(DiskStats#diskstats.timestamp),
    Record = [{dev_name,   DevName},
              {rd_ios,     DiskStats#diskstats.rd_ios},
              {rd_merges,  DiskStats#diskstats.rd_merges},
              {rd_secs,    DiskStats#diskstats.rd_secs},
              {rd_ticks,   DiskStats#diskstats.rd_ticks},
              {wr_ios,     DiskStats#diskstats.wr_ios},
              {wr_merges,  DiskStats#diskstats.wr_merges},
              {wr_secs,    DiskStats#diskstats.wr_secs},
              {wr_ticks,   DiskStats#diskstats.wr_ticks},
              {ios_pgr,    DiskStats#diskstats.ios_pgr},
              {tot_ticks,  DiskStats#diskstats.tot_ticks},
              {rq_ticks,   DiskStats#diskstats.rq_ticks},
              {etag,       ETag},
              {ctime,      CTime}],
    {sysinfo, diskstats, Record}.

iostat_mkrecord_iostat(IOStat, ETag) ->
    DevName = atom_to_list(IOStat#iostat.dev_name),
    CTime = calendar:now_to_universal_time(IOStat#iostat.timestamp),
    Record = [{dev_name,   DevName},
              {tps,        IOStat#iostat.tps},
              {rd_secs_ps, IOStat#iostat.rd_secs_ps},
              {wr_secs_ps, IOStat#iostat.wr_secs_ps},
              {rd_secs,    IOStat#iostat.rd_secs},
              {wr_secs,    IOStat#iostat.wr_secs},
              {etag,       ETag},
              {ctime,      CTime}],
    {sysinfo, iostat, Record}.

iostat_call(poll, State) ->
    {reply, State#iostat_core.poll, State}.

iostat_stop(_State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Service 5: netstat
%% @end
%%--------------------------------------------------------------------
-record(netstat_core, {pollnum, prev, poll}).

netstat_init() ->
    {ok, #netstat_core{pollnum=0, prev=undefined, poll={error,eagain}}}.

netstat_poll(State) ->
    IfStatsLY = sysinfo:ifstats_all(),
    ETag = generate_etag(),
    IfStats = [netstat_mkrecord_ifstats(I, ETag) || I <- IfStatsLY],
    Reply = case State#netstat_core.prev of
	undefined  ->
	    IfStats;
	IfStatsLX ->
	    Diffs = sysinfo:netstat(IfStatsLY, IfStatsLX),
	    NetStat = [netstat_mkrecord_netstat(I, ETag) || I <- Diffs],
	    lists:append(IfStats, NetStat)
    end,
    PollNum = State#netstat_core.pollnum + 1,
    NewState = State#netstat_core{pollnum=PollNum, prev=IfStatsLY, poll=Reply},
    {reply, Reply, NewState}.

netstat_mkrecord_ifstats(IfStats, ETag) ->
    DevName = atom_to_list(IfStats#ifstats.dev_name),
    CTime = calendar:now_to_universal_time(IfStats#ifstats.timestamp),
    Record = [{dev_name,   DevName},
              {rx_bytes,   IfStats#ifstats.rx_bytes},
              {tx_bytes,   IfStats#ifstats.tx_bytes},
              {rx_packets, IfStats#ifstats.rx_packets},
              {tx_packets, IfStats#ifstats.tx_packets},
              {rx_errors,  IfStats#ifstats.rx_errors},
              {tx_errors,  IfStats#ifstats.tx_errors},
              {rx_dropped, IfStats#ifstats.rx_dropped},
              {tx_dropped, IfStats#ifstats.tx_dropped},
              {etag,       ETag},
              {ctime,      CTime}],
    {sysinfo, ifstats, Record}.

netstat_mkrecord_netstat(NetStat, ETag) ->
    DevName = atom_to_list(NetStat#netstat.dev_name),
    CTime = calendar:now_to_universal_time(NetStat#netstat.timestamp),
    Record = [{dev_name,   DevName},
              {rx_bps,     NetStat#netstat.rx_bps},
              {tx_bps,     NetStat#netstat.tx_bps},
              {rx_pps,     NetStat#netstat.rx_pps},
              {tx_pps,     NetStat#netstat.tx_pps},
              {etag,       ETag},
              {ctime,      CTime}],
    {sysinfo, netstat, Record}.

netstat_call(poll, State) ->
    netstat_poll(State).

netstat_stop(_State) ->
    ok.

%%%===================================================================
%%% helper functions
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Generate a random integer between 1 and (2^32 - 1).
%% ETag is a 32-bit unsigned integer.
%% @end
%%--------------------------------------------------------------------
-spec generate_etag() -> integer().

generate_etag() ->
    random:uniform(4294967295).
