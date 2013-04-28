-module(mover_solr_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ROLE,
        {[{<<"name">>,<<"web_role">>},
          {<<"description">>,<<"something something">>},
          {<<"json_class">>,<<"Chef::Role">>},
          {<<"chef_type">>,<<"role">>},
          {<<"default_attributes">>,
           {[{<<"test1">>,1},{<<"test2">>,<<"2">>}]}},
          {<<"override_attributes">>,
           {[{<<"test1">>,8},{<<"rideover">>,<<"10-4">>}]}},
          {<<"run_list">>,[<<"apache2">>,<<"php">>]},
          {<<"env_run_lists">>,
           {[{<<"prod">>,[<<"nginx">>]}]}}]}).

-define(DB_ITEM,
        {[
          {<<"data_bag">>, <<"sport-balls">>},
          {<<"chef_type">>, <<"data_bag_item">>},
          {<<"soccerballs">>, 2},
          {<<"baseballs">>, 4},
          {<<"id">>, <<"balls">>},
          {<<"footballs">>, {[
                              {<<"round">>, 2},
                              {<<"egg">>, 18}
                             ]}}
         ]}).

flatten_non_recursive_type_test() ->
    Input = {[{<<"a_null">>, null},
              {<<"a_true">>, true},
              {<<"a_false">>, false},
              {<<"a_int">>, 2},
              {<<"a_float">>, 1.23},
              {<<"a_string">>, <<"hello">>}
             ]},
    Expanded = mover_solr:flatten(Input),
    %% Expected final result when flattened should be space separated
    %% as below. Formatting of floats is tricky. We should investigate
    %% what the Ruby code does.
    Expect = <<"a_false__=__false "
               "a_float__=__1.23000000000000 "
               "a_int__=__2 "
               "a_null__=__null "
               "a_string__=__hello "
               "a_true__=__true ">>,
    ?assertEqual(Expect, iolist_to_binary(Expanded)).

flatten_lists_test() ->
    Input = {[{<<"k1">>, [null, true, false,
                          <<"a">>, 0, 1.123,
                          [<<"b">>, 2], <<"c">>]}]},
    Expanded = mover_solr:flatten(Input),
    Expect = <<"k1__=__0 k1__=__1.12300000000000 "
               "k1__=__2 k1__=__a k1__=__b k1__=__c "
               "k1__=__false k1__=__null k1__=__true ">>,
    ?assertEqual(Expect, iolist_to_binary(Expanded)).

flatten_nested_test() ->
    Input = {[
              {<<"k1">>, [<<"a1">>, <<"a2">>, [<<"aa1">>, <<"aa2">>]]},
              {<<"k2">>, 5},
              {<<"k3">>, {[{<<"kk1">>, <<"h">>},
                           {<<"kk2">>, [1, 2]},
                           {<<"kk3">>, {[
                                         {<<"kkk1">>, true},
                                         {<<"kkk2">>, <<"i<&>">>},
                                         {<<"kk&k3">>, [<<"j">>,
                                                        {[
                                                          {<<"lkk<>k1">>, 1},
                                                          {<<"lkkk2">>, 2}
                                                         ]}]}
                                        ]}}
                          ]}}]},
    Expect =  <<"k1__=__a1 "
                "k1__=__a2 "
                "k1__=__aa1 "
                "k1__=__aa2 "
                "k2__=__5 "
                "k3_kk1__=__h "
                "k3_kk2__=__1 "
                "k3_kk2__=__2 "
                "k3_kk3_kk&amp;k3__=__j "
                "k3_kk3_kk&amp;k3_lkk&lt;&gt;k1__=__1 "
                "k3_kk3_kk&amp;k3_lkkk2__=__2 "
                "k3_kk3_kkk1__=__true "
                "k3_kk3_kkk2__=__i&lt;&amp;&gt; "
                "kk&amp;k3__=__j "
                "kk1__=__h "
                "kk2__=__1 "
                "kk2__=__2 "
                "kkk1__=__true "
                "kkk2__=__i&lt;&amp;&gt; "
                "lkk&lt;&gt;k1__=__1 "
                "lkkk2__=__2 ">>,
    ?assertEqual(Expect, iolist_to_binary(mover_solr:flatten(Input))).

