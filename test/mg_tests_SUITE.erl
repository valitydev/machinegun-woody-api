%%%
%%% Copyright 2020 Valitydev
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%

%%%
%%% TODO сделать нормальный тест автомата, как вариант, через пропер
%%%
-module(mg_tests_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("mg_proto/include/mg_proto_state_processing_thrift.hrl").

%% tests descriptions
-export([all/0]).
-export([groups/0]).
-export([init_per_suite/1]).
-export([end_per_suite/1]).
-export([init_per_group/2]).
-export([end_per_group/2]).

%% base group tests
-export([namespace_not_found/1]).
-export([machine_start_empty_id/1]).
-export([machine_start/1]).
-export([machine_already_exists/1]).
-export([machine_call_by_id/1]).
-export([machine_id_not_found/1]).
-export([machine_empty_id_not_found/1]).
-export([machine_remove/1]).
-export([machine_remove_by_action/1]).
-export([machine_notification/1]).

%% history group tests
-export([history_changed_atomically/1]).

%% repair group tests
-export([failed_machine_start/1]).
-export([machine_start_timeout/1]).
-export([machine_processor_error/1]).
-export([failed_machine_status/1]).
-export([failed_machine_call/1]).
-export([failed_machine_repair_error/1]).
% -export([failed_machine_repair_business_error/1]).
-export([failed_machine_repair/1]).
-export([failed_machine_simple_repair/1]).
-export([working_machine_repair/1]).
-export([working_machine_status/1]).

%% timer group tests
-export([handle_timer/1]).
-export([abort_timer/1]).

%% deadline group tests
-export([success_call_with_deadline/1]).
-export([timeout_call_with_deadline/1]).

%% event_sink group tests
-export([event_sink_get_empty_history/1]).
-export([event_sink_get_not_empty_history/1]).
-export([event_sink_get_last_event/1]).
-export([event_sink_incorrect_event_id/1]).
-export([event_sink_incorrect_sink_id/1]).
-export([event_sink_lots_events_ordering/1]).

%%

-export([config_with_multiple_event_sinks/1]).

-define(NS, <<"NS">>).
-define(ID, <<"ID">>).
-define(EMPTY_ID, <<"">>).
-define(ES_ID, <<"test_event_sink_2">>).

-define(DEADLINE_TIMEOUT, 1000).

%%
%% tests descriptions
%%
-type group_name() :: atom().
-type test_name() :: atom().
-type config() :: [{atom(), _}].

-spec all() -> [test_name() | {group, group_name()}].
all() ->
    [
        {group, base},
        {group, history},
        {group, repair},
        {group, timers},
        {group, event_sink},
        {group, deadline},
        config_with_multiple_event_sinks
    ].

-spec groups() -> [{group_name(), list(_), [test_name()]}].
groups() ->
    [
        % TODO проверить отмену таймера
        % TODO проверить отдельно get_history
        {base, [sequence], [
            namespace_not_found,
            machine_id_not_found,
            machine_empty_id_not_found,
            machine_start_empty_id,
            machine_start,
            machine_already_exists,
            machine_id_not_found,
            machine_call_by_id,
            machine_notification,
            machine_remove,
            machine_id_not_found,
            machine_start,
            machine_remove_by_action,
            machine_id_not_found
        ]},

        {history, [sequence, {repeat, 5}], [
            history_changed_atomically
        ]},

        {repair, [sequence], [
            failed_machine_start,
            machine_start_timeout,
            machine_id_not_found,
            machine_start,
            machine_processor_error,
            failed_machine_status,
            failed_machine_call,
            failed_machine_repair_error,
            % failed_machine_repair_business_error, % FIXME: uncomment after switch to new repair
            failed_machine_repair,
            machine_call_by_id,
            working_machine_repair,
            working_machine_status,
            machine_remove,
            machine_start,
            machine_processor_error,
            failed_machine_simple_repair,
            machine_call_by_id,
            machine_remove
        ]},

        {timers, [sequence], [
            machine_start,
            handle_timer
            % handle_timer % был прецендент, что таймер срабатывал только один раз
            % abort_timer
        ]},

        {deadline, [sequence], [
            machine_start,
            success_call_with_deadline,
            timeout_call_with_deadline
        ]},

        {event_sink, [sequence], [
            event_sink_get_empty_history,
            event_sink_get_not_empty_history,
            event_sink_get_last_event,
            % TODO event_not_found
            % event_sink_incorrect_event_id,
            event_sink_incorrect_sink_id,
            event_sink_lots_events_ordering
        ]}
    ].

%%
%% starting/stopping
%%
-spec init_per_suite(config()) -> config().
init_per_suite(C) ->
    % dbg:tracer(), dbg:p(all, c),
    % dbg:tpl({mg_core_machine, retry_strategy, '_'}, x),
    C.

-spec end_per_suite(config()) -> ok.
end_per_suite(_C) ->
    ok.

-spec init_per_group(group_name(), config()) -> config().
init_per_group(history, C) ->
    init_per_group([{storage, mg_core_storage_memory} | C]);
init_per_group(_, C) ->
    % NOTE
    % Даже такой небольшой шанс может сработать в ситуациях, когда мы в процессоре выгребаем
    % большой кусок истории машины, из-за чего реальная вероятность зафейлить операцию равна
    % (1 - (1 - p) ^ n).
    init_per_group([{storage, {mg_core_storage_memory, #{random_transient_fail => 0.01}}} | C]).

-spec init_per_group(config()) -> config().
init_per_group(C) ->
    %% TODO сделать нормальную генерацию урлов
    Config = mg_woody_api_config(C),
    Apps = mg_ct_helper:start_applications([
        brod,
        machinegun_woody_api
    ]),
    {ok, ProcessorPid} = mg_test_processor:start(
        {0, 0, 0, 0},
        8023,
        genlib_map:compact(#{
            processor => {
                "/processor",
                #{
                    signal => fun default_signal_handler/1,
                    call => fun default_call_handler/1,
                    repair => fun default_repair_handler/1
                }
            }
        }),
        Config
    ),

    [
        {apps, Apps},
        {automaton_options, #{
            url => "http://localhost:8022",
            ns => ?NS,
            retry_strategy => genlib_retry:linear(3, 1)
        }},
        {event_sink_options, "http://localhost:8022"},
        {processor_pid, ProcessorPid}
        | C
    ].

-spec default_signal_handler(mg_core_events_machine:signal_args()) ->
    mg_core_events_machine:signal_result().
default_signal_handler({Args, _Machine}) ->
    case Args of
        {init, <<"fail">>} ->
            erlang:error(fail);
        {init, <<"timeout">>} ->
            timer:sleep(infinity);
        {init, [<<"fire">>, HistoryLen, EventBody, AuxState]} ->
            {
                {content(AuxState), [content(EventBody) || _ <- lists:seq(1, HistoryLen)]},
                #{timer => undefined}
            };
        {repair, <<"error">>} ->
            erlang:error(error);
        {notification, NotificationArgs} ->
            {{null(), [content(NotificationArgs)]}, #{timer => undefined}};
        timeout ->
            {{null(), [content(<<"handle_timer_body">>)]}, #{timer => undefined}};
        _ ->
            mg_test_processor:default_result(signal, Args)
    end.

-spec default_call_handler(mg_core_events_machine:call_args()) ->
    mg_core_events_machine:call_result().
default_call_handler({Args, #{history := History}}) ->
    Evs = [N || #{body := {_Metadata, N}} <- History],
    SetTimer = {set_timer, {timeout, 1}, {undefined, undefined, forward}, 30},
    case Args of
        [<<"event">>, I] ->
            case lists:member(I, Evs) of
                false -> {I, {null(), [content(I)]}, #{}};
                true -> {I, {null(), []}, #{}}
            end;
        <<"nop">> ->
            {Args, {null(), []}, #{}};
        <<"set_timer">> ->
            {Args, {null(), [content(<<"timer_body">>)]}, #{timer => SetTimer}};
        <<"unset_timer">> ->
            {Args, {null(), [content(<<"timer_body">>)]}, #{timer => unset_timer}};
        <<"fail">> ->
            erlang:error(fail);
        <<"sleep">> ->
            timer:sleep(?DEADLINE_TIMEOUT * 2),
            {Args, {null(), [content(<<"sleep">>)]}, #{}};
        <<"remove">> ->
            {Args, {null(), [content(<<"removed">>)]}, #{remove => remove}}
    end.

-spec default_repair_handler(mg_core_events_machine:repair_args()) ->
    mg_core_events_machine:repair_result().
default_repair_handler({Args, _Machine}) ->
    case Args of
        <<"error">> ->
            erlang:error(error);
        <<"business_error">> ->
            erlang:throw(#mg_stateproc_RepairFailed{reason = {bin, <<"because">>}});
        _ ->
            {ok, {Args, {null(), []}, #{}}}
    end.

-spec null() -> mg_core_events:content().
null() ->
    content(null).

-spec content(mg_core_storage:opaque()) -> mg_core_events:content().
content(Body) ->
    {#{format_version => 42}, Body}.

-spec mg_woody_api_config(config()) -> map().
mg_woody_api_config(C) ->
    Scheduler = #{
        task_quota => <<"scheduler_tasks_total">>
    },
    #{
        woody_server => #{ip => {0, 0, 0, 0, 0, 0, 0, 0}, port => 8022, limits => #{}},
        quotas => [
            #{
                name => <<"scheduler_tasks_total">>,
                limit => #{value => 10},
                update_interval => 100
            }
        ],
        namespaces => #{
            ?NS => #{
                storage => ?config(storage, C),
                processor => #{
                    url => <<"http://localhost:8023/processor">>,
                    transport_opts => #{pool => ns, max_connections => 100}
                },
                default_processing_timeout => 5000,
                schedulers => #{
                    timers => Scheduler,
                    notification => Scheduler
                },
                retries => #{
                    storage => {exponential, infinity, 1, 10},
                    timers => {exponential, infinity, 1, 10}
                },
                % сейчас существуют проблемы, которые не дают включить на постоянной основе эту
                % опцию (а очень хочется, чтобы проверять работоспособность идемпотентных ретраев)
                % TODO в будущем нужно это сделать
                % сейчас же можно иногда включать и смотреть
                % suicide_probability => 0.1,
                event_sinks => [
                    {mg_core_events_sink_machine, #{
                        name => machine,
                        machine_id => ?ES_ID
                    }},
                    {mg_core_events_sink_kafka, #{
                        name => kafka,
                        topic => ?ES_ID,
                        client => mg_kafka_client
                    }}
                ]
            }
        },
        event_sink_ns => #{
            storage => mg_core_storage_memory,
            default_processing_timeout => 5000
        }
    }.

-spec end_per_group(group_name(), config()) -> ok.
end_per_group(_, C) ->
    ok = proc_lib:stop(?config(processor_pid, C)),
    mg_ct_helper:stop_applications(?config(apps, C)).

%%
%% base group tests
%%
-spec namespace_not_found(config()) -> _.
namespace_not_found(C) ->
    Opts = maps:update(ns, <<"incorrect_NS">>, automaton_options(C)),
    #mg_stateproc_NamespaceNotFound{} = (catch mg_automaton_client:start(Opts, ?ID, <<>>)).

-spec machine_start_empty_id(config()) -> _.
machine_start_empty_id(C) ->
    % создание машины с невалидным ID не обрабатывается по протоколу
    {'EXIT', {{woody_error, _}, _}} =
        (catch mg_automaton_client:start(automaton_options(C), ?EMPTY_ID, <<>>)),
    ok.

-spec machine_start(config()) -> _.
machine_start(C) ->
    ok = start_machine(C, ?ID).

-spec machine_already_exists(config()) -> _.
machine_already_exists(C) ->
    #mg_stateproc_MachineAlreadyExists{} =
        (catch mg_automaton_client:start(automaton_options(C), ?ID, <<>>)).

-spec machine_id_not_found(config()) -> _.
machine_id_not_found(C) ->
    IncorrectID = <<"incorrect_ID">>,
    #mg_stateproc_MachineNotFound{} =
        (catch mg_automaton_client:call(automaton_options(C), IncorrectID, <<"nop">>)).

-spec machine_empty_id_not_found(config()) -> _.
machine_empty_id_not_found(C) ->
    #mg_stateproc_MachineNotFound{} =
        (catch mg_automaton_client:call(automaton_options(C), ?EMPTY_ID, <<"nop">>)).

-spec machine_call_by_id(config()) -> _.
machine_call_by_id(C) ->
    <<"nop">> = mg_automaton_client:call(automaton_options(C), ?ID, <<"nop">>).

-spec machine_notification(config()) -> _.
machine_notification(C) ->
    Options = automaton_options(C),
    #mg_stateproc_MachineNotFound{} =
        (catch mg_automaton_client:notify(Options, <<"nope">>, <<"hello">>)),
    #{history := InitialEvents} =
        mg_automaton_client:get_machine(Options, ?ID, {undefined, undefined, forward}),
    _NotificationID = mg_automaton_client:notify(Options, ?ID, <<"hello">>),
    _ = timer:sleep(1000),
    #{history := History1} =
        mg_automaton_client:get_machine(Options, ?ID, {undefined, undefined, forward}),
    [#{body := {_, <<"hello">>}}] = History1 -- InitialEvents.

-spec machine_remove(config()) -> _.
machine_remove(C) ->
    ok = mg_automaton_client:remove(automaton_options(C), ?ID).

-spec machine_remove_by_action(config()) -> _.
machine_remove_by_action(C) ->
    <<"nop">> = mg_automaton_client:call(automaton_options(C), ?ID, <<"nop">>),
    <<"remove">> =
        try
            mg_automaton_client:call(automaton_options(C), ?ID, <<"remove">>)
        catch
            throw:#mg_stateproc_MachineNotFound{} ->
                % The request had been retried
                <<"remove">>
        end.

%%
%% history group tests
%%
-spec history_changed_atomically(config()) -> _.
history_changed_atomically(C) ->
    ID = genlib:unique(),
    HistoryLen = 1000,
    AuxState = <<"see?!">>,
    EventBody = <<"welcome">>,
    HistoryLimit = 5,
    HistoryRange = {undefined, HistoryLimit, backward},
    HistorySeen = [
        {EventID, EventBody}
     || EventID <- lists:seq(HistoryLen, HistoryLen - HistoryLimit + 1, -1)
    ],
    Concurrency = 50,
    MaxDelay = 500,
    % concurrently ...
    [ok | Results] = genlib_pmap:map(
        fun
            (0) ->
                % ... start machine emitting HistoryLen events at once ...
                start_machine(C, ID, [<<"fire">>, HistoryLen, EventBody, AuxState]);
            (_) ->
                % ... and try to observe its history in the meantime
                ok = timer:sleep(rand:uniform(MaxDelay)),
                get_simple_history(C, ID, HistoryRange)
        end,
        lists:seq(0, Concurrency)
    ),
    Groups = lists:foldl(
        fun(R, Acc) ->
            maps:update_with(R, fun(N) -> N + 1 end, 1, Acc)
        end,
        #{},
        Results
    ),
    AtomicResult = {HistorySeen, AuxState},
    ?assertEqual(#{}, maps:without([undefined, AtomicResult], Groups)).

-spec get_simple_history(config(), mg_core:id(), mg_core_events:history_range()) ->
    {[{mg_core_events:id(), mg_core_storage:opaque()}], mg_core_storage:opaque()}.
get_simple_history(C, ID, HRange) ->
    try mg_automaton_client:get_machine(automaton_options(C), ID, HRange) of
        #{history := History, aux_state := {#{}, AuxState}} ->
            {
                [{EventID, Body} || #{id := EventID, body := {#{}, Body}} <- History],
                AuxState
            }
    catch
        throw:#mg_stateproc_MachineNotFound{} ->
            undefined
    end.

%%
%% repair group tests
%%
%% падение машины
-spec failed_machine_start(config()) -> _.
failed_machine_start(C) ->
    #mg_stateproc_MachineFailed{} =
        (catch mg_automaton_client:start(automaton_options(C), ?ID, <<"fail">>)).

-spec machine_start_timeout(config()) -> _.
machine_start_timeout(C) ->
    {'EXIT', {{woody_error, _}, _}} =
        (catch mg_automaton_client:start(
            automaton_options(C),
            ?ID,
            <<"timeout">>,
            mg_core_deadline:from_timeout(1000)
        )),
    #mg_stateproc_MachineNotFound{} =
        (catch mg_automaton_client:call(automaton_options(C), ?ID, <<"nop">>)).

-spec machine_processor_error(config()) -> _.
machine_processor_error(C) ->
    #mg_stateproc_MachineFailed{} =
        (catch mg_automaton_client:call(automaton_options(C), ?ID, <<"fail">>)).

-spec failed_machine_status(config()) -> _.
failed_machine_status(C) ->
    #{status := {failed, _}} =
        mg_automaton_client:get_machine(automaton_options(C), ?ID, {undefined, undefined, forward}).

-spec failed_machine_call(config()) -> _.
failed_machine_call(C) ->
    #mg_stateproc_MachineFailed{} =
        (catch mg_automaton_client:call(automaton_options(C), ?ID, <<"ok">>)).

-spec failed_machine_repair_error(config()) -> _.
failed_machine_repair_error(C) ->
    #mg_stateproc_MachineFailed{} =
        (catch mg_automaton_client:repair(automaton_options(C), ?ID, <<"error">>)).

% -spec failed_machine_repair_business_error(config()) ->
%     _.
% failed_machine_repair_business_error(C) ->
%     #mg_stateproc_RepairFailed{reason = {bin, <<"because">>}} =
%         (catch mg_automaton_client:repair(automaton_options(C), {id, ?ID}, <<"business_error">>)).

-spec failed_machine_repair(config()) -> _.
failed_machine_repair(C) ->
    <<"ok">> = mg_automaton_client:repair(automaton_options(C), ?ID, <<"ok">>).

-spec failed_machine_simple_repair(config()) -> _.
failed_machine_simple_repair(C) ->
    ok = mg_automaton_client:simple_repair(automaton_options(C), ?ID).

-spec working_machine_repair(config()) -> _.
working_machine_repair(C) ->
    #mg_stateproc_MachineAlreadyWorking{} =
        (catch mg_automaton_client:repair(automaton_options(C), ?ID, <<"ok">>)).

-spec working_machine_status(config()) -> _.
working_machine_status(C) ->
    #{status := working} =
        mg_automaton_client:get_machine(automaton_options(C), ?ID, {undefined, undefined, forward}).

%%
%% timer
%%
-spec handle_timer(config()) -> _.
handle_timer(C) ->
    Options0 = automaton_options(C),
    % retry with extremely short timeout
    Options1 = Options0#{retry_strategy => genlib_retry:linear(3, 1)},
    #{history := InitialEvents} =
        mg_automaton_client:get_machine(Options1, ?ID, {undefined, undefined, forward}),
    <<"set_timer">> = mg_automaton_client:call(Options1, ?ID, <<"set_timer">>),
    #{history := History1} =
        mg_automaton_client:get_machine(Options1, ?ID, {undefined, undefined, forward}),
    [StartTimerEvent] = History1 -- InitialEvents,
    ok = timer:sleep(2000),
    #{history := History2} =
        mg_automaton_client:get_machine(Options1, ?ID, {undefined, undefined, forward}),
    [StartTimerEvent, _] = History2 -- InitialEvents.

-spec abort_timer(config()) -> _.
abort_timer(C) ->
    #{history := InitialEvents} =
        mg_automaton_client:get_machine(
            automaton_options(C),
            ?ID,
            {undefined, undefined, forward}
        ),
    <<"set_timer">> = mg_automaton_client:call(automaton_options(C), ?ID, <<"set_timer">>),
    <<"unset_timer">> = mg_automaton_client:call(automaton_options(C), ?ID, <<"unset_timer">>),
    ok = timer:sleep(2000),
    #{history := History1} =
        mg_automaton_client:get_machine(
            automaton_options(C),
            ?ID,
            {undefined, undefined, forward}
        ),
    [_] = History1 -- InitialEvents.

%%
%% deadline
%%
-spec timeout_call_with_deadline(config()) -> _.
timeout_call_with_deadline(C) ->
    DeadlineFn = fun() -> mg_core_deadline:from_timeout(?DEADLINE_TIMEOUT) end,
    Options0 = no_timeout_automaton_options(C),
    Options1 = maps:remove(retry_strategy, Options0),
    {'EXIT', {{woody_error, {external, result_unknown, <<"{timeout", _/binary>>}}, _Stack}} =
        (catch mg_automaton_client:call(Options1, ?ID, <<"sleep">>, DeadlineFn())),
    #mg_stateproc_MachineAlreadyWorking{} =
        (catch mg_automaton_client:repair(Options0, ?ID, <<"ok">>, DeadlineFn())).

-spec success_call_with_deadline(config()) -> _.
success_call_with_deadline(C) ->
    Deadline = mg_core_deadline:from_timeout(?DEADLINE_TIMEOUT * 3),
    Options = no_timeout_automaton_options(C),
    <<"sleep">> = mg_automaton_client:call(Options, ?ID, <<"sleep">>, Deadline).

%%
%% event_sink group test
%%
-spec event_sink_get_empty_history(config()) -> _.
event_sink_get_empty_history(C) ->
    [] = mg_event_sink_client:get_history(es_opts(C), ?ES_ID, #mg_stateproc_HistoryRange{
        direction = forward
    }).

-spec event_sink_get_not_empty_history(config()) -> _.
event_sink_get_not_empty_history(C) ->
    ok = start_machine(C, ?ID),

    _ = create_events(3, C, ?ID),

    AllEvents = mg_event_sink_client:get_history(es_opts(C), ?ES_ID, #mg_stateproc_HistoryRange{
        direction = forward
    }),
    GeneratedEvents = [
        E
     || E = #mg_stateproc_SinkEvent{
            source_id = ?ID,
            source_ns = ?NS,
            event = #mg_stateproc_Event{}
        } <- AllEvents
    ],
    ?assert(erlang:length(GeneratedEvents) >= 3).

-spec event_sink_get_last_event(config()) -> _.
event_sink_get_last_event(C) ->
    [
        #mg_stateproc_SinkEvent{
            id = 3,
            source_id = _ID,
            source_ns = _NS,
            event = #mg_stateproc_Event{}
        }
    ] =
        mg_event_sink_client:get_history(es_opts(C), ?ES_ID, #mg_stateproc_HistoryRange{
            direction = backward,
            limit = 1
        }).

-spec event_sink_incorrect_event_id(config()) -> _.
event_sink_incorrect_event_id(C) ->
    #mg_stateproc_EventNotFound{} =
        (catch mg_event_sink_client:get_history(es_opts(C), ?ES_ID, #mg_stateproc_HistoryRange{
            'after' = 42
        })).

-spec event_sink_incorrect_sink_id(config()) -> _.
event_sink_incorrect_sink_id(C) ->
    HRange = #mg_stateproc_HistoryRange{},
    #mg_stateproc_EventSinkNotFound{} =
        (catch mg_event_sink_client:get_history(es_opts(C), <<"incorrect_event_sink_id">>, HRange)).

-spec event_sink_lots_events_ordering(config()) -> _.
event_sink_lots_events_ordering(C) ->
    MachineID = genlib:unique(),
    ok = start_machine(C, MachineID),
    N = 20,
    _ = create_events(N, C, MachineID),

    HRange = #mg_stateproc_HistoryRange{direction = forward},
    Events = mg_event_sink_client:get_history(es_opts(C), ?ES_ID, HRange),
    % event_sink не гарантирует отсутствия дублей событий, но гарантирует
    % сохранения порядка событий отдельной машины.
    lists:foldl(
        fun(Ev, LastEvIDMap) ->
            #mg_stateproc_SinkEvent{
                source_id = Machine,
                source_ns = NS,
                event = Body
            } = Ev,
            Key = {NS, Machine},
            LastID = maps:get(Key, LastEvIDMap, 0),
            case Body#mg_stateproc_Event.id of
                ID when ID =:= LastID + 1 ->
                    LastEvIDMap#{Key => ID};
                ID when ID =< LastID ->
                    % Дубликат одного из уже известных событий
                    LastEvIDMap;
                ID ->
                    % Нарушен порядок событий, получился пропуск
                    erlang:error({invalid_order, ID, LastID}, [Ev, LastEvIDMap])
            end
        end,
        #{},
        Events
    ).

-spec config_with_multiple_event_sinks(config()) -> _.
config_with_multiple_event_sinks(_C) ->
    Config = #{
        woody_server => #{ip => {0, 0, 0, 0, 0, 0, 0, 0}, port => 8022, limits => #{}},
        namespaces => #{
            <<"1">> => #{
                storage => mg_core_storage_memory,
                processor => #{
                    url => <<"http://localhost:8023/processor">>,
                    transport_opts => #{pool => pool1, max_connections => 100}
                },
                default_processing_timeout => 30000,
                schedulers => #{
                    timers => #{},
                    overseer => #{}
                },
                retries => #{},
                event_sinks => [
                    {mg_core_events_sink_machine, #{name => default, machine_id => <<"SingleES">>}}
                ]
            },
            <<"2">> => #{
                storage => mg_core_storage_memory,
                processor => #{
                    url => <<"http://localhost:8023/processor">>,
                    transport_opts => #{pool => pool2, max_connections => 100}
                },
                default_processing_timeout => 5000,
                schedulers => #{
                    timers => #{},
                    overseer => #{}
                },
                retries => #{},
                event_sinks => [
                    {mg_core_events_sink_machine, #{
                        name => machine,
                        machine_id => <<"SingleES">>
                    }},
                    {mg_core_events_sink_kafka, #{
                        name => kafka,
                        topic => <<"mg_core_event_sink">>,
                        client => mg_ct_helper:config(kafka_client_name)
                    }}
                ]
            }
        },
        event_sink_ns => #{
            storage => mg_core_storage_memory,
            default_processing_timeout => 5000
        }
    },
    Apps = mg_ct_helper:start_applications([
        brod,
        woody
    ]),
    {ok, _Pid} = mg_core_utils_supervisor_wrapper:start_link(
        {local, mg_core_sup_does_nothing},
        #{strategy => rest_for_one},
        mg_test_configurator:construct_child_specs(Config)
    ),
    ok = mg_ct_helper:stop_applications(Apps).

