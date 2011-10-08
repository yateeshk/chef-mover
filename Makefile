REBAR=rebar
DEPS = deps/ibrowse deps/chef_common

all: compile eunit

clean:
	@rebar clean

distclean:
	@rebar skip_deps=true clean
	@rm -rf deps rel/mover

compile: $(DEPS)
	@rebar compile
	@dialyzer -Wrace_conditions -Wunderspecs -r ebin

$(DEPS):
	@rebar get-deps

eunit: compile
	@rebar skip_deps=true eunit

test: eunit

munge_apps:
	@mkdir -p rel/apps/mover
	@ln -sf `pwd`/ebin rel/apps/mover
	@ln -sf `pwd`/priv rel/apps/mover
	@cp rebar.config rel
	@echo '{deps_dir, ["../deps"]}.' >> rel/rebar.config

rel: compile munge_apps
	@cd rel;$(REBAR) generate
	@rm -rf rel/apps rel/rebar.config
	@echo '   \ \  / /      / __ \    ) )  ( (   / ___/  (   __ \   '
	@echo '   () \/ ()     / /  \ \  ( (    ) ) ( (__     ) (__) )  '
	@echo '   / _  _ \    ( ()  () )  \ \  / /   ) __)   (    __/   '
	@echo '  / / \/ \ \   ( ()  () )   \ \/ /   ( (       ) \ \  _  '
	@echo ' /_/      \_\   \ \__/ /     \  /     \ \___  ( ( \ \_)) '
	@echo '(/          \)   \____/       \/       \____\  )_) \__/  '

relclean:
	@rm -rf rel/mover
	@rm -rf rel/apps

update:
	@cd rel/mover;bin/mover restart

devrel: rel
	@/bin/echo -n Symlinking deps and apps into release
	@$(foreach dep,$(wildcard deps/*), /bin/echo -n .;rm -rf rel/mover/lib/$(shell basename $(dep))-* \
           && ln -sf $(abspath $(dep)) rel/mover/lib;)
	@rm -rf rel/mover/lib/mover-*;mkdir -p rel/mover/lib/mover
	@ln -sf `pwd`/ebin rel/mover/lib/mover
	@ln -sf `pwd`/priv rel/mover/lib/mover
	@/bin/echo done.
	@/bin/echo  Run \'make update\' to pick up changes in a running VM.