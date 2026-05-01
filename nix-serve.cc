#include <nix/cmd/command.hh>
#include <nix/main/shared.hh>
#include <nix/store/log-store.hh>
#include <nix/store/nar-info.hh>
#include <nix/util/file-system.hh>
#include <nix/util/serialise.hh>
#include <nix/util/signals.hh>
#include <nix/util/signature/local-keys.hh>
#include <nix/util/signature/signer.hh>

#include <httplib.h>

#include <memory>
#include <string>

namespace nix {

struct CmdNixServe : StoreCommand, RootArgs
{
    bool helpRequested = false;
    std::string host = "0.0.0.0";
    int port = 5000;

    std::string description() override
    {
        return "Serve a Nix store as a binary cache";
    }

    CmdNixServe()
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
        addFlag({
            .longName = "help",
            .shortName = 'h',
            .description = "Show usage information.",
            .handler = {[this]() { helpRequested = true; }},
        });
        addFlag({
            .longName = "listen",
            .shortName = 'l',
            .description = "Address to listen on (`HOST:PORT`)",
            .labels = {"address"},
            .handler = {[this](std::string s) {
                auto colon = s.rfind(':');
                if (colon != std::string::npos) {
                    host = s.substr(0, colon);
                    port = std::stoi(s.substr(colon + 1));
                } else {
                    host = s;
                }
            }},
        });
#pragma GCC diagnostic pop
    }

    using StoreConfigCommand::run;
    void run(ref<Store> store) override;

    static void streamNar(Store & store, StorePath storePath, uint64_t narSize, httplib::Response & res);
};

void CmdNixServe::streamNar(Store & store, StorePath storePath, uint64_t narSize, httplib::Response & res)
{
    auto source = sinkToSource([&store, storePath](Sink & sink) { store.narFromPath(storePath, sink); });

    res.set_content_provider(
        narSize,
        "application/x-nix-nar",
        [source = std::shared_ptr<Source>(std::move(source))](size_t, size_t length, httplib::DataSink & sink) -> bool {
            char buf[65536];
            try {
                auto n = source->read(buf, std::min(length, sizeof(buf)));
                sink.write(buf, n);
                return true;
            } catch (EndOfFile &) {
                return false;
            }
        });
}

void CmdNixServe::run(ref<Store> store)
{
    std::unique_ptr<LocalSigner> signer;
    if (auto * keyFile = getenv("NIX_SECRET_KEY_FILE")) {
        auto keyData = readFile(keyFile);
        while (!keyData.empty() && keyData.back() == '\n')
            keyData.pop_back();
        signer = std::make_unique<LocalSigner>(SecretKey{keyData});
    }

    httplib::Server svr;

    // FIXME this logic should be factored out and unit-tested in Nix.
    svr.Get("/nix-cache-info", [&](const httplib::Request &, httplib::Response & res) {
        res.set_content(
            "StoreDir: " + store->storeDir + "\n"
            "WantMassQuery: 1\n"
            "Priority: 30\n",
            "text/plain");
    });

    svr.Get(R"(/([0-9a-z]+)\.narinfo)", [&](const httplib::Request & req, httplib::Response & res) {
        auto hashPart = req.matches[1].str();

        auto storePath = store->queryPathFromHashPart(hashPart);
        if (!storePath) {
            res.status = 404;
            res.set_content("No such path.\n", "text/plain");
            return;
        }

        auto info = store->queryPathInfo(*storePath);

        auto narHash32 = info->narHash.to_string(HashFormat::Nix32, false);

        NarInfo narInfo(*info);
        narInfo.url = "nar/" + hashPart + "-" + narHash32 + ".nar";
        narInfo.compression = "none";
        narInfo.fileHash = info->narHash;
        narInfo.fileSize = info->narSize;

        if (signer)
            narInfo.sign(*store, *signer);

        res.set_content(narInfo.to_string(*store), "text/x-nix-narinfo");
    });

    svr.Get(R"(/nar/([0-9a-z]+)-([0-9a-z]+)\.nar)", [&](const httplib::Request & req, httplib::Response & res) {
        auto hashPart = req.matches[1].str();
        auto expectedNarHash = req.matches[2].str();

        auto storePath = store->queryPathFromHashPart(hashPart);
        if (!storePath) {
            res.status = 404;
            res.set_content("No such path.\n", "text/plain");
            return;
        }

        auto info = store->queryPathInfo(*storePath);
        auto narHash32 = info->narHash.to_string(HashFormat::Nix32, false);
        if (narHash32 != expectedNarHash) {
            res.status = 404;
            res.set_content("Incorrect NAR hash. Maybe the path has been recreated.\n", "text/plain");
            return;
        }

        streamNar(*store, *storePath, info->narSize, res);
    });

    // FIXME: remove soon.
    svr.Get(R"(/nar/([0-9a-z]+)\.nar)", [&](const httplib::Request & req, httplib::Response & res) {
        auto hashPart = req.matches[1].str();

        auto storePath = store->queryPathFromHashPart(hashPart);
        if (!storePath) {
            res.status = 404;
            res.set_content("No such path.\n", "text/plain");
            return;
        }

        auto info = store->queryPathInfo(*storePath);
        streamNar(*store, *storePath, info->narSize, res);
    });

    svr.Get(R"(/log/([0-9a-z]+-[0-9a-zA-Z\+\-\.\_\?\=]+))", [&](const httplib::Request & req, httplib::Response & res) {
        auto pathName = req.matches[1].str();
        auto * logStore = dynamic_cast<LogStore *>(&*store);
        if (!logStore) {
            res.status = 404;
            res.set_content("This store does not support build logs.\n", "text/plain");
            return;
        }
        auto storePath = StorePath{pathName};
        auto log = logStore->getBuildLog(storePath);
        if (!log) {
            res.status = 404;
            res.set_content("No log available.\n", "text/plain");
            return;
        }
        res.set_content(*log, "text/plain");
    });

    svr.set_error_handler([](const httplib::Request &, httplib::Response & res) {
        if (res.status == 404)
            res.set_content("File not found.\n", "text/plain");
    });

    auto interruptCb = createInterruptCallback([&]() { svr.stop(); });

    notice("nix-serve listening on %s:%d", host, port);
    svr.listen(host, port);
}

} // namespace nix

int main(int argc, char ** argv)
{
    return nix::handleExceptions(argv[0], [&]() {
        nix::initNix();
        nix::CmdNixServe cmd;
        cmd.parseCmdline(nix::argvToStrings(argc, argv));
        if (cmd.helpRequested) {
            // FIXME automate this with something less heavy than what Nix does today.
            nix::logger->cout(
                "nix-serve - %s\n"
                "\n"
                "Usage: nix-serve [OPTIONS]\n"
                "\n"
                "Options:\n"
                "  --listen, -l HOST:PORT  Address to listen on (default: 0.0.0.0:5000)\n"
                "  --store URI             Nix store URI (default: auto)\n"
                "  --help, -h              Show this help message\n"
                "\n"
                "Environment variables:\n"
                "  NIX_SECRET_KEY_FILE     Path to secret key for signing narinfo responses",
                cmd.description());
            return;
        }
        cmd.run();
    });
}
