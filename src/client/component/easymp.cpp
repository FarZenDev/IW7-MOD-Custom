#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "easymp.hpp"
#include "upnp.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "network.hpp"
#include "party.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"

#include <utils/http.hpp>
#include <utils/io.hpp>
#include <utils/properties.hpp>
#include <utils/string.hpp>

namespace easymp
{
	namespace
	{
		std::recursive_mutex state_mutex;

		struct friend_entry
		{
			std::string name;
			std::string address;
		};

		struct friend_status
		{
			bool online{};
			bool in_game{};
			std::string hostname;
			std::string mapname;
			std::string gametype;
			int clients{};
			int max_clients{};
		};

		struct pending_invite_t
		{
			bool valid{};
			std::string from;
			game::netadr_s address{};
			std::string mapname;
			std::string gametype;
		};

		// NAT hole punching: each client periodically sends a tiny presence packet
		// to every friend. Outgoing packets open a mapping in our own NAT/CGNAT so
		// the friend's replies, status pings and invites can reach us back - even
		// on mobile/tethered connections where no inbound port can be opened.
		struct presence_info
		{
			game::netadr_s address{};
			std::chrono::steady_clock::time_point last_seen{};
		};

		std::vector<friend_entry> friends_list;
		std::vector<recent_view> recent_players;
		std::unordered_map<game::netadr_s, std::string> pending_pings; // address -> friend name
		std::unordered_map<std::string, friend_status> statuses;       // friend name -> last known status
		std::unordered_map<std::string, presence_info> presence_map;   // lower friend name -> live presence
		pending_invite_t pending_invite;
		std::string public_ip;

		// Crockford base32: no I, L, O, U to avoid reading mistakes
		constexpr const char* B32_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

		std::string get_friends_file_path()
		{
			return (utils::properties::get_appdata_path() / "friends.txt").generic_string();
		}

		std::string get_recent_file_path()
		{
			return (utils::properties::get_appdata_path() / "recent_players.txt").generic_string();
		}

		std::uint16_t get_default_port()
		{
			const auto* net_port = game::Dvar_FindVar("net_port");
			return net_port ? static_cast<std::uint16_t>(net_port->current.integer) : 27017;
		}

		std::string normalize_address(std::string address)
		{
			if (address.find(':') == std::string::npos)
			{
				address += utils::string::va(":%u", get_default_port());
			}

			return address;
		}

		void load_list(const std::string& path, const std::function<void(const std::string&, const std::string&)>& add)
		{
			std::string data;
			if (!utils::io::read_file(path, &data))
			{
				return;
			}

			for (const auto& line : utils::string::split(data, '\n'))
			{
				const auto tab = line.find('\t');
				if (tab == std::string::npos)
				{
					continue;
				}

				auto name = line.substr(0, tab);
				auto address = line.substr(tab + 1);
				while (!address.empty() && (address.back() == '\r' || address.back() == ' '))
				{
					address.pop_back();
				}

				if (!name.empty() && !address.empty())
				{
					add(name, address);
				}
			}
		}

		void load_friends()
		{
			std::lock_guard _(state_mutex);
			friends_list.clear();
			load_list(get_friends_file_path(), [](const std::string& name, const std::string& address)
			{
				friends_list.push_back({name, address});
			});
		}

		void save_friends()
		{
			std::lock_guard _(state_mutex);
			std::string data;
			for (const auto& entry : friends_list)
			{
				data += entry.name + "\t" + entry.address + "\n";
			}

			utils::io::write_file(get_friends_file_path(), data);
		}

		void load_recent()
		{
			std::lock_guard _(state_mutex);
			recent_players.clear();
			load_list(get_recent_file_path(), [](const std::string& name, const std::string& address)
			{
				recent_players.push_back({name, address});
			});
		}

		void save_recent()
		{
			std::lock_guard _(state_mutex);
			std::string data;
			for (const auto& entry : recent_players)
			{
				data += entry.name + "\t" + entry.address + "\n";
			}

			utils::io::write_file(get_recent_file_path(), data);
		}

		const friend_entry* find_friend(const std::string& name)
		{
			const auto lower = utils::string::to_lower(name);
			for (const auto& entry : friends_list)
			{
				if (utils::string::to_lower(entry.name) == lower)
				{
					return &entry;
				}
			}

			return nullptr;
		}

