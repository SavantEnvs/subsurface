// AI-generated (Claude)
// DataTrak / WLog .log importer
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
	// first two bytes: little-endian length of the DataTrak log; the remainder is the optional WLog .add file
	if (size < 2)
		return -1;
	size_t len = buf[0] | ((unsigned char)buf[1] << 8);
	buf.erase(0, 2);
	if (len > buf.size())
		len = buf.size();
	std::string wl = buf.substr(len);
	buf.resize(len);
	datatrak_import(buf, wl, &log);
	return 0;
}
