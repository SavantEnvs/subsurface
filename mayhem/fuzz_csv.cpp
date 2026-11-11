// AI-generated (Claude)
// CSV (depth/temperature/pressure and Poseidon) importers
#include "harness_common.h"
#include "core/file.h"
#include "core/import-csv.h"

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
	// the first byte picks the CSV flavour, the rest is the file
	enum csv_format type = (enum csv_format)((unsigned char)buf[0] % (POSEIDON_CEILING + 1));
	buf.erase(0, 1);
	try_to_open_csv(buf, type, &log);
	return 0;
}
