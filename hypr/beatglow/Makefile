# The plugin only loads into the exact Hyprland it was built against, so every build is kept as
# beatglow-<commit>.so (the last three): an upgrade installs a new Hyprland while the old one
# keeps running until you log out, and the build that fits the running one has to survive that.
#   make          builds for the installed Hyprland; beatglow.so (what hyprland.lua loads at
#                 login) is a copy of that build
#   make load     swaps the build that fits the RUNNING Hyprland into it, building one first
#                 when there's none (`make running`); never unloads the old one for a misfit
#   make running  builds for the running Hyprland from that release's headers (Arch archive)
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b --no-gnu-unique
DEPS := pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon
HYPR_VERSION_H := $(shell pkg-config --variable=prefix hyprland)/hyprland/src/version.h
COMMIT := $(shell sed -n 's/.*GIT_COMMIT_HASH *"\([0-9a-f]\{8\}\).*/\1/p' $(HYPR_VERSION_H))
RUNNING = $(shell hyprctl version -j | jq -r '.commit[0:8]')
RUNNING_TAG = $(shell hyprctl version -j | jq -r '.tag | ltrimstr("v")')
# Hyprland knows a plugin by the exact path it was loaded from: the README's symlinked folder, if there
PLUGDIR ?= $(if $(wildcard $(HOME)/.config/hypr/plugins/beatglow/main.cpp),$(HOME)/.config/hypr/plugins/beatglow,$(CURDIR))
KEEP = ls -t beatglow-*.so | tail -n +4 | xargs -r rm -f

beatglow.so: beatglow-$(COMMIT).so
	cp $< $@.tmp && mv $@.tmp $@   # a new inode: never rewrite a .so Hyprland has mapped

beatglow-$(COMMIT).so: main.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) main.cpp -o $@.tmp `pkg-config --cflags $(DEPS)`
	mv $@.tmp $@
	$(KEEP)

# that release's headers, fetched once into ~/.cache/beatglow/<commit> (the package is ~50 MB)
HDRS = $(HOME)/.cache/beatglow/$(RUNNING)
running:
	@[ -f beatglow-$(RUNNING).so ] && [ beatglow-$(RUNNING).so -nt main.cpp ] && exit 0; \
	if [ "$(RUNNING)" = "$(COMMIT)" ]; then $(MAKE) -s beatglow-$(COMMIT).so; exit; fi; \
	if [ ! -f "$(HDRS)/usr/include/hyprland/src/version.h" ]; then \
		echo "fetching Hyprland $(RUNNING_TAG)'s headers"; rm -rf "$(HDRS)"; mkdir -p "$(HDRS)" && \
		curl -sfL "https://archive.archlinux.org/packages/h/hyprland/hyprland-$(RUNNING_TAG)-1-x86_64.pkg.tar.zst" | tar --zstd -xf - -C "$(HDRS)" usr/include/hyprland || { rm -rf "$(HDRS)"; exit 1; }; \
	fi; \
	grep -q '"$(RUNNING)' "$(HDRS)/usr/include/hyprland/src/version.h" || { echo "the archive's $(RUNNING_TAG) isn't the running commit $(RUNNING)"; rm -rf "$(HDRS)"; exit 1; }; \
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -I"$(HDRS)/usr/include" main.cpp -o beatglow-$(RUNNING).so.tmp \
		`pkg-config --cflags $(DEPS) | sed "s#-I/usr/include/hyprland#-I$(HDRS)/usr/include/hyprland#g"` && \
	mv beatglow-$(RUNNING).so.tmp beatglow-$(RUNNING).so && $(KEEP)

load: beatglow.so running
	@for f in $(PLUGDIR)/beatglow*.so; do hyprctl plugin unload "$$f" >/dev/null 2>&1; done; \
	hyprctl plugin load "$(PLUGDIR)/beatglow-$(RUNNING).so"

clean:
	rm -f beatglow-*.so *.tmp

.PHONY: running load clean
