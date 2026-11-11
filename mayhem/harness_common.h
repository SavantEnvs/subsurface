// AI-generated (Claude)
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string>

#include <QCoreApplication>

#include "core/divelog.h"
#include "core/errorhelper.h"
#include "core/parse.h"
#include "core/pref.h"
#include "core/tag.h"

// placeholder for Command::changesMade(), needed by the git saver in corelib (as in cli/main.cpp)
namespace Command {
	std::string changesMade() { return {}; }
}

static void quiet_error_cb(std::string) {}

// One-time process setup shared by every harness (mirrors cli/main.cpp without a GUI).
static void subsurface_fuzz_init()
{
	static int argc = 1;
	static char arg0[] = "fuzz";
	static char *argv[] = { arg0, nullptr };
	static QCoreApplication app(argc, argv);
	Q_INIT_RESOURCE(subsurface);
	set_error_cb(quiet_error_cb);
	prefs = default_prefs;
	taglist_init_global();
	parse_xml_init();
}

// Dives hold raw pointers into g_tag_list and register_tag() never removes an entry, so tags parsed from one input
// would stay for the rest of the process. Declared before the local divelog, the guard resets the list after the
// divelog is destroyed, so every input starts from the seeded list. Only harnesses whose importers call
// taglist_add_tag() need it; libdc-parser never registers a tag.
static void subsurface_fuzz_reset()
{
	g_tag_list.clear();
	taglist_init_global();
}

struct subsurface_fuzz_reset_guard {
	~subsurface_fuzz_reset_guard() { subsurface_fuzz_reset(); }
};
