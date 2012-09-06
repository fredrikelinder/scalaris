% @copyright 2009-2012 Zuse Institute Berlin
%    and onScale solutions GmbH

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

%% @author Florian Schintke <schintke@onscale.de>
%% @doc Part of generic transaction implementation -
%%      The state for a single request in a transaction of a TM and RTM.
%% @version $Id$
-module(tx_item_state).
-author('schintke@onscale.de').
-vsn('$Id$').

%-define(TRACE(X,Y), io:format(X,Y)).
-define(TRACE(X,Y), ok).

-include("scalaris.hrl").

%% Operations on tx_item_state
-export([new/1, new/3, new/6]).
-export([get_txid/1]).
-export([get_maj_for_prepared/1, get_maj_for_abort/1]).
-export([get_itemid/1, set_itemid/2]).
-export([get_decided/1]).
-export([set_decided/2]).
-export([inc_numprepared/1, inc_numabort/1]).
-export([newly_decided/1]).
-export([get_paxosids_rtlogs_tps/1,set_paxosids_rtlogs_tps/2]).
-export([set_tp_for_paxosid/3]).
-export([get_status/1, set_status/2]).
-export([hold_back/2, get_hold_back/1, set_hold_back/2]).
-export([get_numcommitted/1]).
-export([add_learner_decide/2]).
-export([add_commit_ack/1]).

-ifdef(with_export_type_support).
-export_type([tx_item_id/0, tx_item_state/0]).
-export_type([paxos_id/0]).
-endif.

-opaque paxos_id() :: {uid:global_uid()}.
-type tx_item_id() :: {?tx_item_id, uid:global_uid()}.
-type tx_item_state() ::
 {
   TxItemId::tx_item_id(), %%  1 id of the item
   ?tx_item_state,     %%  2 tx_item_state, data type tag for debugging
   TxId::tx_state:tx_id() | undefined_tx_id,  %%  3 part of transaction with id TxId
   TLogEntry::tx_tlog:tlog_entry() | empty_tlog_entry, %%  4 corresponding transaction log entry
   Maj_for_prepared::non_neg_integer(), %%  5 prepare votes to decide prepared
   Maj_for_abort::non_neg_integer(), %%  6 abort votes to decide abort
   Decided::false | ?prepared | ?abort, %%  7 current decision status
   Numprepared::non_neg_integer(), %%  8 number of received prepare votes
   Numabort::non_neg_integer(), %%  9 number of received abort votes
   [{paxos_id(), RTLogEntry::tx_tlog:tlog_entry(), TP::comm:mypid() | unknown}], %% 10 involved PaxosIDs
   Status::new | uninitialized | ok, %% 11 item status
   HoldBackQueue::[comm:message()],         %% 12 when not initialized
   NumCommitted::non_neg_integer()  %% 13
 }.

%% @TODO maybe the following entries are also necessary?:
%%      tx_tm_helper_behaviour to use? needed? for what?,
%%      timeout before the first RTM takes over

-spec new(tx_item_id()) -> tx_item_state().
new(ItemId) ->
    ReplDeg = config:read(replication_factor),
    {ItemId, ?tx_item_state, undefined_tx_id, empty_tlog_entry,
     quorum:majority_for_accept(ReplDeg), quorum:majority_for_deny(ReplDeg),
     false, 0, 0, _no_paxIds = [], uninitialized, _HoldBack = [], 0}.

-spec new(tx_item_id(), tx_state:tx_id(), tx_tlog:tlog_entry())
         -> tx_item_state().
new(ItemId, TxId, TLogEntry) ->
    ReplDeg = config:read(replication_factor),
    new(ItemId, TxId, TLogEntry, quorum:majority_for_accept(ReplDeg),
        quorum:majority_for_deny(ReplDeg), unknown).

%% pre: if paxos IDs are given, their order must match the order of the created RTLogEntries!
-spec new(tx_item_id(), tx_state:tx_id(), tx_tlog:tlog_entry(),
          Maj_for_prepared::non_neg_integer(),
          Maj_for_abort::non_neg_integer(), PaxosIds::[paxos_id()] | unknown)
         -> tx_item_state().
new(ItemId, TxId, TLogEntry, Maj_for_prepared, Maj_for_abort, PaxosIds0) ->
    %% expand TransLogEntry to replicated translog entries
    RTLogEntries =
        case tx_tlog:get_entry_operation(TLogEntry) of
            ?read ->
                rdht_tx_read:validate_prefilter(TLogEntry);
            ?write ->
                rdht_tx_write:validate_prefilter(TLogEntry)
        end,
    PaxosIds =
        case PaxosIds0 of
            unknown -> [ {uid:get_global_uid()} || _ <- RTLogEntries ];
%%          unknown -> [ {paxos_id, uid:get_global_uid()} || _ <- RTLogEntries ];
            _ -> PaxosIds0
        end,
    TPs = [ unknown || _ <- PaxosIds ],
    PaxIDsRTLogsTPs = lists:zip3(PaxosIds, RTLogEntries, TPs),
    {ItemId, ?tx_item_state, TxId, TLogEntry,
     Maj_for_prepared, Maj_for_abort,
     false, 0, 0, PaxIDsRTLogsTPs,
     uninitialized, _HoldBack = [], 0}.

