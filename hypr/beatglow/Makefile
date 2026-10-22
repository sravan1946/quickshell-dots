# Rebuild after every Hyprland update (the plugin refuses to load against a different one).
# version.h changes with every Hyprland release, so `make` notices one on its own.
# `make load` also swaps it into the running Hyprland.
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b --no-gnu-unique
HYPR_VERSION_H := $(shell pkg-config --variable=prefix hyprland)/hyprland/src/version.h
# Hyprland knows a plugin by the exact path it was loaded from: the README's symlink, if there
PLUGIN ?= $(or $(wildcard $(HOME)/.config/hypr/plugins/beatglow/beatglow.so),$(CURDIR)/beatglow.so)

beatglow.so: main.cpp $(wildcard $(HYPR_VERSION_H))
	$(CXX) $(CXXFLAGS) $(LDFLAGS) main.cpp -o $@.tmp `pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`
	mv $@.tmp $@   # a new inode: never rewrite the .so Hyprland has mapped

load: beatglow.so
	-hyprctl plugin unload "$(PLUGIN)" >/dev/null
	hyprctl plugin load "$(PLUGIN)"

clean:
	rm -f beatglow.so beatglow.so.tmp

.PHONY: load clean
