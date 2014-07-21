-module(mover_org_user_invites_migration_callback).

-export([
	 migration_init/0,
	 migration_type/0,
	 supervisor/0,
	 migration_start_worker_args/2,
	 error_halts_migration/0,
	 reconfigure_object/2,
	 migration_action/2,
	 next_object/0
	]).

-include("mover.hrl").
-include_lib("moser/include/moser.hrl").

migration_init() ->
    AcctInfo = moser_acct_processor:open_account(),
    AllUserOrgAssoc = moser_acct_processor:all_org_association_data(AcctInfo, association_request),
    mover_transient_migration_queue:initialize_queue(?MODULE, AllUserOrgAssoc).

migration_start_worker_args(Object, AcctInfo) ->
    [Object, AcctInfo].

migration_action(Object, AcctInfo) ->
    {UserGuid, OrgGuid, LastUpdatedBy, UserBody} = Object,
    try
	OrgInfo = moser_acct_processor:expand_org_info(#org_info{org_id = OrgGuid, account_info = AcctInfo}),
	moser_org_converter:insert_org_user_invite(OrgInfo, UserGuid, OrgGuid, LastUpdatedBy, UserBody)
    catch
	Exception:Reason ->
	    lager:error("org_user_invites_failure org_id: ~p user_id: ~p Exception: ~p Reason: ~p Stacktrace: ~p ~n",
			[OrgGuid, UserGuid, Exception, Reason, erlang:get_stacktrace()])
    end,
    ok.

next_object() ->
    mover_transient_migration_queue:next(?MODULE).

migration_type() ->
    <<"org_user_invites_migration">>.

supervisor() ->
    mover_transient_worker_sup.

error_halts_migration() ->
    true.

reconfigure_object(_ObjectId, _AcctInfo) ->
    no_op.