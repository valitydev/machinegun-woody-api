%%%
%%% Copyright 2019 RBKmoney
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

%%% Squad behaviour
%%%
%%% A squad is a group of processes (usually distributed over a cluster of
%%% nodes) with dynamic membership which choose a leader among themselves
%%% in a simple yet only eventually consistent manner.
-module(mg_gen_squad_pulse).

-callback handle_beat(_Options, beat()) ->
    _.

%% TODO remove weak circular deps
-type beat() ::
    {rank,
        {changed, mg_gen_squad:rank()}} |
    {{member, pid()},
        {added, mg_gen_squad:member()} |
        {refreshed, mg_gen_squad:member()} |
        {removed, _Reason :: lost | {down, _}}} |
    {{broadcast, mg_gen_squad:payload()},
        {sent, pid()} |
        received} |
    {{timer, reference()},
        {started, _Timeout :: non_neg_integer(), _Msg} |
        cancelled |
        {fired, _Msg}} |
    {{monitor, reference()},
        {started, pid()} |
        cancelled |
        {fired, pid(), _Reason}}.

-type handler() :: mg_utils:mod_opts().

-export_type([beat/0]).
-export_type([handler/0]).

-export([handle_beat/2]).

%%

-spec handle_beat(handler(), any()) ->
    _.
handle_beat(Handler, Beat) ->
    {Mod, Options} = mg_utils:separate_mod_opts(Handler),
    Mod:handle_beat(Options, Beat).