		const friend_entry* find_friend_by_ip(const game::netadr_s& address)
		{
			for (const auto& entry : friends_list)
			{
				game::netadr_s stored{};
				if (game::NET_StringToAdr(normalize_address(entry.address).data(), &stored) &&
					stored.addr == address.addr)
				{
					return &entry;
				}
			}

			return nullptr;
		}

		bool presence_fresh(const std::string& name)
		{
			const auto iter = presence_map.find(utils::string::to_lower(name));
			return iter != presence_map.end() &&
				std::chrono::steady_clock::now() - iter->second.last_seen < std::chrono::seconds(65);
		}

		void mark_presence(const std::string& name, const game::netadr_s& address)
		{
			auto& info = presence_map[utils::string::to_lower(name)];
			info.address = address;
			info.last_seen = std::chrono::steady_clock::now();
		}

		// resolve the sender of a friend packet: match by stored IP first, then by
		// the announced name (handles friends whose public IP changed since added)
		const friend_entry* identify_friend_packet(const game::netadr_s& source, const std::string& announced_name)
		{
			if (const auto* entry = find_friend_by_ip(source))
			{
				return entry;
			}

			if (!announced_name.empty())
			{
				return find_friend(announced_name);
			}

			return nullptr;
		}

		std::string adr_to_connect_string(const game::netadr_s& address)
		{
			return utils::string::va("%u.%u.%u.%u:%u",
				static_cast<unsigned int>(address.ip[0]),
				static_cast<unsigned int>(address.ip[1]),
				static_cast<unsigned int>(address.ip[2]),
				static_cast<unsigned int>(address.ip[3]),
				static_cast<unsigned int>(ntohs(address.port)));
		}

		void copy_to_clipboard(const std::string& text)
		{
			if (!OpenClipboard(nullptr))
			{
				return;
			}

			EmptyClipboard();
			if (auto* mem = GlobalAlloc(GMEM_MOVEABLE, text.size() + 1))
			{
				if (auto* dst = GlobalLock(mem))
				{
					std::memcpy(dst, text.data(), text.size() + 1);
					GlobalUnlock(mem);
					if (!SetClipboardData(CF_TEXT, mem))
					{
						GlobalFree(mem);
					}
				}
				else
				{
					GlobalFree(mem);
				}
			}

			CloseClipboard();
		}

		std::string encode_invite_code(const std::uint8_t ip[4], const std::uint16_t port)
		{
			std::uint8_t bytes[7]{};
			std::memcpy(bytes, ip, 4);
			bytes[4] = static_cast<std::uint8_t>(port >> 8);
			bytes[5] = static_cast<std::uint8_t>(port & 0xFF);

			std::uint8_t checksum = 0x77;
			for (auto i = 0; i < 6; ++i)
			{
				checksum ^= bytes[i];
			}
			bytes[6] = checksum;

			std::string out;
			auto bit_pos = 0;
			for (auto i = 0; i < 12; ++i)
			{
				auto value = 0;
				for (auto b = 0; b < 5; ++b)
				{
					const auto idx = bit_pos + b;
					value <<= 1;
					if (idx < 56 && (bytes[idx / 8] >> (7 - (idx % 8))) & 1)
					{
						value |= 1;
					}
				}

				out += B32_ALPHABET[value];
				bit_pos += 5;

				if (i == 3 || i == 7)
				{
					out += '-';
				}
			}

			return out;
		}

