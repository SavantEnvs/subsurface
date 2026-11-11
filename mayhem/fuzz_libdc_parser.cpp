// AI-generated (Claude)
// libdivecomputer dive-buffer parsers as driven by Subsurface's libdc_buffer_parser().
#include <vector>

#include "harness_common.h"
#include "core/dive.h"
#include "core/libdivecomputer.h"

#include <libdivecomputer/descriptor.h>

static std::vector<dc_family_t> families;
static std::vector<int> models;

static bool handled(dc_family_t f)
{
	switch (f) {
	case DC_FAMILY_UWATEC_ALADIN:
	case DC_FAMILY_UWATEC_MEMOMOUSE:
	case DC_FAMILY_UWATEC_SMART:
	case DC_FAMILY_UWATEC_MERIDIAN:
	case DC_FAMILY_HW_OSTC:
	case DC_FAMILY_HW_FROG:
	case DC_FAMILY_HW_OSTC3:
	case DC_FAMILY_DIVESOFT_FREEDOM:
	case DC_FAMILY_GARMIN:
	case DC_FAMILY_SHEARWATER_PREDATOR:
	case DC_FAMILY_SHEARWATER_PETREL:
		return true;
	default:
		return false;
	}
}

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	subsurface_fuzz_init();
	dc_iterator_t *it = nullptr;
	if (dc_descriptor_iterator(&it) != DC_STATUS_SUCCESS)
		return 0;
	dc_descriptor_t *d = nullptr;
	while (dc_iterator_next(it, &d) == DC_STATUS_SUCCESS) {
		if (handled(dc_descriptor_get_type(d))) {
			families.push_back(dc_descriptor_get_type(d));
			models.push_back(dc_descriptor_get_model(d));
		}
		dc_descriptor_free(d);
	}
	dc_iterator_free(it);
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 2 || families.empty())
		return -1;
	// the first byte picks the device model, the rest is the raw dive buffer
	size_t idx = data[0] % families.size();
	device_data_t devdata;
	struct divelog log;
	devdata.log = &log;
	if (!prepare_device_descriptor(models[idx], families[idx], devdata))
		return -1;
	auto d = std::make_unique<dive>();
	libdc_buffer_parser(d.get(), &devdata, data + 1, size - 1);
	return 0;
}
