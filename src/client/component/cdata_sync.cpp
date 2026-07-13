#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/http.hpp>
#include <utils/io.hpp>
#include <utils/properties.hpp>
#include <utils/string.hpp>

#include <rapidjson/document.h>

namespace cdata_sync
{
	namespace
	{
		// ===== Your GitHub repository (edit these two lines if it ever changes) =====
		// Example: REPO = "FarZen/iw7-mod-easymp", BRANCH = "main"
		constexpr const char* REPO = "FarZenDev/IW7-MOD-Custom";
		constexpr const char* BRANCH = "main";
		// The client data lives under this path inside the repo:
		constexpr const char* REPO_CDATA_PREFIX = "data/cdata/";
		// ===========================================================================

		std::atomic_bool sync_running{false};

		std::string get_cdata_root()
		{
			return (utils::properties::get_appdata_path() / "cdata").generic_string();
		}

		std::string get_version_file()
		{
			return (utils::properties::get_appdata_path() / "cdata_sync.txt").generic_string();
		}

		utils::http::headers github_headers()
		{
			// GitHub's API rejects requests without a User-Agent
			return { {"User-Agent", "iw7-mod-easymp"} };
		}

		bool download_file(const std::string& repo_path, const std::string& local_path)
		{
			const auto url = utils::string::va("https://raw.githubusercontent.com/%s/%s/%s",
				REPO, BRANCH, repo_path.data());

			const auto response = utils::http::get_data(url, {}, github_headers(), {}, 20);
			if (!response.has_value() || response->code != CURLE_OK || response->response_code != 200)
			{
				console::warn("[CDataSync] Failed to download %s\n", repo_path.data());
				return false;
			}

			return utils::io::write_file(local_path, response->buffer);
		}

		void sync_worker(const bool forced)
		{
			const auto _ = gsl::finally([]() { sync_running = false; });

			// 1. list every file in the repo tree
			const auto tree_url = utils::string::va(
				"https://api.github.com/repos/%s/git/trees/%s?recursive=1", REPO, BRANCH);

			const auto tree = utils::http::get_data(tree_url, {}, github_headers(), {}, 20);
			if (!tree.has_value() || tree->code != CURLE_OK || tree->response_code != 200)
			{
				console::warn("[CDataSync] Could not reach GitHub (%s). Using local scripts.\n", REPO);
				return;
			}

			rapidjson::Document doc;
			doc.Parse(tree->buffer.data());
			if (doc.HasParseError() || !doc.IsObject() || !doc.HasMember("tree") || !doc["tree"].IsArray())
			{
				console::warn("[CDataSync] Unexpected response from GitHub. Using local scripts.\n");
				return;
			}

			// 2. collect cdata files and build a combined signature (sha per blob)
			struct sync_file { std::string repo_path; std::string local_path; };
			std::vector<sync_file> files;
			std::string signature;

			const auto prefix = std::string(REPO_CDATA_PREFIX);
			const auto& tree_array = doc["tree"];
			for (rapidjson::SizeType i = 0; i < tree_array.Size(); ++i)
			{
				const auto& node = tree_array[i];
				if (!node.IsObject() || !node.HasMember("path") || !node["path"].IsString() ||
					!node.HasMember("type") || !node["type"].IsString())
				{
					continue;
				}

				if (std::string(node["type"].GetString()) != "blob")
				{
					continue;
				}

				const std::string path = node["path"].GetString();
				if (!path.starts_with(prefix))
				{
					continue;
				}

				const auto relative = path.substr(prefix.size());
				const auto local_path = get_cdata_root() + "/" + relative;

				files.push_back({ path, local_path });

				if (node.HasMember("sha") && node["sha"].IsString())
				{
					signature += node["sha"].GetString();
				}
			}

			if (files.empty())
			{
				console::warn("[CDataSync] No '%s' folder found in %s.\n", REPO_CDATA_PREFIX, REPO);
				return;
			}

			// 3. skip if nothing changed since last sync (unless forced)
			std::string previous_signature;
			utils::io::read_file(get_version_file(), &previous_signature);
			if (!forced && previous_signature == signature)
			{
				console::info("[CDataSync] Client data already up to date (%zu files).\n", files.size());
				return;
			}

			// 4. download everything
			auto ok = 0;
			for (const auto& file : files)
			{
				if (download_file(file.repo_path, file.local_path))
				{
					++ok;
				}
			}

			if (ok == static_cast<int>(files.size()))
			{
				utils::io::write_file(get_version_file(), signature);
				console::info("[CDataSync] Client data updated from GitHub: %d file(s). "
					"Restart the game if the menu looks off.\n", ok);
			}
			else
			{
				console::warn("[CDataSync] Partial update: %d/%zu files. Will retry next launch.\n",
					ok, files.size());
			}
		}

		void start_sync(const bool forced)
		{
			auto expected = false;
			if (!sync_running.compare_exchange_strong(expected, true))
			{
				return;
			}

			scheduler::once([forced]()
			{
				sync_worker(forced);
			}, scheduler::pipeline::async);
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi() || utils::flags::has_flag("nocdatasync"))
			{
				return;
			}

			start_sync(false);

			command::add("cdata_update", []()
			{
				console::info("[CDataSync] Forcing client data update from GitHub...\n");
				start_sync(true);
			});
		}
	};
}

REGISTER_COMPONENT(cdata_sync::component)