		bool decode_invite_code(const std::string& code, std::string& out_address)
		{
			std::string normalized;
			for (auto c : code)
			{
				c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
				if (c == '-' || c == ' ')
				{
					continue;
				}

				// forgive commonly confused characters
				if (c == 'O') c = '0';
				if (c == 'I' || c == 'L') c = '1';
				if (c == 'U') c = 'V';

				normalized += c;
			}

			if (normalized.size() != 12)
			{
				return false;
			}

			std::uint8_t bytes[8]{};
			auto bit_pos = 0;
			for (const auto c : normalized)
			{
				const auto* found = std::strchr(B32_ALPHABET, c);
				if (!found)
				{
					return false;
				}

				const auto value = static_cast<int>(found - B32_ALPHABET);
				for (auto b = 0; b < 5; ++b)
				{
					const auto idx = bit_pos + b;
					if (idx >= 64)
					{
						break;
					}

					if ((value >> (4 - b)) & 1)
					{
						bytes[idx / 8] |= 1 << (7 - (idx % 8));
					}
				}

				bit_pos += 5;
			}

			std::uint8_t checksum = 0x77;
			for (auto i = 0; i < 6; ++i)
			{
				checksum ^= bytes[i];
			}

			if (checksum != bytes[6])
			{
				return false;
			}

			const auto port = static_cast<std::uint16_t>((bytes[4] << 8) | bytes[5]);
			out_address = utils::string::va("%u.%u.%u.%u:%u",
				static_cast<unsigned int>(bytes[0]),
				static_cast<unsigned int>(bytes[1]),
				static_cast<unsigned int>(bytes[2]),
				static_cast<unsigned int>(bytes[3]),
				static_cast<unsigned int>(port));
			return true;
		}

		std::atomic_bool ip_fetch_running{false};

		void fetch_public_ip(const int retries_left = 8)
		{
			{
				std::lock_guard _(state_mutex);
				if (!public_ip.empty())
				{
					return;
				}
			}

			// avoid launching several lookups at once (menu polls this every 3s)
			auto expected = false;
			if (!ip_fetch_running.compare_exchange_strong(expected, true))
			{
				return;
			}

			scheduler::once([retries_left]()
			{
				const auto fetch_guard = gsl::finally([]() { ip_fetch_running = false; });

				// try HTTPS first, then plain HTTP (passes better behind phone
				// tethering / captive setups where HTTPS to these hosts is blocked)
				const char* services[] =
				{
					"https://api.ipify.org",
					"http://api.ipify.org",
					"http://checkip.amazonaws.com",
					"http://icanhazip.com",
					"http://ifconfig.me/ip",
					"http://ipv4.icanhazip.com",
				};

				for (const auto* url : services)
				{
					const auto response = utils::http::get_data(url, {}, {}, {}, 8);
					if (!response.has_value() || response->code != CURLE_OK)
					{
						continue;
					}

					auto ip = response->buffer;
					ip.erase(std::remove_if(ip.begin(), ip.end(), [](const char c)
					{
						return c == '\r' || c == '\n' || c == ' ' || c == '\t';
					}), ip.end());

					in_addr parsed{};
					if (!ip.empty() && inet_pton(AF_INET, ip.data(), &parsed) == 1)
					{
						std::lock_guard _(state_mutex);
						public_ip = ip;
						console::info("[EasyMP] Public IP detected: %s\n", ip.data());
						return;
					}
				}

				if (retries_left > 0)
				{
					console::debug("[EasyMP] Public IP not detected, retrying (%d left)...\n", retries_left);
					scheduler::once([retries_left]()
					{
						fetch_public_ip(retries_left - 1);
					}, scheduler::pipeline::async, 5s);
				}
				else
				{
					console::warn("[EasyMP] Could not detect public IP after several tries. "
						"Check your internet connection, then run 'invite_code' to retry.\n");
				}
			}, scheduler::pipeline::async);
		}

		std::string get_player_name()
		{
			const auto* name = game::Dvar_FindVar("name");
			if (name && name->current.string && *name->current.string)
			{
				return name->current.string;
			}

			return "Player";
		}

		void print_invite_code()
		{
			const auto code = get_my_invite_code();
			if (code.empty())
			{
				console::warn("[EasyMP] Public IP not detected yet. Retrying now, run 'invite_code' again in a few seconds...\n");
				fetch_public_ip();
				return;
			}

			copy_to_clipboard(code);
			console::info("=======================================================\n");
			console::info("[EasyMP] Your invite code: ^2%s^7 (copied to clipboard)\n", code.data());
			console::info("[EasyMP] Friends can join you with: join %s\n", code.data());
			console::info("[EasyMP] Or add you as a friend with: friend_add <name> %s\n", code.data());
			console::info("=======================================================\n");
		}

		void do_connect(const game::netadr_s& target)
		{
			if (game::CL_IsGameClientActive(0))
			{
				command::execute("disconnect");
				scheduler::once([target]()
				{
					party::connect(target);
				}, scheduler::pipeline::main, 500ms);
			}
			else
			{
				party::connect(target);
			}
		}