%%
%% utils
%%
-spec start_machine(config(), mg_core:id()) -> ok.
start_machine(C, ID) ->
    start_machine(C, ID, ID).

-spec start_machine(config(), mg_core:id(), term()) -> ok.
start_machine(C, ID, Args) ->
    case catch mg_automaton_client:start(automaton_options(C), ID, Args) of
        ok ->
            ok;
        #mg_stateproc_MachineAlreadyExists{} ->
            ok
    end.

-spec create_event(mg_core_storage:opaque(), config(), mg_core:id()) -> _.
create_event(Event, C, ID) ->
    mg_automaton_client:call(automaton_options(C), ID, Event).

-spec create_events(integer(), config(), mg_core:id()) -> _.
create_events(N, C, ID) ->
    lists:foreach(
        fun(I) ->
            I = create_event([<<"event">>, I], C, ID)
        end,
        lists:seq(1, N)
    ).

-spec automaton_options(config()) -> _.
automaton_options(C) -> ?config(automaton_options, C).

-spec es_opts(config()) -> _.
es_opts(C) -> ?config(event_sink_options, C).

-spec no_timeout_automaton_options(config()) -> _.
no_timeout_automaton_options(C) ->
    Options0 = automaton_options(C),
    %% Let's force enlarge client timeout. We expect server timeout only.
    Options0#{transport_opts => #{recv_timeout => ?DEADLINE_TIMEOUT * 10}}.
