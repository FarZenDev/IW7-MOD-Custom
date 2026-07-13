#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "upnp.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"

#include <utils/http.hpp>
#include <utils/string.hpp>

namespace upnp
{
	namespace
	{
		std::atomic_bool mapping_in_progress{false};

		struct igd_info
		{
			std::string control_url;
			std::string service_type;
		};

		std::string get_local_ip()
		{
			const auto sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
			if (sock == INVALID_SOCKET)
			{
				return {};
			}

			sockaddr_in remote{};
			remote.sin_family = AF_INET;
			remote.sin_port = htons(53);
			inet_pton(AF_INET, "8.8.8.8", &remote.sin_addr);

			std::string result{};
			if (::connect(sock, reinterpret_cast<sockaddr*>(&remote), sizeof(remote)) == 0)
			{
				sockaddr_in local{};
				int len = sizeof(local);
				if (getsockname(sock, reinterpret_cast<sockaddr*>(&local), &len) == 0)
				{
					char buffer[INET_ADDRSTRLEN]{};
					if (inet_ntop(AF_INET, &local.sin_addr, buffer, sizeof(buffer)))
					{
						result = buffer;
					}
				}
			}

			closesocket(sock);
			return result;
		}

		std::string extract_header(const std::string& response, const std::string& header)
		{
			const auto lower = utils::string::to_lower(response);
			const auto pos = lower.find(utils::string::to_lower(header) + ":");
			if (pos == std::string::npos)
			{
				return {};
			}

			const auto value_start = pos + header.size() + 1;
			const auto value_end = lower.find("\r\n", value_start);
			if (value_end == std::string::npos)
			{
				return {};
			}

			auto value = response.substr(value_start, value_end - value_start);
			while (!value.empty() && (value.front() == ' ' || value.front() == '\t'))
			{
				value.erase(value.begin());
			}

			return value;
		}

		std::string ssdp_discover_location()
		{
			const auto sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
			if (sock == INVALID_SOCKET)
			{
				return {};
			}

			DWORD timeout = 3000;
			setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));

