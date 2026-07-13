#pragma once
#include "game/game.hpp"

#include <utils/info_string.hpp>

namespace easymp
{
	struct friend_view
	{
		std::string name;
		std::string address;
		bool online;
		bool in_game;
		std::string hostname;
		std::string mapname;
		std::string gametype;
		int clients;
		int max_clients;
	};

	struct recent_view
	{
		std::string name;
		std::string address;
	};

	struct invite_view
	{
		bool valid;
		std::string from;
		std::string address;
		std::string mapname;
		std::string gametype;
	};

	// called from party.cpp when an infoResponse arrives (friend status tracking)
	void handle_info_response(const game::netadr_s& target, const utils::info_string& info);

	// called from party.cpp when a player registers on our listen server (recent players)
	void note_recent_player(const std::string& name, const game::netadr_s& address);

	// called from party.cpp right before joining a server (recent hosts)
	void note_recent_host(const std::string& hostname, const game::netadr_s& address);

	// called from party.cpp when a map starts on our own server:
	// forwards the port via UPnP and auto-invites friends
	void on_host_game_started();

	// cached public IP (empty until the async lookup succeeds), used by discord.cpp
	std::string get_cached_public_ip();

	// data getters for the LUI friends menu
	std::vector<friend_view> get_friends_snapshot();
	std::vector<recent_view> get_recent_players();
	invite_view get_pending_invite();
	std::string get_my_invite_code();
	void refresh_friends_status();
}