-spec get_itemid(tx_item_state()) -> tx_item_id().
get_itemid(State) ->         element(1, State).
-spec set_itemid(tx_item_state(), tx_item_id()) -> tx_item_state().
set_itemid(State, Val) ->    setelement(1, State, Val).
-spec get_txid(tx_item_state()) -> tx_state:tx_id() | undefined_tx_id.
get_txid(State) ->           element(3, State).
-spec get_maj_for_prepared(tx_item_state()) -> non_neg_integer().
get_maj_for_prepared(State) -> element(5, State).
-spec get_maj_for_abort(tx_item_state()) -> non_neg_integer().
get_maj_for_abort(State) ->  element(6, State).
-spec get_decided(tx_item_state()) -> false | ?prepared | ?abort.
get_decided(State) ->        element(7, State).
-spec set_decided(tx_item_state(), false | ?prepared | ?abort) -> tx_item_state().
set_decided(State, Val) ->   setelement(7, State, Val).
-spec get_numprepared(tx_item_state()) -> non_neg_integer().
get_numprepared(State) ->    element(8, State).
-spec inc_numprepared(tx_item_state()) -> tx_item_state().
inc_numprepared(State) ->    setelement(8, State, element(8,State) + 1).
-spec get_numabort(tx_item_state()) -> non_neg_integer().
get_numabort(State) ->       element(9, State).
-spec inc_numabort(tx_item_state()) -> tx_item_state().
inc_numabort(State) ->       setelement(9, State, element(9,State) + 1).

-spec get_paxosids_rtlogs_tps(tx_item_state()) ->
                                     [{paxos_id(), tx_tlog:tlog_entry(),
                                       comm:mypid() | unknown}].
get_paxosids_rtlogs_tps(State) -> element(10, State).
-spec set_paxosids_rtlogs_tps(tx_item_state(), [{paxos_id(), tx_tlog:tlog_entry(), comm:mypid()}]) -> tx_item_state().
set_paxosids_rtlogs_tps(State, NewTPList) -> setelement(10, State, NewTPList).

-spec get_status(tx_item_state()) -> new | uninitialized | ok.
get_status(State) ->         element(11, State).
-spec set_status(tx_item_state(), new | uninitialized | ok) -> tx_item_state().
set_status(State, Status) -> setelement(11, State, Status).
-spec hold_back(comm:message(), tx_item_state()) -> tx_item_state().
hold_back(Msg, State) ->     setelement(12, State, [Msg | element(12, State)]).
-spec get_hold_back(tx_item_state()) -> [comm:message()].
get_hold_back(State) ->      element(12, State).
-spec set_hold_back(tx_item_state(), [comm:message()]) -> tx_item_state().
set_hold_back(State, Queue) -> setelement(12, State, Queue).

-spec get_numcommitted(tx_item_state()) -> non_neg_integer().
get_numcommitted(State) ->    element(13, State).
-spec inc_numcommitted(tx_item_state()) -> tx_item_state().
inc_numcommitted(State) ->       setelement(13, State, element(13,State) + 1).

-spec newly_decided(tx_item_state()) -> false | ?prepared | ?abort.
newly_decided(State) ->
    case get_decided(State) of
        false ->
            Prepared = get_numprepared(State) =:= get_maj_for_prepared(State),
            Abort =    get_numabort(State) =:= get_maj_for_abort(State),
            if Prepared andalso not Abort -> ?prepared;
               not Prepared andalso Abort -> ?abort;
               true -> false
            end;
        _Any -> false
    end.

-spec set_tp_for_paxosid(tx_item_state(), comm:mypid(), paxos_id()) -> tx_item_state().
set_tp_for_paxosid(State, TP, PaxosId) ->
    TPList = get_paxosids_rtlogs_tps(State),
    NewTPList = util:lists_keystore2(PaxosId, 1, TPList, 3, TP),
    set_paxosids_rtlogs_tps(State, NewTPList).

-spec add_learner_decide(tx_item_state(),
                         {learner_decide, tx_item_id(),
                          paxos_id(), ?prepared | ?abort}) ->
                                {hold_back
                                 | state_updated
                                 | {item_newly_decided, ?prepared | ?abort},
                                 tx_item_state()}.
add_learner_decide(State, {learner_decide, _ItemId, _PaxosID, Value} = Msg) ->
    case ok =/= get_status(State) of
        true -> %% new | uninitialized
            TmpState = tx_item_state:hold_back(Msg, State),
            NewState = tx_item_state:set_status(TmpState, uninitialized),
            {hold_back, NewState};
        false -> %% ok
            TmpState =
                case Value of
                    ?prepared -> tx_item_state:inc_numprepared(State);
                    ?abort ->    tx_item_state:inc_numabort(State)
                end,
            case newly_decided(TmpState) of
                false -> {state_updated, TmpState};
                Decision ->
                    NewState = set_decided(TmpState, Decision),
                    {{item_newly_decided, Decision}, NewState}
            end
    end.

-spec add_commit_ack(tx_item_state()) ->
                            {item_newly_safe | state_updated,
                            tx_item_state()}.
add_commit_ack(State) ->
    NewState = inc_numcommitted(State),
    Maj = get_maj_for_prepared(NewState),
    case get_numcommitted(NewState) of
        Maj -> {item_newly_safe, NewState};
        _   -> {state_updated, NewState}
    end.
