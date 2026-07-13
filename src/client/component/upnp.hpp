#pragma once

namespace upnp
{
	// Asynchronously discovers the internet gateway (router) via SSDP and maps
	// the given UDP port to this machine so friends can connect from the internet.
	// Results are reported to the console. Safe to call multiple times.
	void try_map_port(std::uint16_t port);
}
