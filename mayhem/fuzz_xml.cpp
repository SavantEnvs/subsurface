// AI-generated (Claude)
// Subsurface XML / XSLT-converted log parser (native .ssrf plus the UDDF, DL7, divelogs.de... importers).
#include "harness_common.h"

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	subsurface_fuzz_init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size == 0)
		return -1;
	// parse_xml_buffer() measures its input with strlen(), so hand it a NUL-terminated copy
	std::string buf((const char *)data, size);
	subsurface_fuzz_reset_guard reset_guard;
	struct divelog log;
	parse_xml_buffer("fuzz.xml", buf.c_str(), buf.size(), &log, nullptr);
	return 0;
}