flatten_and_xml_escape_test() ->
    Input = {[
              {<<"A & W">>, <<"The \"question\" is < > !&">>}
             ]},
    Expect = <<"A &amp; W__=__The \"question\" is &lt; &gt; !&amp; ">>,
    ?assertEqual(Expect, iolist_to_binary(mover_solr:flatten(Input))).

make_command_role_test_() ->
    Cmd = mover_solr:make_command(add, role, <<"abc123">>, <<"dbdb1212">>, ?ROLE),

    Payload = ej:get({<<"payload">>}, Cmd),
    [?_assertEqual(<<"add">>, ej:get({<<"action">>}, Cmd)),
     ?_assert(is_integer(ej:get({<<"enqueued_at">>}, Payload))),
     ?_assertEqual(<<"role">>, ej:get({<<"type">>}, Payload)),
     ?_assertEqual(<<"abc123">>, ej:get({<<"id">>}, Payload)),
     ?_assertEqual(<<"chef_dbdb1212">>, ej:get({<<"database">>}, Payload)),
     ?_assertEqual(?ROLE, ej:get({<<"item">>}, Payload))
    ].

post_single_test_() ->
    MinItem = {[{<<"key1">>, <<"value1">>},
                {<<"key2">>, <<"value2">>}]},
    {setup,
     fun() ->
             meck:new(ibrowse, [])
     end,
     fun(_) ->
             meck:unload()
     end,
     [{"happy path add post_single",
       fun() ->
               Cmd = mover_solr:make_command(add, role, <<"abc123">>,
                                             "dbdb1212", MinItem),

               Expect = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                          "<add><doc>"
                          "<field name=\"X_CHEF_id_CHEF_X\">abc123</field>"
                          "<field name=\"X_CHEF_database_CHEF_X\">chef_dbdb1212</field>"
                          "<field name=\"X_CHEF_type_CHEF_X\">role</field>"
                          "<field name=\"content\">key1__=__value1 key2__=__value2 </field>"
                          "</doc></add>">>,
               meck:expect(ibrowse, send_req,
                           fun(Url, Headers, post, Doc) ->
                                   ?assertEqual("http://localhost:8983/update", Url),
                                   ?assertEqual([{"Content-Type", "text/xml"}], Headers),
                                   ?assertEqual(Expect, Doc),
                                   {ok, "200", [], []}
                           end),
               ?assertEqual(ok, mover_solr:post_single(Cmd))
       end},

      {"happy path delete post_single",
       fun() ->
               Cmd = mover_solr:make_command(delete, role, <<"abc123">>,
                                             "dbdb1212", {[]}),

               Expect = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                          "<delete><id>abc123</id></delete>\n">>,
               meck:expect(ibrowse, send_req,
                           fun(Url, Headers, post, Doc) ->
                                   ?assertEqual("http://localhost:8983/update", Url),
                                   ?assertEqual([{"Content-Type", "text/xml"}], Headers),
                                   ?assertEqual(Expect, Doc),
                                   {ok, "200", [], []}
                           end),
               ?assertEqual(ok, mover_solr:post_single(Cmd))
       end},

      {"special handling for data bag items",
       fun() ->
               Cmd = mover_solr:make_command(add, data_bag_item, <<"abc123">>,
                                             "dbdb1212", ?DB_ITEM),

               Expect = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                          "<add>"
                          "<doc>"
                          "<field name=\"X_CHEF_id_CHEF_X\">abc123</field>"
                          "<field name=\"X_CHEF_database_CHEF_X\">chef_dbdb1212</field>"
                          "<field name=\"X_CHEF_type_CHEF_X\">data_bag_item</field>"
                          "<field name=\"data_bag\">sport-balls</field>"
                          "<field name=\"content\">"
                          "baseballs__=__4 "
                          "chef_type__=__data_bag_item "
                          "data_bag__=__sport-balls "
                          "egg__=__18 footballs_egg__=__18 "
                          "footballs_round__=__2 "
                          "id__=__balls "
                          "round__=__2 "
                          "soccerballs__=__2 "
                          "</field>"
                          "</doc>"
                          "</add>">>,
               meck:expect(ibrowse, send_req,
                           fun(Url, Headers, post, Doc) ->
                                   ?assertEqual("http://localhost:8983/update", Url),
                                   ?assertEqual([{"Content-Type", "text/xml"}], Headers),
                                   ?assertEqual(Expect, Doc),
                                   {ok, "200", [], []}
                           end),
               ?assertEqual(ok, mover_solr:post_single(Cmd))
       end},

      {"bogus action is skipped",
       fun() ->
               Cmd = mover_solr:make_command(bogus, role, <<"abc123">>,
                                             "chef_dbdb1212", MinItem),
               ?assertEqual(skip, mover_solr:post_single(Cmd))
       end},

      {"error from ibrowse",
       fun() ->
               Cmd = mover_solr:make_command(add, role, <<"abc123">>,
                                             "dbdb1212", MinItem),
               meck:expect(ibrowse, send_req,
                           fun(_Url, _Headers, post, _Doc) ->
                                   {ok, "500", [], <<"oh no">>}
                           end),
               ?assertEqual({error, "500", <<"oh no">>}, mover_solr:post_single(Cmd))
       end}
     ]}.

