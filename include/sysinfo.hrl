-ifndef(SYSINFO_HRL_).
-define(SYSINFO_HRL_, 1).

%%--------------------------------------------------------------------
%% Definitions used in read_file/1
%%--------------------------------------------------------------------
%% defined in kernel/file.hrl
-record(file_descriptor, {
    module :: module(),     % Module that handles this kind of file
    data   :: term()        % Module dependent data
}).

%% defined in kernel/file.erl
-type fd()        :: #file_descriptor{}.
-type io_device() :: pid() | fd().

%% defined in stdlib/timer.erl
-type timestamp() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}.

-define(IoBuffSize, 4096).

%%--------------------------------------------------------------------
-define(PathDiskStats, "/proc/diskstats").
-define(PathLoadAvg,   "/proc/loadavg").
-define(PathStat,      "/proc/stat").
-define(PathUptime,    "/proc/uptime").
-define(PathVersion,   "/proc/version").
-define(PathNetDevice, "/sys/class/net").

%%--------------------------------------------------------------------
-record(loadavg_raw, {
    avg1  :: float(),    %% load average over last 1 minutes
    avg5  :: float(),    %% load average over last 5 minutes
    avg15 :: float(),    %% load average over last 15 minutes
    prun  :: integer(),  %% the number of currently running tasks
    ptot  :: integer(),  %% the total number of all tasks
    plast :: integer()   %% the pid of the most recently created task
}).

-type loadavg_raw() :: #loadavg_raw{}.

-record(loadavg, {
    avg1  :: float(),    %% load average over last 1 minutes
    avg5  :: float(),    %% load average over last 5 minutes
    avg15 :: float()     %% load average over last 15 minutes
}).

-type loadavg() :: #loadavg{}.

%%--------------------------------------------------------------------
-record(uptime_raw, {
    uptime   :: float(), %% uptime in seconds
    idletime :: float()  %% idle time in seconds
}).

-type uptime_raw() :: #uptime_raw{}.

-record(uptime, {
    day    :: integer(),
    hour   :: integer(),
    minute :: integer(),
    second :: integer()
}).

-type uptime() :: #uptime{}.

%%--------------------------------------------------------------------
%% #cputime{} holds the time slice division of the CPU.
%% A typical top report:
%% Cpu(s): 15.8%us, 7.2%sy, 0.0%ni, 76.5%id, 0.5%wa, 0.0%hi, 0.0%si, 0.0%st
%% Here each item of cputime is an integer. The unit is USER_HZ.
-record(cputime, {
    us :: integer(),  %% user mode
    sy :: integer(),  %% system mode
    ni :: integer(),  %% low priority user mode (nice)
    id :: integer(),  %% idle task
    wa :: integer(),  %% I/O waiting
    hi :: integer(),  %% servicing IRQs
    si :: integer(),  %% servicing soft IRQs
    st :: integer()   %% steal (time given to other DomU instances)
}).

-type cputime() :: #cputime{}.

-record(cputime_util, {
    us :: float(),  %% user mode
    sy :: float(),  %% system mode
    ni :: float(),  %% low priority user mode (nice)
    id :: float(),  %% idle task
    wa :: float(),  %% I/O waiting
    hi :: float(),  %% servicing IRQs
    si :: float(),  %% servicing soft IRQs
    st :: float()   %% steal (time given to other DomU instances)
}).

-type cputime_util() :: #cputime_util{}.


%%--------------------------------------------------------------------
-record(meminfo, {
    mem_total   :: integer(),  %% in Kilo-Bytes
    mem_free    :: integer(),
    mem_buffers :: integer(),
    mem_cached  :: integer(),
    swap_total  :: integer(),
    swap_free   :: integer()
}).

-type meminfo() :: #meminfo{}.

%%--------------------------------------------------------------------
-record(diskinfo, {
    fs     ::  string(),
    type   ::  string(),
    size   ::  integer(),
    used   ::  integer(),
    free   ::  integer(),
    pct    ::  integer(),
    mnt    ::  string()}).

-type diskinfo() :: #diskinfo{}.

%%--------------------------------------------------------------------
%% block device I/O statistics
-record(diskstats, {
    dev_name  :: atom(),     % device name
    rd_ios    :: integer(),  % # of reads completed
    rd_merges :: integer(),  % # of reads merged
    rd_secs   :: integer(),  % # of sectors read
    rd_ticks  :: integer(),  % # of milliseconds spent reading
    wr_ios    :: integer(),  % # of writes completed
    wr_merges :: integer(),  % # of writes merged
    wr_secs   :: integer(),  % # of sectors written
    wr_ticks  :: integer(),  % # of milliseconds spent writing
    ios_pgr   :: integer(),  % # of I/Os currently in progress
    tot_ticks :: integer(),  % # of milliseconds spent doing I/Os
    rq_ticks  :: integer(),  % weighted # of milliseconds spent doing I/Os
    timestamp :: timestamp()
}).

-type diskstats() :: #diskstats{}.

-record(iostat, {
    dev_name   :: atom(),      % device name
    tps        :: float(),     % # of transfers per second
    rd_secs_ps :: float(),     % # of blocks read per second
    wr_secs_ps :: float(),     % # of blocks written per second
    rd_secs    :: integer(),   % # of blocks read
    wr_secs    :: integer(),   % # of blocks written
    timestamp  :: timestamp()
}).

-type iostat() :: #iostat{}.

%%--------------------------------------------------------------------
%% network interface I/O statistics
-record(ifstats, {
    dev_name   :: atom(),
    rx_bytes   :: integer(),
    tx_bytes   :: integer(),
    rx_packets :: integer(),
    tx_packets :: integer(),
    rx_errors  :: integer(),
    tx_errors  :: integer(),
    rx_dropped :: integer(),
    tx_dropped :: integer(),
    timestamp  :: timestamp()
}).

-type ifstats() :: #ifstats{}.

-record(netstat, {
    dev_name   :: atom(),
    rx_bps     :: float(),
    tx_bps     :: float(),
    rx_pps     :: float(),
    tx_pps     :: float(),
    timestamp  :: timestamp()
}).

-type netstat() :: #netstat{}.

-endif.
