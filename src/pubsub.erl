%%% Copyright (c) 2009 Oortle, Inc

%%% Permission is hereby granted, free of charge, to any person 
%%% obtaining a copy of this software and associated documentation 
%%% files (the "Software"), to deal in the Software without restriction, 
%%% including without limitation the rights to use, copy, modify, merge, 
%%% publish, distribute, sublicense, and/or sell copies of the Software, 
%%% and to permit persons to whom the Software is furnished to do so, 
%%% subject to the following conditions:

%%% The above copyright notice and this permission notice shall be included 
%%% in all copies or substantial portions of the Software.

%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
%%% OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
%%% THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
%%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
%%% DEALINGS IN THE SOFTWARE.

-module(pubsub).

-export([publish/2, subscribe/3, unsubscribe/2,
         start/1, stop/1]).

-export([init/1, handle_call/3, handle_cast/2, 
         handle_info/2, terminate/2, code_change/3]).

-record(state, {
          topic,
          subs = ets:new(subs, [set, public])
         }).

publish(Ref, Msg) ->
    gen_server:cast(Ref, {publish, Msg}).

subscribe(Ref, Pid, Socket) ->
    gen_server:cast(Ref, {subscribe, Pid, Socket}).

unsubscribe(Ref, Pid) ->
    gen_server:cast(Ref, {unsubscribe, Pid}).

start(Topic) ->
    gen_server:start_link(?MODULE, [Topic], []).

stop(Ref) ->
    gen_server:cast(Ref, stop).

init([Topic]) ->
    process_flag(trap_exit, true),
    {ok, #state{topic = Topic}}.

handle_cast(stop, State) ->
    {stop, normal, State};

handle_cast({subscribe, Pid, Socket}, State) ->
  %% automatically unsubscribe when dead
  Ref = erlang:monitor(process, Pid),
  Pid ! ack,
  ets:insert(State#state.subs, {Pid, Ref, Socket}),
  {noreply, State};

handle_cast({unsubscribe, Pid}, State) ->
    unsubscribe1(Pid, State);

handle_cast({publish, Msg}, State) ->
    io:format("info: ~p~n", [ets:info(State#state.subs)]),
    Start = now(),
    {struct, L} = Msg,
    JSON = {struct, [{<<"timestamp">>, binary_to_list(term_to_binary(now()))}|L]},
    Bin = mochijson2:encode(JSON),
    %% F = fun({Pid, _}, _) -> gen_server:cast(Pid, Msg1) end,
    F = fun({_Pid, _, Socket}, _) ->
        gen_tcp:send(Socket, [Bin, 1])
      end,
    process_flag(priority, high),
    ets:foldr(F, ignore, State#state.subs),
    io:format("time: ~p~n", [timer:now_diff(now(), Start) / 1000]),
    ets:delete_all_objects(State#state.subs),
    process_flag(priority, normal),
    {noreply, State};

handle_cast(Event, State) ->
    {stop, {unknown_cast, Event}, State}.

handle_call(Event, From, State) ->
    {stop, {unknown_call, Event, From}, State}.

handle_info({'EXIT', _Pid, normal}, State) ->
    {noreply, State};

handle_info({'DOWN', _, process, Pid, _}, State) ->
    unsubscribe1(Pid, State);

handle_info(Info, State) ->
    {stop, {unknown_info, Info}, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

unsubscribe1(Pid, State) ->
    case ets:lookup(State#state.subs, Pid) of
        [{_, Ref}] ->
            erlang:demonitor(Ref),
            ets:delete(State#state.subs, Pid);
        _ ->
            ok
    end,
    {noreply, State}.