		bool resolve_join_target(const std::string& input, game::netadr_s& target)
		{
			std::lock_guard _(state_mutex);

			// 1. friend name - prefer the live address observed through presence
			// packets (handles friends whose public IP changed since being added)
			if (const auto* entry = find_friend(input))
			{
				const auto iter = presence_map.find(utils::string::to_lower(entry->name));
				if (iter != presence_map.end() && presence_fresh(entry->name))
				{
					target = iter->second.address;
					return true;
				}

				return game::NET_StringToAdr(normalize_address(entry->address).data(), &target);
			}

			// 2. invite code
			std::string decoded;
			if (decode_invite_code(input, decoded))
			{
				return game::NET_StringToAdr(decoded.data(), &target);
			}

			// 3. raw ip[:port]
			return game::NET_StringToAdr(normalize_address(input).data(), &target);
		}

		void send_invites_to_friends()
		{
			std::lock_guard _(state_mutex);

			utils::info_string info{};
			info.set("from", get_player_name());
			info.set("mapname", [&]() -> std::string
			{
				const auto* mapname = game::Dvar_FindVar("mapname");
				return mapname && mapname->current.string ? mapname->current.string : "";
			}());
			info.set("gametype", [&]() -> std::string
			{
				const auto* gametype = game::Dvar_FindVar("g_gametype");
				return gametype && gametype->current.string ? gametype->current.string : "";
			}());

			if (!public_ip.empty())
			{
				info.set("address", utils::string::va("%s:%u", public_ip.data(), get_default_port()));
			}

			auto sent = 0;
			for (const auto& entry : friends_list)
			{
				game::netadr_s target{};
				if (game::NET_StringToAdr(normalize_address(entry.address).data(), &target))
				{
					network::send(target, "gameInvite", info.build(), '\n');
					++sent;
				}

				// also send through the live NAT mapping observed from their
				// presence packets (reaches friends behind CGNAT/mobile networks)
				const auto iter = presence_map.find(utils::string::to_lower(entry.name));
				if (iter != presence_map.end() &&
					(iter->second.address.addr != target.addr || iter->second.address.port != target.port))
				{
					network::send(iter->second.address, "gameInvite", info.build(), '\n');
				}
			}

			if (sent > 0)
			{
				console::info("[EasyMP] Invite sent to %d friend(s).\n", sent);
			}
		}

		void send_presence_to_friends()
		{
			std::lock_guard _(state_mutex);

			if (friends_list.empty())
			{
				return;
			}

			utils::info_string info{};
			info.set("name", get_player_name());

			for (const auto& entry : friends_list)
			{
				game::netadr_s target{};
				if (game::NET_StringToAdr(normalize_address(entry.address).data(), &target))
				{
					network::send(target, "easympPresence", info.build(), '\n');
				}
			}
		}
	}

	std::string get_cached_public_ip()
	{
		std::lock_guard _(state_mutex);
		return public_ip;
	}

	std::string get_my_invite_code()
	{
		{
			std::lock_guard _(state_mutex);
			if (public_ip.empty())
			{
				// keep trying while someone is looking at the code (menu polls this)
				fetch_public_ip();
				return {};
			}
		}

		std::lock_guard _(state_mutex);

		std::uint8_t ip[4]{};
		in_addr parsed{};
		if (inet_pton(AF_INET, public_ip.data(), &parsed) != 1)
		{
			return {};
		}

		std::memcpy(ip, &parsed.s_addr, 4);
		return encode_invite_code(ip, get_default_port());
	}

	void handle_info_response(const game::netadr_s& target, const utils::info_string& info)
	{
		std::lock_guard _(state_mutex);

		const auto iter = pending_pings.find(target);
		if (iter == pending_pings.end())
		{
			return;
		}

		friend_status status{};
		status.online = true;
		status.in_game = std::atoi(info.get("sv_running").data()) != 0;
		status.hostname = info.get("hostname");
		status.mapname = info.get("mapname");
		status.gametype = info.get("gametype");
		status.clients = std::atoi(info.get("clients").data());
		status.max_clients = std::atoi(info.get("sv_maxclients").data());

		statuses[iter->second] = status;
	}

