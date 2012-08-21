%  @copyright 2010-2012 Zuse Institute Berlin
%  @end
%
%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.
%%%-------------------------------------------------------------------
%%% File    tester_global_state.erl
%%% @author Thorsten Schuett <schuett@zib.de>
%%% @doc    global state for tester
%%% @end
%%% Created :  17 Aug 2012 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @version $Id$
-module(tester_global_state).

-author('schuett@zib.de').
-vsn('$Id$').

-export([register_type_checker/3,
         unregister_type_checker/1,
         get_type_checker/1,
         register_value_creator/4,
         unregister_value_creator/1,
         get_value_creator/1]).

-include("tester.hrl").
-include("unittest.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% handle global state, e.g. specific handlers
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

register_type_checker(Type, Module, Fun) ->
    insert({type_checker, Type}, {Module, Fun}).

unregister_type_checker(Type) ->
    delete({type_checker, Type}).

get_type_checker(Type) ->
    lookup({type_checker, Type}).

register_value_creator(Type, Module, Function, Arity) ->
    insert({value_creator, Type}, {Module, Function, Arity}).

unregister_value_creator(Type) ->
    delete({value_creator, Type}).

get_value_creator(Type) ->
    lookup({value_creator, Type}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% create and query ets-table
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec lookup(any()) -> failed | any().
lookup(Key) ->
    check_whether_table_exists(),
    case ets:lookup(?MODULE, Key) of
        [{Key, Value}] -> Value;
        [] -> failed
    end.

insert(Key, Value) ->
    check_whether_table_exists(),
    ets:insert(?MODULE, {Key, Value}).

delete(Key) ->
    check_whether_table_exists(),
    ets:delete(?MODULE, Key).

check_whether_table_exists() ->
    case ets:info(?MODULE) of
        undefined -> create_table();
        _ -> ok
    end.

create_table() ->
    P = self(),
    spawn(
      fun() ->
              _ = try ets:new(?MODULE, [set, public, named_table])
                  catch
                      % is there a race-condition?
                      Error:Reason ->
                          case ets:info(?MODULE) of
                              undefined ->
                                  ?ct_fail("could create ets table for tester_global_state: ~p:~p",
                                           [Error, Reason]);
                              _ ->
                                  ok
                          end
                  end,
              P ! go,
              util:sleep_for_ever()
      end),
    receive
        go ->
            ok
    end,
    ok.