post_multi_test_() ->
    MinItem = {[{<<"key1">>, <<"value1">>},
                {<<"key2">>, <<"value2">>}]},
    Cmds = [mover_solr:make_command(add, role, <<"a1">>, "db1", MinItem),
            mover_solr:make_command(add, role, <<"a2">>, "db2", MinItem),
            mover_solr:make_command(bogus, role, <<"a3">>, "db2", MinItem),
            mover_solr:make_command(bogus, role, <<"a4">>, "db2", MinItem),
            mover_solr:make_command(delete, role, <<"a5">>, "db3", {[]})],
    {setup,
     fun() ->
             meck:new(ibrowse, [])
     end,
     fun(_) ->
             meck:unload()
     end,
     [{"happy path mix post_multi",
       fun() ->
               %% See http://wiki.apache.org/solr/UpdateXmlMessages
               %% for expected format of mixed add/delete POSTs
               Expect = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                          "<update>"
                          "<delete>"
                          "<id>a5</id>"
                          "</delete>\n"
                          "<add>"

                          "<doc>"
                          "<field name=\"X_CHEF_id_CHEF_X\">a2</field>"
                          "<field name=\"X_CHEF_database_CHEF_X\">chef_db2</field>"
                          "<field name=\"X_CHEF_type_CHEF_X\">role</field>"
                          "<field name=\"content\">key1__=__value1 key2__=__value2 </field>"
                          "</doc>"

                          "<doc>"
                          "<field name=\"X_CHEF_id_CHEF_X\">a1</field>"
                          "<field name=\"X_CHEF_database_CHEF_X\">chef_db1</field>"
                          "<field name=\"X_CHEF_type_CHEF_X\">role</field>"
                          "<field name=\"content\">key1__=__value1 key2__=__value2 </field>"
                          "</doc>"
                          "</add>"
                          "</update>">>,
               meck:expect(ibrowse, send_req,
                           fun(Url, Headers, post, Doc) ->
                                   ?assertEqual("http://localhost:8983/update", Url),
                                   ?assertEqual([{"Content-Type", "text/xml"}], Headers),
                                   ?assertEqual(Expect, Doc),
                                   {ok, "200", [], []}
                           end),
               ?assertEqual(ok, mover_solr:post_multi(Cmds))
       end},

      {"all empty post_multi",
       fun() ->
               AllBogus = [mover_solr:make_command(bogus, role, <<"a3">>, "db2", MinItem),
                           mover_solr:make_command(bogus, role, <<"a4">>, "db2", MinItem)],
               ?assertEqual(skip, mover_solr:post_multi(AllBogus))
       end}

      ]}.

%% TODO:
%% - test data bag special case
%% - test empty multi