			sockaddr_in dest{};
			dest.sin_family = AF_INET;
			dest.sin_port = htons(1900);
			inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr);

			std::string location{};
			const char* search_targets[] =
			{
				"urn:schemas-upnp-org:device:InternetGatewayDevice:1",
				"urn:schemas-upnp-org:device:InternetGatewayDevice:2",
			};

			for (const auto* target : search_targets)
			{
				const auto request = utils::string::va(
					"M-SEARCH * HTTP/1.1\r\n"
					"HOST: 239.255.255.250:1900\r\n"
					"MAN: \"ssdp:discover\"\r\n"
					"MX: 2\r\n"
					"ST: %s\r\n"
					"\r\n", target);

				if (sendto(sock, request, static_cast<int>(std::strlen(request)), 0,
					reinterpret_cast<sockaddr*>(&dest), sizeof(dest)) == SOCKET_ERROR)
				{
					continue;
				}

				char buffer[2048]{};
				sockaddr_in from{};
				int from_len = sizeof(from);
				const auto received = recvfrom(sock, buffer, sizeof(buffer) - 1, 0,
					reinterpret_cast<sockaddr*>(&from), &from_len);
				if (received <= 0)
				{
					continue;
				}

				buffer[received] = '\0';
				location = extract_header(buffer, "location");
				if (!location.empty())
				{
					break;
				}
			}

			closesocket(sock);
			return location;
		}

		std::string extract_tag(const std::string& xml, const std::string& tag, size_t from = 0)
		{
			const auto open = "<" + tag + ">";
			const auto close = "</" + tag + ">";

			const auto start = xml.find(open, from);
			if (start == std::string::npos)
			{
				return {};
			}

			const auto value_start = start + open.size();
			const auto end = xml.find(close, value_start);
			if (end == std::string::npos)
			{
				return {};
			}

			return xml.substr(value_start, end - value_start);
		}

		std::optional<igd_info> find_wan_service(const std::string& location)
		{
			const auto description = utils::http::get_data(location, {}, {}, {}, 5);
			if (!description.has_value() || description->code != CURLE_OK)
			{
				return {};
			}

			const auto& xml = description->buffer;
			const char* service_types[] =
			{
				"urn:schemas-upnp-org:service:WANIPConnection:2",
				"urn:schemas-upnp-org:service:WANIPConnection:1",
				"urn:schemas-upnp-org:service:WANPPPConnection:1",
			};

			for (const auto* service_type : service_types)
			{
				const auto pos = xml.find(service_type);
				if (pos == std::string::npos)
				{
					continue;
				}

				const auto control_url = extract_tag(xml, "controlURL", pos);
				if (control_url.empty())
				{
					continue;
				}

				igd_info info{};
				info.service_type = service_type;

				if (control_url.starts_with("http://") || control_url.starts_with("https://"))
				{
					info.control_url = control_url;
				}
				else
				{
					// base = scheme://host:port from the description location
					const auto scheme_end = location.find("://");
					if (scheme_end == std::string::npos)
					{
						continue;
					}

					const auto host_end = location.find('/', scheme_end + 3);
					const auto base = host_end == std::string::npos ? location : location.substr(0, host_end);
					info.control_url = base + (control_url.starts_with("/") ? "" : "/") + control_url;
				}

				return info;
			}

			return {};
		}

		bool send_add_port_mapping(const igd_info& igd, const std::string& local_ip,
			const std::uint16_t port, const std::uint32_t lease_seconds)
		{
			const auto body = utils::string::va(
				"<?xml version=\"1.0\"?>"
				"<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
				"s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
				"<s:Body>"
				"<u:AddPortMapping xmlns:u=\"%s\">"
				"<NewRemoteHost></NewRemoteHost>"
				"<NewExternalPort>%u</NewExternalPort>"
				"<NewProtocol>UDP</NewProtocol>"
				"<NewInternalPort>%u</NewInternalPort>"
				"<NewInternalClient>%s</NewInternalClient>"
				"<NewEnabled>1</NewEnabled>"
				"<NewPortMappingDescription>IW7-Mod</NewPortMappingDescription>"
				"<NewLeaseDuration>%u</NewLeaseDuration>"
				"</u:AddPortMapping>"
				"</s:Body>"
				"</s:Envelope>",
				igd.service_type.data(), port, port, local_ip.data(), lease_seconds);

			const utils::http::headers headers =
			{
				{"Content-Type", "text/xml; charset=\"utf-8\""},
				{"SOAPAction", utils::string::va("\"%s#AddPortMapping\"", igd.service_type.data())},
			};

			const auto response = utils::http::get_data(igd.control_url, body, headers, {}, 5);
			return response.has_value() && response->code == CURLE_OK && response->response_code == 200;
		}

		void map_port_worker(const std::uint16_t port)
		{
			const auto _ = gsl::finally([]()
			{
				mapping_in_progress = false;
			});

			WSADATA wsa_data{};
			WSAStartup(MAKEWORD(2, 2), &wsa_data);

			const auto local_ip = get_local_ip();
			if (local_ip.empty())
			{
				console::warn("[UPnP] Could not determine local IP address\n");
				return;
			}

			const auto location = ssdp_discover_location();
			if (location.empty())
			{
				console::warn("[UPnP] No UPnP router found. Port %u may require manual forwarding.\n", port);
				return;
			}

			const auto igd = find_wan_service(location);
			if (!igd.has_value())
			{
				console::warn("[UPnP] Router found but no WAN service available. Port %u may require manual forwarding.\n", port);
				return;
			}

			// some routers reject permanent leases, some reject timed ones - try both
			if (send_add_port_mapping(*igd, local_ip, port, 0) ||
				send_add_port_mapping(*igd, local_ip, port, 86400))
			{
				console::info("[UPnP] UDP port %u successfully forwarded to %s. Friends can now join you from the internet!\n",
					port, local_ip.data());
			}
			else
			{
				console::warn("[UPnP] Router refused the port mapping. Port %u may require manual forwarding.\n", port);
			}
		}
	}

	void try_map_port(const std::uint16_t port)
	{
		auto expected = false;
		if (!mapping_in_progress.compare_exchange_strong(expected, true))
		{
			return;
		}

		scheduler::once([port]()
		{
			map_port_worker(port);
		}, scheduler::pipeline::async);
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			command::add("upnp", []()
			{
				const auto* net_port = game::Dvar_FindVar("net_port");
				const auto port = static_cast<std::uint16_t>(net_port ? net_port->current.integer : 27017);
				console::info("[UPnP] Trying to forward UDP port %u...\n", port);
				try_map_port(port);
			});
		}
	};
}

REGISTER_COMPONENT(upnp::component)
