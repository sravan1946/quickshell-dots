# Rebuild after every Hyprland update (the plugin refuses to load against a different one).
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b --no-gnu-unique

beatglow.so: main.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) main.cpp -o $@ `pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`

clean:
	rm -f beatglow.so
