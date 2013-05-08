%%%-------------------------------------------------------------------
%%% File    : sysinfo.erl
%%% Description : System status & statistics information.
%%% Author  : physacco
%%% Created : 23 May 2011
%%%-------------------------------------------------------------------
-module(sysinfo).
-vsn("0.2.0").

-export([kvsn/0]).
-export([loadavg/0, avg1/0, avg5/0, avg15/0, nprocs/0, loadavg_raw/0]).
-export([uptime/0, uptime_hum/0, uptime_raw/0]).
-export([stat_raw/0, cpustats/0, cpustats/1, cpustats_diff/2, cpustats_util/2,
         cputime_util/1, cputime_util/2, cputime_diff/2]).
-export([memfree/0]).
-export([diskfree/0]).
-export([is_device/1, diskstats/0, iostat/2]).
-export([net_devices/0, ifstats/1, ifstats/2, ifstats_all/0,
         ifstats_all_but_lo/0, netstat/2]).

-include("sysinfo.hrl").

%%%===================================================================
%%% API functions
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Return the Linux kernel version.
%% @end
%%--------------------------------------------------------------------
-spec kvsn() -> string() | {'error', any()}.

kvsn() ->
    case read_file(?PathVersion) of
    {ok, Data} ->
        case re:run(Data, "^Linux version (.*?) ",
                    [{capture, all_but_first, list}]) of
        {match, [Vsn|_]} ->
            Vsn;
        nomatch ->
            {error, {badarg, Data}}
        end;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec loadavg() -> {'ok', loadavg()} | {'error', any()}.