	void note_recent_player(const std::string& name, const game::netadr_s& address)
	{
		if (name.empty() || game::environment::is_dedi())
		{
			return;
		}

		std::lock_guard _(state_mutex);

		const auto address_str = adr_to_connect_string(address);
		const auto lower = utils::string::to_lower(name);

		std::erase_if(recent_players, [&](const recent_view& entry)
		{
			return utils::string::to_lower(entry.name) == lower || entry.address == address_str;
		});

		recent_players.insert(recent_players.begin(), {name, address_str});
		if (recent_players.size() > 15)
		{
			recent_players.resize(15);
		}

		save_recent();
	}

	void note_recent_host(const std::string& hostname, const game::netadr_s& address)
	{
		note_recent_player(hostname.empty() ? "Host" : hostname, address);
	}

	void on_host_game_started()
	{
		upnp::try_map_port(get_default_port());

		if (game::environment::is_dedi())
		{
			return;
		}

		// give the server a moment to be fully up before friends probe it
		scheduler::once([]()
		{
			send_invites_to_friends();
			print_invite_code();
		}, scheduler::pipeline::main, 4s);
	}

	std::vector<friend_view> get_friends_snapshot()
	{
		std::lock_guard _(state_mutex);

		std::vector<friend_view> result;
		result.reserve(friends_list.size());

		for (const auto& entry : friends_list)
		{
			friend_view view{};
			view.name = entry.name;
			view.address = entry.address;

			const auto iter = statuses.find(entry.name);
			if (iter != statuses.end())
			{
				view.online = iter->second.online;
				view.in_game = iter->second.in_game;
				view.hostname = iter->second.hostname;
				view.mapname = iter->second.mapname;
				view.gametype = iter->second.gametype;
				view.clients = iter->second.clients;
				view.max_clients = iter->second.max_clients;
			}

			// friends behind CGNAT can't answer direct pings, but their periodic
			// presence packets prove they are online
			if (!view.online && presence_fresh(entry.name))
			{
				view.online = true;
			}

			result.push_back(std::move(view));
		}

		return result;
	}

	std::vector<recent_view> get_recent_players()
	{
		std::lock_guard _(state_mutex);
		return recent_players;
	}

	invite_view get_pending_invite()
	{
		std::lock_guard _(state_mutex);

		invite_view view{};
		view.valid = pending_invite.valid;
		if (pending_invite.valid)
		{
			view.from = pending_invite.from;
			view.address = adr_to_connect_string(pending_invite.address);
			view.mapname = pending_invite.mapname;
			view.gametype = pending_invite.gametype;
		}

		return view;
	}

