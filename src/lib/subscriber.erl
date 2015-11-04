%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% FILE: subscriber.erl
%
% AUTHOR: Jake Breindel
% DATE: 11-2-15
%
% DESCRIPTION:
%
% Subscribes to events from the websocket
% and to the manager.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(subscriber).
-export([pid_name/1, alive/1, start/2, loop/2]).
-include("download_status.hrl").

pid_name(Account) ->
	list_to_atom(Account:id() ++ "-subscriber").

notify_manager(Manager, Data) ->
	case is_pid(Manager) of
		true ->
			erlang:display({notify_manager, Data}),
			Manager ! Data;
		false ->
			false
	end.

alive(Account) ->
	SubscriberName = pid_name(Account),
	case whereis(SubscriberName) of 
		undefined ->
			false;
		Pid ->
			Pid
	end.

start(Account, WebSocket) ->
	erlang:display({subscriber_start, WebSocket}),
	case alive(Account) of 
		false ->
			erlang:process_flag(trap_exit, true),
			SubscriberPid = erlang:spawn_link(?MODULE, loop, [Account, WebSocket]),
			receive
		        {'EXIT', SubscriberPid, normal} -> % not a crash
		            {noreply, undefined};
		        {'EXIT', SubscriberPid, shutdown} -> % manual shutdown, not a crash
		            {noreply, undefined};
		        {'EXIT', SubscriberPid, _} ->
		            start(Account, WebSocket)
    		end;
		Pid ->
			erlang:display({pid, Pid}),
			{noreply, undefined}
	end.

loop(Account, WebSocket) ->
	register(pid_name(Account), self()),
	ManagerName = manager:pid_name(Account),
	case whereis(ManagerName) of
		undefined ->
			ManagerPid = spawn(manager, loop, [Account, Subscriber]),
			loop(Account, WebSocket, ManagerPid);
		Manager ->
			notify_manager(Manager, {subscriber_connect, self()}),
			loop(Account, WebSocket, Manager)
	end.

loop(Account, WebSocket, Manager) ->
	receive
		
		%%%%%%%%%%%%%%%%%%%%%
		%% Client Messages %%
		%%%%%%%%%%%%%%%%%%%%%
		
		{websocket_message, Message} ->
			erlang:display({websocket_message, Message}),
			case mochijson:decode(binary_to_list(Message)) of
				{struct, [{"downloads", {array, DownloadsArray}}]} ->
					notify_manager(Manager, {subscriber_downloads, DownloadsArray});
				{struct, [{"refresh", _}]} ->
					notify_manager(Manager, {subscriber_refresh, undefined});
				Json ->
					erlang:display(Json)
			end;
		
		{websocket_close, _} ->
			notify_manager(Manager, {subscriber_disconnect, undefined}),
			kill;
		
		%%%%%%%%%%%%%%%%%%%%%%
		%% Manager Messages %%
		%%%%%%%%%%%%%%%%%%%%%%

		{manager_downloads, Downloads} ->
			erlang:display({manager_downloads, Downloads});

		_ ->
			erlang:display("Message")
	end,
	loop(Account, WebSocket, Manager).
	