loadavg() ->
    case loadavg_raw() of
    {ok, #loadavg_raw{avg1=Avg1, avg5=Avg5, avg15=Avg15}} ->
        {ok, #loadavg{avg1=Avg1, avg5=Avg5, avg15=Avg15}};
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec avg1() -> float() | {'error', any()}.

avg1() ->
    case loadavg_raw() of
    {ok, #loadavg_raw{avg1=Avg1}} ->
        Avg1;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec avg5() -> float() | {'error', any()}.

avg5() ->
    case loadavg_raw() of
    {ok, #loadavg_raw{avg5=Avg5}} ->
        Avg5;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec avg15() -> float() | {'error', any()}.

avg15() ->
    case loadavg_raw() of
    {ok, #loadavg_raw{avg15=Avg15}} ->
        Avg15;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec nprocs() -> integer() | {'error', any()}.

nprocs() ->
    case loadavg_raw() of
    {ok, #loadavg_raw{ptot=PTot}} ->
        PTot;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% loadavg_raw
%%   Read /proc/loadavg and return its content as a #loadavg_raw{}.
%% /proc/loadavg
%%   The first three fields in this file are load average figures
%%   giving the number of jobs in the run queue (state R) or waiting
%%   for disk I/O (state D) averaged over 1, 5, and 15 minutes. They
%%   are the same as the load average numbers given by uptime(1) and
%%   other programs. The fourth field consists of two numbers 
%%   separated by a slash (/). The first of these is the number of
%%   currently executing kernel scheduling entities (processes,
%%   threads); this will be less than or equal to the number of CPUs.
%%   The value after the slash is the number of kernel scheduling
%%   entities that currently exist on the system. The fifth field is
%%   the PID of the process that was most recently created on the system.
%% Sample:
%%   0.02 0.01 0.00 3/336 6586
-spec loadavg_raw() -> {'ok', loadavg_raw()} | {'error', any()}.

loadavg_raw() ->
    case read_file(?PathLoadAvg) of
    {ok, Data} ->
        % An example of Data:
        %   <<"0.02 0.01 0.00 3/336 6586\n">>
        {ok, [Avg1, Avg5, Avg15, PRun, PTot, PLast], _} =
            io_lib:fread("~f ~f ~f ~d/~d ~d", binary_to_list(Data)),
        {ok, #loadavg_raw{avg1=Avg1, avg5=Avg5, avg15=Avg15,
                          prun=PRun, ptot=PTot, plast=PLast}};
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Return uptime as a float number.
%% @end
%%--------------------------------------------------------------------
-spec uptime() -> float() | {'error', any()}.

uptime() ->
    case uptime_raw() of
    {ok, #uptime_raw{uptime=Uptime}} ->
        Uptime;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Return uptime as a #uptime{}.
%% @end
%%--------------------------------------------------------------------
-spec uptime_hum() -> {'ok', uptime()} | {'error', any()}.

uptime_hum() ->
    case uptime_raw() of
    {ok, #uptime_raw{uptime=Uptime}} ->
        {ok, convert_uptime(Uptime)};
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Return uptime and idletime by reading /proc/uptime.
%% @end
%%--------------------------------------------------------------------
-spec uptime_raw() -> {'ok', uptime_raw()} | {'error', any()}.

uptime_raw() ->
    case read_file(?PathUptime) of
    {ok, Data} ->
        % An example of Data:
        %   <<"40721.48 64590.47\n">>
        {ok, [Uptime, IdleTime], _} = 
            io_lib:fread("~f ~f", binary_to_list(Data)),
        {ok, #uptime_raw{uptime=Uptime, idletime=IdleTime}};
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Convert uptime in seconds to human-readable format.
%% Used by uptime_hum/0.
%% @end
%%--------------------------------------------------------------------
-spec convert_uptime(integer() | float()) -> uptime().

convert_uptime(Uptime) when is_integer(Uptime) ->
    Days  = Uptime div 86400,
    Hours = Uptime rem 86400 div 3600,
    Mins  = Uptime rem 3600 div 60,
    Secs  = Uptime rem 60,
    #uptime{day=Days, hour=Hours, minute=Mins, second=Secs};
convert_uptime(Uptime) when is_float(Uptime) ->
    convert_uptime(round(Uptime)).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec cpustats() -> [tuple()] | {'error', any()}.

cpustats() ->
    case stat_raw() of
    TupList when is_list(TupList) ->
        case lists:keyfind(cpu, 1, TupList) of
        {cpu, CpuTimes} ->
            CpuTimes;
        false ->
            {error, unavailable}
        end;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec cpustats(atom() | integer()) -> cputime() | {'error', any()}.
cpustats(Key) ->
    case cpustats() of
    TupList when is_list(TupList) ->
        case lists:keyfind(Key, 1, TupList) of
        {Key, CpuTime} ->
            CpuTime;
        false ->
            {error, unavailable}
        end;
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
cpustats_diff(CpuTimeLY, CpuTimeLX) ->
    cpustats_diff_loop(CpuTimeLY, CpuTimeLX, []).

cpustats_diff_loop([], _, Matched) ->
    lists:reverse(Matched);
cpustats_diff_loop([{Key, CpuTimeY}|T], CpuTimeLX, Matched) ->
    case lists:keytake(Key, 1, CpuTimeLX) of
    {value, {Key, CpuTimeX}, Remainder} ->
        CpuTimeDiff = cputime_diff(CpuTimeY, CpuTimeX),
        cpustats_diff_loop(T, Remainder, [{Key, CpuTimeDiff}|Matched]);
    false ->
        cpustats_diff_loop(T, CpuTimeLX, Matched)
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec cpustats_util([tuple()], [tuple()]) -> [tuple()].

cpustats_util(CpuTimeLY, CpuTimeLX) ->
    cpustats_util_loop(CpuTimeLY, CpuTimeLX, []).

cpustats_util_loop([], _, Matched) ->
    lists:reverse(Matched);
cpustats_util_loop([{Key, CpuTimeY}|T], CpuTimeLX, Matched) ->
    case lists:keytake(Key, 1, CpuTimeLX) of
    {value, {Key, CpuTimeX}, Remainder} ->
        CpuUtil = cputime_util(CpuTimeY, CpuTimeX),
        cpustats_util_loop(T, Remainder, [{Key, CpuUtil}|Matched]);
    false ->
        cpustats_util_loop(T, CpuTimeLX, Matched)
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec cputime_util(cputime()) -> cputime_util().

cputime_util(CpuTime) ->
    Us = CpuTime#cputime.us,
    Sy = CpuTime#cputime.sy,
    Ni = CpuTime#cputime.ni,
    Id = CpuTime#cputime.id,
    Wa = CpuTime#cputime.wa,
    Hi = CpuTime#cputime.hi,
    Si = CpuTime#cputime.si,
    St = CpuTime#cputime.st,
    Total = Us + Sy + Ni + Id + Wa + Hi + Si + St,
    #cputime_util{
        us = Us / Total,
        sy = Sy / Total,
        ni = Ni / Total,
        id = Id / Total,
        wa = Wa / Total,
        hi = Hi / Total,
        si = Si / Total,
        st = St / Total}.

-spec cputime_util(cputime(), cputime()) -> cputime_util().

cputime_util(CpuTimeY, CpuTimeX) ->
    cputime_util(cputime_diff(CpuTimeY, CpuTimeX)).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec cputime_diff(cputime(), cputime()) -> cputime().

cputime_diff(CpuTimeY, CpuTimeX) ->
    #cputime{
        us = CpuTimeY#cputime.us - CpuTimeX#cputime.us,
        sy = CpuTimeY#cputime.sy - CpuTimeX#cputime.sy,
        ni = CpuTimeY#cputime.ni - CpuTimeX#cputime.ni,
        id = CpuTimeY#cputime.id - CpuTimeX#cputime.id,
        wa = CpuTimeY#cputime.wa - CpuTimeX#cputime.wa,
        hi = CpuTimeY#cputime.hi - CpuTimeX#cputime.hi,
        si = CpuTimeY#cputime.si - CpuTimeX#cputime.si,
        st = CpuTimeY#cputime.st - CpuTimeX#cputime.st}.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec stat_raw() -> [tuple()] | {'error', any()}.

stat_raw() ->
    case read_lines(?PathStat) of
    {ok, Lines} ->
        stat_raw_merge_cpus(stat_raw_scan_lines(Lines));
    Error ->  % {error, any()}
        Error
    end.

stat_raw_scan_lines(Lines) ->
    stat_raw_scan_lines(Lines, []).

stat_raw_scan_lines([], TupList) ->
    TupList;
stat_raw_scan_lines([H|T], TupList) ->
    case stat_raw_scan_line(H) of
    {ok, KV} ->
        stat_raw_scan_lines(T, [KV|TupList]);
    _ ->  %% error | ignore
        stat_raw_scan_lines(T, TupList)
    end.

stat_raw_scan_line(<<"cpu", _/binary>> = Line) ->
    RE = case get(regex_cpu) of
    undefined ->
        {ok, MP} = re:compile("cpu(\\d+)?\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)"
            "\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)"),
        put(regex_cpu, MP),
        MP;
    MP ->
        MP
    end,
    case re:run(Line, RE, [{capture, all_but_first, list}]) of
    {match, [Tag|Nums]} ->
        [User, Nice, Sys, Idle, Wait, IRQ, SoftIRQ, Steal] = 
            [list_to_integer(S) || S <- Nums],
        Info = #cputime{us=User, sy=Sys, ni=Nice, id=Idle,
                        wa=Wait, hi=IRQ, si=SoftIRQ, st=Steal},
        Cpu = if Tag =:= "" -> all; true -> list_to_integer(Tag) end,
        {ok, {cpu, {Cpu, Info}}};
    _ ->
        error
    end;
stat_raw_scan_line(<<"intr", _/binary>> = Line) ->
    RE = case get(regex_intr) of
    undefined ->
        {ok, MP} = re:compile("intr (\\d+) "),
        put(regex_intr, MP),
        MP;
    MP ->
        MP
    end,
    case re:run(Line, RE, [{capture, all_but_first, list}]) of
    {match, [Num]} ->
        {ok, {intr, list_to_integer(Num)}};
    _ ->
        error
    end;
stat_raw_scan_line(<<"softirq", _/binary>> = Line) ->
    RE = case get(regex_intr) of
    undefined ->
        {ok, MP} = re:compile("softirq (\\d+) "),
        put(regex_intr, MP),
        MP;
    MP ->
        MP
    end,
    case re:run(Line, RE, [{capture, all_but_first, list}]) of
    {match, [Num]} ->
        {ok, {softirq, list_to_integer(Num)}};
    _ ->
        error
    end;
stat_raw_scan_line(<<"ctxt", _/binary>> = Line) ->
    [_, Num] = (string:tokens(binary_to_list(Line), " \n")),
    {ok, {ctxt, list_to_integer(Num)}};
stat_raw_scan_line(<<"btime", _/binary>> = Line) ->
    [_, Num] = (string:tokens(binary_to_list(Line), " \n")),
    {ok, {btime, list_to_integer(Num)}};
stat_raw_scan_line(<<"processes", _/binary>> = Line) ->
    [_, Num] = (string:tokens(binary_to_list(Line), " \n")),
    {ok, {processes, list_to_integer(Num)}};
stat_raw_scan_line(<<"procs_running", _/binary>> = Line) ->
    [_, Num] = (string:tokens(binary_to_list(Line), " \n")),
    {ok, {procs_running, list_to_integer(Num)}};
stat_raw_scan_line(<<"procs_blocked", _/binary>> = Line) ->
    [_, Num] = (string:tokens(binary_to_list(Line), " \n")),
    {ok, {procs_blocked, list_to_integer(Num)}};
stat_raw_scan_line(_) ->
    ignore.

stat_raw_merge_cpus(ParsedLines) ->
    {A, B} = stat_raw_merge_cpus(ParsedLines, [], []),
    [{cpu, A}|B].

stat_raw_merge_cpus([], A, B) ->
    {A, B};
stat_raw_merge_cpus([{cpu, CpuInfo}|T], A, B) ->
    stat_raw_merge_cpus(T, [CpuInfo|A], B);
stat_raw_merge_cpus([H|T], A, B) ->
    stat_raw_merge_cpus(T, A, [H|B]).

%%--------------------------------------------------------------------
%% @doc
%% Collect memory usage information.
%% @end
%%--------------------------------------------------------------------
-spec memfree() -> meminfo() | {'error', any()}.

memfree() ->
    case read_lines("/proc/meminfo") of
    {ok, Lines} ->
        memfree_scan_lines(Lines);
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Scan raw lines from /proc/meminfo. Used in memfree/0.
%% @end
%%--------------------------------------------------------------------
-spec memfree_scan_lines([binary()]) -> meminfo().

memfree_scan_lines(Lines) ->
    memfree_collect(lists:map(fun memfree_scan_line/1, Lines), #meminfo{}).

memfree_collect([], Rec) ->
    Rec;
memfree_collect([{mem_total, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{mem_total = Value});
memfree_collect([{mem_free, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{mem_free = Value});
memfree_collect([{mem_buffers, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{mem_buffers = Value});
memfree_collect([{mem_cached, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{mem_cached = Value});
memfree_collect([{swap_total, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{swap_total = Value});
memfree_collect([{swap_free, Value}|Tail], Rec) ->
    memfree_collect(Tail, Rec#meminfo{swap_free = Value});
memfree_collect([_|Tail], Rec) ->
    memfree_collect(Tail, Rec).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Interpret each line from /proc/meminfo. Used in memfree_scan_lines/0.
%% @end
%%--------------------------------------------------------------------
-spec memfree_scan_line(binary()) -> tuple() | 'ignore'.

memfree_scan_line(Line) ->
    memfree_conv_line(re:split(Line, "\\s+")).

memfree_conv_line([<<"MemTotal:">>, Value, _Unit]) ->
    {mem_total, bin2int(Value)};
memfree_conv_line([<<"MemFree:">>, Value, _Unit]) ->
    {mem_free, bin2int(Value)};
memfree_conv_line([<<"Buffers:">>, Value, _Unit]) ->
    {mem_buffers, bin2int(Value)};
memfree_conv_line([<<"Cached:">>, Value, _Unit]) ->
    {mem_cached, bin2int(Value)};
memfree_conv_line([<<"SwapTotal:">>, Value, _Unit]) ->
    {swap_total, bin2int(Value)};
memfree_conv_line([<<"SwapFree:">>, Value, _Unit]) ->
    {swap_free, bin2int(Value)};
memfree_conv_line(_) ->
    ignore.

%%--------------------------------------------------------------------
%% @doc
%% Report file system disk space usage.
%% It invokes the system command `df' to get current disk usage of
%% underlying operating system, and return it in a reasonable form.
%% @end
%%--------------------------------------------------------------------
-spec diskfree() -> {'ok', [diskinfo()]} | {'error', any()}.

diskfree() ->
    try
        diskfree_parse_data(os:cmd("df -T -P -B1"))
    catch
        T:E -> {error, {T, E}}
    end.

diskfree_parse_data(Data) ->
    Lines = tl(re:split(Data, "\n")),  % skip the 1st line
    diskfree_parse_lines(Lines, []).

diskfree_parse_lines([], SoFar) ->
    lists:reverse(SoFar);
diskfree_parse_lines([<<>>|T], SoFar) ->
    diskfree_parse_lines(T, SoFar);
diskfree_parse_lines([Line|T], SoFar) when is_binary(Line) ->
    RE = case get(df_regex) of
    undefined ->
        {ok, Regex} = re:compile("^(.*?)\\s+(.*?)"
            "\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)%\\s+(.+)$"),
        put(df_regex, Regex),
        Regex;
    Regex ->
        Regex
    end,
    case re:run(Line, RE, [{capture,all_but_first,list}]) of
    nomatch ->
        diskfree_parse_lines(T, SoFar);
    {match, [FS,Type,Size,Used,Free,Pct,Mnt]} ->
        DI = #diskinfo{
            fs   = FS,
            type = Type,
            size = list_to_integer(Size),
            used = list_to_integer(Used),
            free = list_to_integer(Free),
            pct  = list_to_integer(Pct),
            mnt  = Mnt},
        diskfree_parse_lines(T, [DI|SoFar])
    end.

%%--------------------------------------------------------------------
%% @doc
%% Test whether Item is a device.
%% For example:
%%   1> sysinfo:is_device(sda).
%%   true
%%   1> sysinfo:is_device(sda1).
%%   false
%% @end
%%
%% Some servers have got such devices:
%%   104    0 cciss/c0d0  
%%   104    1 cciss/c0d0p1
%%   104    2 cciss/c0d0p2
%%   104    5 cciss/c0d0p5
%%   104    6 cciss/c0d0p6
%%   104    7 cciss/c0d0p7
%%   104    8 cciss/c0d0p8
%%   104    9 cciss/c0d0p9
%% The sysfs node for cciss/c0d0 is /sys/cciss!c0d0.
%%--------------------------------------------------------------------
-spec is_device(atom() | string()) -> 'true' | 'false'.

is_device(Item) when is_atom(Item) ->
    is_device(atom_to_list(Item));
is_device(Item) when is_list(Item) ->
    Name = case re:run(Item, "^cciss/([0-9a-z]+)$", [{capture,all_but_first,list}]) of
    {match, [Partition]} ->
        "cciss!" ++ Partition;
    nomatch ->
        Item
    end,
    filelib:is_file(filename:join(["/sys/block", Name])).

%%--------------------------------------------------------------------
%% @doc
%% Collect I/O statistics data of block devices.
%% @end
%%--------------------------------------------------------------------
-spec diskstats() -> [diskstats()] | {'error', any()}.

diskstats() ->
    case read_lines(?PathDiskStats) of
    {ok, Lines} ->
        diskstats_scan_lines(Lines, erlang:now());
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Scan raw lines from /proc/diskstats. Used in diskstats/0.
%% @end
%%--------------------------------------------------------------------
-spec diskstats_scan_lines([binary()], timestamp()) -> [diskstats()].

diskstats_scan_lines(Lines, Timestamp) ->
    lists:foldr(fun(Line, Acc) ->
        case diskstats_scan_line(Line, Timestamp) of
        undefined ->
            Acc;
        DiskStats ->
            [DiskStats|Acc]
        end
    end, [], Lines).

-spec diskstats_scan_line(binary(), timestamp()) -> diskstats() | 'undefined'.

diskstats_scan_line(Line, Timestamp) ->
    Vec = tl(re:split(Line, "\\s+")),
    case length(Vec) of
    14 ->
        [_Major, _Minor, DevBin | RawStats] = Vec,
        DevStr = binary_to_list(DevBin),
        case is_device(DevStr) of
        true ->
            RDs = lists:nth(1, RawStats),
            WRs = lists:nth(5, RawStats),
            if RDs =:= <<"0">>, WRs =:= <<"0">> ->
                % if both rd_ios and wr_ios are 0, the line is skipped.
                undefined;
            true ->
                Dev = list_to_atom(DevStr),  %% atom-table-overflow safe
                Counters = [bin2int(S) || S <- RawStats],
                list_to_tuple([diskstats,Dev]++Counters++[Timestamp])
            end;
        false ->
            % if dev_name of this line is not a device, it is skipped.
            undefined
        end;
    _ ->
        % if the line contains less than 14 items, it is skipped.
        undefined
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec diskstats_to_iostat(diskstats(), diskstats()) -> iostat().

diskstats_to_iostat(#diskstats{dev_name=Dev}=DiskStatsY, #diskstats{dev_name=Dev}=DiskStatsX) ->
    TsFactor = 1000000,
    TDelta = timer:now_diff(DiskStatsY#diskstats.timestamp, DiskStatsX#diskstats.timestamp),

    % I/O transfers during this interval
    TC = (DiskStatsY#diskstats.rd_ios + DiskStatsY#diskstats.wr_ios) -
         (DiskStatsX#diskstats.rd_ios + DiskStatsX#diskstats.wr_ios),
    % average I/O transfers per second
    TPS =  TC * TsFactor / TDelta,

    % blocks/sectors read during this internal
    Blk_read = DiskStatsY#diskstats.rd_secs - DiskStatsX#diskstats.rd_secs,
    % average blocks/sectors read per second
    Blk_read_rate = Blk_read * TsFactor / TDelta,

    % blocks/sectors written during this internal
    Blk_wrtn = DiskStatsY#diskstats.wr_secs - DiskStatsX#diskstats.wr_secs,
    % average blocks/sectors written per second
    Blk_wrtn_rate = Blk_wrtn * TsFactor / TDelta,

    #iostat{
        dev_name   = Dev,
        tps        = TPS,
        rd_secs_ps = Blk_read_rate,
        wr_secs_ps = Blk_wrtn_rate,
        rd_secs    = Blk_read,
        wr_secs    = Blk_wrtn,
        timestamp  = DiskStatsY#diskstats.timestamp}.

%%--------------------------------------------------------------------
%% @doc
%% Timestamp is not the middle point of the interval, but the right end.
%% @end
%%--------------------------------------------------------------------
-spec iostat([diskstats()], [diskstats()]) -> [iostat()].

iostat(DiskStatsLY, DiskStatsLX) ->
    iostat_loop(DiskStatsLY, DiskStatsLX, []).

iostat_loop([], _, Matched) ->
    lists:reverse(Matched);
iostat_loop([DiskStatsY|T], DiskStatsLX, Matched) ->
    Dev = DiskStatsY#diskstats.dev_name,
    KeyPos = 2,  %% the structure of #diskstats{} is {diskstats, dev_name, ...}
    case lists:keytake(Dev, KeyPos, DiskStatsLX) of
    {value, DiskStatsX, Remainder} ->
        IoStat = diskstats_to_iostat(DiskStatsY, DiskStatsX),
        iostat_loop(T, Remainder, [IoStat|Matched]);
    false ->
        iostat_loop(T, DiskStatsLX, Matched)
    end.

%%--------------------------------------------------------------------
%% @doc
%% List all network interfaces in this system.
%% This function shall never fail as long as sysfs is mounted.
%% If sysfs is not mounted, it returns {error, enoent}.
%% @end
%%--------------------------------------------------------------------
-spec net_devices() -> [atom()] | {'error', any()}.

net_devices() ->
    case file:list_dir(?PathNetDevice) of
    {ok, Entries} ->
        [list_to_atom(E) || E <- Entries];
    {error, Reason} ->
        {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Get statistics data of a certain network interfaces.
%% This function shall never fail as long as Device exists.
%% If Device does not exist, it returns a trivial #ifstats record.
%% @end
%%--------------------------------------------------------------------
-spec ifstats(atom()) -> ifstats().

ifstats(Device) ->
    #ifstats{
        dev_name   = Device,                                  % Device
        rx_bytes   = read_netdev_stats(Device, rx_bytes),     % TotalDataIn
        tx_bytes   = read_netdev_stats(Device, tx_bytes),     % TotalDataOut
        rx_packets = read_netdev_stats(Device, rx_packets),   % TotalPacketsIn
        tx_packets = read_netdev_stats(Device, tx_packets),   % TotalPacketsOut
        rx_errors  = read_netdev_stats(Device, rx_errors),    % TotalErrorsIn
        tx_errors  = read_netdev_stats(Device, tx_errors),    % TotalErrorsOut
        rx_dropped = read_netdev_stats(Device, rx_dropped),   % TotalDropsIn
        tx_dropped = read_netdev_stats(Device, tx_dropped),   % TotalDropsOut
        timestamp  = erlang:now()}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% ifstats/1 with external timestamp.
%% This function is intended for ifstats_all/0.
%% @end
%%--------------------------------------------------------------------
-spec ifstats(atom(), timestamp()) -> ifstats().

ifstats(Device, Timestamp) ->
    #ifstats{
        dev_name   = Device,                                  % Device
        rx_bytes   = read_netdev_stats(Device, rx_bytes),     % TotalDataIn
        tx_bytes   = read_netdev_stats(Device, tx_bytes),     % TotalDataOut
        rx_packets = read_netdev_stats(Device, rx_packets),   % TotalPacketsIn
        tx_packets = read_netdev_stats(Device, tx_packets),   % TotalPacketsOut
        rx_errors  = read_netdev_stats(Device, rx_errors),    % TotalErrorsIn
        tx_errors  = read_netdev_stats(Device, tx_errors),    % TotalErrorsOut
        rx_dropped = read_netdev_stats(Device, rx_dropped),   % TotalDropsIn
        tx_dropped = read_netdev_stats(Device, tx_dropped),   % TotalDropsOut
        timestamp  = Timestamp}.

%%--------------------------------------------------------------------
%% @doc
%% Get statistics data of all network interfaces in the system.
%% This function shall never fail as long as sysfs is mounted.
%% If sysfs is not mounted, it returns {error, enoent}.
%% @end
%%--------------------------------------------------------------------
-spec ifstats_all() -> [tuple()] | {'error', any()}.

ifstats_all() ->
    case net_devices() of
    Devices when is_list(Devices) ->
        Timestamp = erlang:now(),
        [ifstats(Dev, Timestamp) || Dev <- Devices];
    {error, Reason} ->
        {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Get statistics data of all network interfaces but lo in the system.
%% This function shall never fail as long as sysfs is mounted.
%% If sysfs is not mounted, it returns {error, enoent}.
%% @end
%%--------------------------------------------------------------------
-spec ifstats_all_but_lo() -> [tuple()] | {'error', any()}.

ifstats_all_but_lo() ->
    case net_devices() of
    Devices when is_list(Devices) ->
        Timestamp = erlang:now(),
        [ifstats(Dev, Timestamp) || Dev <- Devices, Dev =/= lo];
    {error, Reason} ->
        {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Read the value of a network device statistics item.
%% This function shall never fail as long as Device exists.
%% If Device does not exist, it returns undefined.
%% @end
%%--------------------------------------------------------------------
-spec read_netdev_stats(atom(), atom()) -> integer() | {'error', any()}.

read_netdev_stats(Device, Item) ->
    case read_sys_entry_long(
        filename:join([?PathNetDevice, Device, "statistics", Item])) of
    Value when is_integer(Value) ->
        Value;
    {error, enoent} ->
        undefined
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Read the value of a long integer entry from /sys.
%% This function shall never fail as long as EntryPath exists.
%% If EntryPath does not exist, it returns {error, enoent}.
%% @end
%%--------------------------------------------------------------------
-spec read_sys_entry_long(string()) -> integer() | {'error', any()}.

read_sys_entry_long(EntryPath) ->
    case file:read_file(EntryPath) of
    {ok, Bin} ->
        {Num, _Rest} = string:to_integer(binary_to_list(Bin)),
        Num;
    {error, Reason} ->
        {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec ifstats_to_netstat(ifstats(), ifstats()) -> netstat().

ifstats_to_netstat(#ifstats{dev_name=Dev}=IfStatsY, #ifstats{dev_name=Dev}=IfStatsX) ->
    TsFactor = 1000000,
    TDelta = timer:now_diff(IfStatsY#ifstats.timestamp, IfStatsX#ifstats.timestamp),
    #netstat{
        dev_name  = Dev,
        rx_bps    = (IfStatsY#ifstats.rx_bytes - IfStatsX#ifstats.rx_bytes) * TsFactor / TDelta,
        tx_bps    = (IfStatsY#ifstats.tx_bytes - IfStatsX#ifstats.tx_bytes) * TsFactor / TDelta,
        rx_pps    = (IfStatsY#ifstats.rx_packets - IfStatsX#ifstats.rx_packets) * TsFactor / TDelta,
        tx_pps    = (IfStatsY#ifstats.tx_packets - IfStatsX#ifstats.tx_packets) * TsFactor / TDelta,
        timestamp = IfStatsY#ifstats.timestamp}.

%%--------------------------------------------------------------------
%% @doc
%% Timestamp is not the middle point of the interval, but the right end.
%% @end
%%--------------------------------------------------------------------
-spec netstat([ifstats()], [ifstats()]) -> [netstat()].

netstat(IfStatsLY, IfStatsLX) ->
    netstat_loop(IfStatsLY, IfStatsLX, []).

netstat_loop([], _, Matched) ->
    lists:reverse(Matched);
netstat_loop([IfStatsY|T], IfStatsLX, Matched) ->
    Dev = IfStatsY#ifstats.dev_name,
    KeyPos = 2,  %% the structure of #ifstats{} is {ifstats, dev_name, ...}
    case lists:keytake(Dev, KeyPos, IfStatsLX) of
    {value, IfStatsX, Remainder} ->
        Netstat = ifstats_to_netstat(IfStatsY, IfStatsX),
        netstat_loop(T, Remainder, [Netstat|Matched]);
    false ->
        netstat_loop(T, IfStatsLX, Matched)
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Return the content of a file as a list of lines.
%% Note: the line splitter "\n" is removed from each line.
%% @end
%%--------------------------------------------------------------------
-spec read_lines(string()) -> {'ok', [binary()]} | {'error', any()}.

read_lines(FilePath) ->
    case read_file(FilePath) of
    {ok, Data} ->
        {ok, re:split(Data, "\\n")};
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Read the content of a file and return a binary.
%% I was trying to read /proc/stat using file:read_file/1.
%%   1> file:read_file("/proc/stat").
%%   {ok, <<>>}.
%% file:read_file/1 always checks the length of the file at first. If
%% the length is 0, it returns <<>> immediately.
%% So I have to write my own read_file function.
%% @end
%%--------------------------------------------------------------------
-spec read_file(string()) -> {'ok', binary()} | {'error', any()}.

read_file(FilePath) ->
    case file:open(FilePath, [read, raw, binary]) of
    {ok, IoDevice} ->
        case loop_read(IoDevice, []) of
        {ok, Data} ->
            file:close(IoDevice),
            {ok, Data};
        Error2 ->  % {error, any()}
            file:close(IoDevice),
            Error2
        end;
    Error1 ->  % {error, any()}
        Error1
    end.

-spec loop_read(io_device(), list()) -> {'ok', binary()} | {'error', any()}.

loop_read(IoDevice, DataList) ->
    case file:read(IoDevice, ?IoBuffSize) of
    eof ->
        {ok, list_to_binary(lists:reverse(DataList))};
    {ok, Data} ->
        loop_read(IoDevice, [Data|DataList]);
    Error ->  % {error, any()}
        Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert binary to integer. It's a shortcut function.
%% For example:
%%   bin2int(<<"2345">>) -> 2345.
%% @end
%%--------------------------------------------------------------------
-spec bin2int(binary()) -> integer().

bin2int(Data) ->
    list_to_integer(binary_to_list(Data)).
