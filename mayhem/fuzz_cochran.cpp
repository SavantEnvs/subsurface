// AI-generated (Claude)
// Cochran Analyst .can importer. A file-input target, not libFuzzer: try_to_open_cochran() calls exit(1) on
// any file whose decoded log-format byte is not '2' or '3', which a libFuzzer process cannot survive.
#include "harness_common.h"
#include "core/file.h"

int main(int argc, char **argv)
{
	if (argc < 2)
		return 2;
	subsurface_fuzz_init();
	auto [mem, err] = readfile(argv[1]);
	if (err <= 0)
		return 0;
	struct divelog log;
	try_to_open_cochran("fuzz.can", mem, &log);
	return 0;
}
