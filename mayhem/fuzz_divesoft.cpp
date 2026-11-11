// AI-generated (Claude)
// Divesoft Freedom .dlf importer
#include "harness_common.h"
#include "core/file.h"


extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	subsurface_fuzz_init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size == 0)
		return -1;
	std::string buf((const char *)data, size);
	subsurface_fuzz_reset_guard reset_guard;
	struct divelog log;
	divesoft_import(buf, &log);
	return 0;
}