	void refresh_friends_status()
	{
		std::lock_guard _(state_mutex);

		pending_pings.clear();
		for (auto& [name, status] : statuses)
		{
			status.online = false;
			status.in_game = false;
		}

		for (const auto& entry : friends_list)
		{
			game::netadr_s target{};
			if (game::NET_StringToAdr(normalize_address(entry.address).data(), &target))
			{
				pending_pings[target] = entry.name;
				network::send(target, "getInfo", "easymp");
			}

			// also probe through the live NAT mapping learned from presence
			const auto iter = presence_map.find(utils::string::to_lower(entry.name));
			if (iter != presence_map.end() &&
				(iter->second.address.addr != target.addr || iter->second.address.port != target.port))
			{
				pending_pings[iter->second.address] = entry.name;
				network::send(iter->second.address, "getInfo", "easymp");
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			load_friends();
			load_recent();
			fetch_public_ip();

			network::on("gameInvite", [](const game::netadr_s& target, const std::string_view& data)
			{
				const utils::info_string info{data};

				std::lock_guard _(state_mutex);

				// only accept invites from people in our friends list, to avoid spam
				const auto from = info.get("from");
				const auto* sender = identify_friend_packet(target, from);
				const auto is_friend = sender != nullptr;
				if (sender)
				{
					mark_presence(sender->name, target);
				}

				pending_invite.valid = true;
				pending_invite.from = from.empty() ? "Un joueur" : from;
				pending_invite.address = target;
				pending_invite.mapname = info.get("mapname");
				pending_invite.gametype = info.get("gametype");

				// the connect address may differ from the packet source (rare NAT setups)
				const auto explicit_address = info.get("address");
				if (!explicit_address.empty())
				{
					game::netadr_s parsed{};
					if (game::NET_StringToAdr(explicit_address.data(), &parsed))
					{
						pending_invite.address = parsed;
					}
				}

				console::info("[EasyMP] %s invited you to play %s on %s! Type 'accept_invite' or open the FRIENDS menu.\n",
					pending_invite.from.data(),
					pending_invite.gametype.empty() ? "?" : pending_invite.gametype.data(),
					pending_invite.mapname.empty() ? "?" : pending_invite.mapname.data());

				if (is_friend && game::Com_FrontEnd_IsInFrontEnd())
				{
					scheduler::once([]()
					{
						std::lock_guard _(state_mutex);
						if (pending_invite.valid)
						{
							game::shared::menu_error(utils::string::va(
								"%s vous invite a jouer !\nOuvrez le menu JOUER ENTRE AMIS pour le rejoindre.",
								pending_invite.from.data()));
						}
					}, scheduler::pipeline::main);
				}
			});

			// presence beacons: prove we are online and keep a NAT hole open in
			// both directions, so even friends on mobile/CGNAT connections can be
			// seen online and receive invites
			network::on("easympPresence", [](const game::netadr_s& target, const std::string_view& data)
			{
				const utils::info_string info{data};

				std::lock_guard _(state_mutex);
				const auto* sender = identify_friend_packet(target, info.get("name"));
				if (!sender)
				{
					return;
				}

				mark_presence(sender->name, target);

				utils::info_string ack{};
				ack.set("name", get_player_name());
				network::send(target, "easympPresenceAck", ack.build(), '\n');
			});

			network::on("easympPresenceAck", [](const game::netadr_s& target, const std::string_view& data)
			{
				const utils::info_string info{data};

				std::lock_guard _(state_mutex);
				const auto* sender = identify_friend_packet(target, info.get("name"));
				if (sender)
				{
					mark_presence(sender->name, target);
				}
			});

			scheduler::loop(send_presence_to_friends, scheduler::pipeline::main, 20s);

			command::add("host", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: host <map> [gametype] [maxclients] [password]\n");
					console::info("example: host mp_crash_iw war 12\n");
					return;
				}

				const std::string map = params.get(1);

				// default gametype: keep the current one (correct for zombies maps),
				// fall back to team deathmatch for multiplayer
				std::string gametype;
				if (params.size() > 2)
				{
					gametype = params.get(2);
				}
				else
				{
					const auto* current_gametype = game::Dvar_FindVar("g_gametype");
					if (current_gametype && current_gametype->current.string &&
						*current_gametype->current.string && current_gametype->current.string != "frontend"s)
					{
						gametype = current_gametype->current.string;
					}
					else
					{
						gametype = "war";
					}
				}
				auto max_clients = params.size() > 3 ? std::atoi(params.get(3)) : 12;
				max_clients = std::clamp(max_clients, 2, 18);
				const std::string password = params.size() > 4 ? params.get(4) : "";

				command::execute(utils::string::va("seta g_gametype %s", gametype.data()), true);
				command::execute(utils::string::va("seta ui_gametype %s", gametype.data()), true);
				command::execute(utils::string::va("seta ui_maxclients %d", max_clients), true);
				command::execute(utils::string::va("seta party_maxplayers %d", max_clients), true);
				command::execute(utils::string::va("seta g_password \"%s\"", password.data()), true);
				command::execute(utils::string::va("seta sv_hostname \"Partie de %s\"", get_player_name().data()), true);

				auto* privatematch = game::Dvar_FindVar("xblive_privatematch");
				if (privatematch)
				{
					game::Dvar_SetBool(privatematch, true);
				}

				console::info("[EasyMP] Hosting %s (%s, %d players max)...\n", map.data(), gametype.data(), max_clients);
				party::start_map(map, false);
			});

			command::add("join", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: join <friend name | invite code | ip[:port]>\n");
					return;
				}

				const auto input = params.join(1);
				game::netadr_s target{};
				if (!resolve_join_target(input, target))
				{
					console::error("[EasyMP] Could not resolve '%s' (unknown friend, invalid code or address).\n", input.data());
					return;
				}

				console::info("[EasyMP] Connecting to %s...\n", adr_to_connect_string(target).data());
				do_connect(target);
			});

			command::add("accept_invite", []()
			{
				game::netadr_s target{};
				{
					std::lock_guard _(state_mutex);
					if (!pending_invite.valid)
					{
						console::info("[EasyMP] No pending invite.\n");
						return;
					}

					target = pending_invite.address;
					pending_invite.valid = false;
				}

				console::info("[EasyMP] Accepting invite, connecting to %s...\n", adr_to_connect_string(target).data());
				do_connect(target);
			});

			command::add("decline_invite", []()
			{
				std::lock_guard _(state_mutex);
				pending_invite.valid = false;
			});

			command::add("friend_add", [](const command::params& params)
			{
				if (params.size() < 3)
				{
					console::info("usage: friend_add <name> <ip[:port] | invite code>\n");
					return;
				}

				const std::string name = params.get(1);
				std::string address = params.join(2);

				std::string decoded;
				if (decode_invite_code(address, decoded))
				{
					address = decoded;
				}

				game::netadr_s check{};
				if (!game::NET_StringToAdr(normalize_address(address).data(), &check))
				{
					console::error("[EasyMP] Invalid address or invite code: %s\n", address.data());
					return;
				}

				std::lock_guard _(state_mutex);
				std::erase_if(friends_list, [&](const friend_entry& entry)
				{
					return utils::string::to_lower(entry.name) == utils::string::to_lower(name);
				});

				friends_list.push_back({name, normalize_address(address)});
				save_friends();
				console::info("[EasyMP] Friend '%s' added (%s). Total: %zu friend(s).\n",
					name.data(), address.data(), friends_list.size());
			});

			command::add("friend_add_recent", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: friend_add_recent <index>\n");
					return;
				}

				std::lock_guard _(state_mutex);
				const auto index = static_cast<size_t>(std::atoi(params.get(1)));
				if (index >= recent_players.size())
				{
					console::error("[EasyMP] Invalid recent player index.\n");
					return;
				}

				const auto recent = recent_players[index];
				std::erase_if(friends_list, [&](const friend_entry& entry)
				{
					return utils::string::to_lower(entry.name) == utils::string::to_lower(recent.name);
				});

				friends_list.push_back({recent.name, recent.address});
				save_friends();
				console::info("[EasyMP] Friend '%s' added (%s).\n", recent.name.data(), recent.address.data());
			});

			command::add("friend_remove", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("usage: friend_remove <name>\n");
					return;
				}

				const auto name = utils::string::to_lower(params.join(1));

				std::lock_guard _(state_mutex);
				const auto before = friends_list.size();
				std::erase_if(friends_list, [&](const friend_entry& entry)
				{
					return utils::string::to_lower(entry.name) == name;
				});

				if (friends_list.size() != before)
				{
					save_friends();
					console::info("[EasyMP] Friend removed.\n");
				}
				else
				{
					console::info("[EasyMP] No friend with that name.\n");
				}
			});

			command::add("friends", []()
			{
				refresh_friends_status();

				scheduler::once([]()
				{
					const auto snapshot = get_friends_snapshot();
					if (snapshot.empty())
					{
						console::info("[EasyMP] Your friends list is empty. Use: friend_add <name> <address | code>\n");
						return;
					}

					console::info("=========== FRIENDS (%zu) ===========\n", snapshot.size());
					for (const auto& entry : snapshot)
					{
						if (entry.online && entry.in_game)
						{
							console::info("^2[IN GAME]^7 %s - %s on %s (%d/%d) - join with: join %s\n",
								entry.name.data(), entry.gametype.data(), entry.mapname.data(),
								entry.clients, entry.max_clients, entry.name.data());
						}
						else if (entry.online)
						{
							console::info("^3[ONLINE]^7  %s\n", entry.name.data());
						}
						else
						{
							console::info("^1[OFFLINE]^7 %s\n", entry.name.data());
						}
					}
				}, scheduler::pipeline::main, 2s);
			});

			command::add("invite", []()
			{
				if (!game::SV_Loaded() || game::Com_FrontEnd_IsInFrontEnd())
				{
					console::info("[EasyMP] You are not hosting a game. Start one first (host <map>).\n");
					return;
				}

				send_invites_to_friends();
			});

			command::add("invite_code", []()
			{
				print_invite_code();
			});
		}
	};
}

REGISTER_COMPONENT(easymp::component)
