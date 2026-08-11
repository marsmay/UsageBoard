@preconcurrency import Foundation
import Darwin
#if canImport(XCTest)
import XCTest
@testable import UsageBoardCore

final class UsageBoardTests: XCTestCase {
    func testConfigurationDecodesDefaultsAndSaves() throws {
        let data = #"{"plugins":[{"name":"A","executablePath":"/bin/echo"}]}"#.data(using: .utf8)!
        let configuration = try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(configuration.schemaVersion, 1)
        XCTAssertEqual(configuration.language, .zhHans)
        XCTAssertEqual(configuration.overviewDisplayMode, .tabs)
        XCTAssertEqual(configuration.plugins.first?.refreshIntervalSeconds, 300)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-\(UUID().uuidString).json")
        let store = ConfigStore(fileURL: url)
        try store.save(configuration)
        let reloaded = try store.load()
        let savedText = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(savedText.contains(#""language" : "zh-Hans""#))
        XCTAssertEqual(reloaded.plugins.first?.name, "A")
    }

    func testPluginsDirectoryIsNextToConfigurationFile() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))

        XCTAssertEqual(store.pluginsDirectoryURL(), directory.appendingPathComponent("plugins", isDirectory: true))
    }

    func testPluginStateStoreSavesAndClampsRefreshInterval() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let store = PluginStateStore(directoryURL: directory)
        let state = PluginCachedState(
            updatedAt: Date().addingTimeInterval(-1),
            items: [
                UsageItem(id: "a", name: "A", used: 1, limit: 2, displayStyle: .ratio)
            ]
        )

        try store.save(stateID: "plugin", state: state)

        XCTAssertNotNil(store.load(stateID: "plugin"))
        XCTAssertFalse(store.needsRefresh(stateID: "plugin", intervalSeconds: 0))
        XCTAssertFalse(store.needsRefresh(stateID: "plugin", intervalSeconds: -10))
    }

    func testPluginStateStoreCacheHitsAfterDiskDelete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let store = PluginStateStore(directoryURL: directory)
        let state = PluginCachedState(
            updatedAt: Date(),
            items: [UsageItem(id: "b", name: "B", used: 3, limit: 5, displayStyle: .percent)]
        )

        try store.save(stateID: "cached", state: state)

        // Remove the file on disk — the in-memory cache should still serve it.
        let fileURL = directory.appendingPathComponent("cached.json")
        try FileManager.default.removeItem(at: fileURL)

        let loaded = store.load(stateID: "cached")
        XCTAssertNotNil(loaded, "Expected in-memory cache hit after disk file deletion")
        XCTAssertEqual(loaded?.items.first?.name, "B")
    }

    func testPluginStateStoreKeepsMalformedStateIDInsideStatesDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("states", isDirectory: true)
        let store = PluginStateStore(directoryURL: directory)
        let state = PluginCachedState(
            updatedAt: Date(),
            items: [UsageItem(id: "c", name: "C", used: 1, limit: 2, displayStyle: .ratio)]
        )

        try store.save(stateID: "../outside", state: state)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.json").path))
        XCTAssertNotNil(store.load(stateID: "../outside"))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.deletingPathExtension().lastPathComponent, ".._outside")
    }

    func testBundledPluginInstallerCreatesSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let bundled = source.appendingPathComponent("glm-usage-plugin.py")
        let existing = destination.appendingPathComponent("glm-usage-plugin.py")
        let newPlugin = source.appendingPathComponent("tavily-usage-plugin.py")
        try "bundled".data(using: .utf8)!.write(to: bundled)
        try "user-edited".data(using: .utf8)!.write(to: existing)
        try "new".data(using: .utf8)!.write(to: newPlugin)

        let installed = try BundledPluginInstaller(
            sourceDirectoryURL: source,
            destinationDirectoryURL: destination
        )
        .installIfNeeded()

        XCTAssertEqual(installed.map(\.lastPathComponent), ["glm-usage-plugin.py", "tavily-usage-plugin.py"])
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: existing.path)
        XCTAssertEqual(URL(fileURLWithPath: linkTarget).resolvingSymlinksInPath(), bundled.resolvingSymlinksInPath())
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("tavily-usage-plugin.py")), "new")
    }

    func testBundledPluginInstallerReplacesBrokenSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let bundled = source.appendingPathComponent("glm-usage-plugin.py")
        let existing = destination.appendingPathComponent("glm-usage-plugin.py")
        let staleTarget = root.appendingPathComponent("missing/UsageBoard.app/Contents/Resources/Plugins/glm-usage-plugin.py")
        try "bundled".data(using: .utf8)!.write(to: bundled)
        try FileManager.default.createSymbolicLink(at: existing, withDestinationURL: staleTarget)

        let installed = try BundledPluginInstaller(
            sourceDirectoryURL: source,
            destinationDirectoryURL: destination
        )
        .installIfNeeded()

        XCTAssertEqual(installed.map(\.lastPathComponent), ["glm-usage-plugin.py"])
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: existing.path)
        XCTAssertEqual(URL(fileURLWithPath: linkTarget).resolvingSymlinksInPath(), bundled.resolvingSymlinksInPath())
    }

    func testPluginOutputDecodesAndFormatsUsage() throws {
        let json = """
        {
          "schemaVersion": 1,
          "updatedAt": "2026-04-29T00:00:00Z",
          "items": [
            {
              "id": "requests",
              "name": "Requests",
              "used": 1200,
              "limit": 1500,
              "displayStyle": "percent",
              "resetAt": "2026-04-29T00:05:00Z",
              "status": "normal"
            }
          ]
        }
        """.data(using: .utf8)!

        let output = try UsageBoardJSON.decoder().decode(PluginOutput.self, from: json)
        let item = try XCTUnwrap(output.items.first)
        XCTAssertEqual(item.progress, 0.8)
        XCTAssertEqual(item.name, "Requests")
        XCTAssertEqual(item.displayValue(), "80%")
        let now = ISO8601DateFormatter().date(from: "2026-04-29T00:00:00Z")!
        let text = item.resetText(now: now)
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "--")
    }

    func testPluginOutputDecodesFractionalSecondDates() throws {
        let json = """
        {
          "schemaVersion": 1,
          "updatedAt": "2026-05-15T04:22:02Z",
          "items": [
            {
              "id": "minimax-minimax-m*-interval",
              "name": "文本（5小时）",
              "used": 0,
              "limit": 1500,
              "displayStyle": "ratio",
              "resetAt": "2026-05-15T06:59:59.669000Z",
              "status": "normal"
            }
          ]
        }
        """.data(using: .utf8)!

        let output = try UsageBoardJSON.decoder().decode(PluginOutput.self, from: json)
        let item = try XCTUnwrap(output.items.first)
        XCTAssertEqual(item.name, "文本（5小时）")
        XCTAssertNotNil(item.resetAt)
    }

    func testPluginOutputDecodesChartAndCachesIt() throws {
        let json = """
        {
          "schemaVersion": 1,
          "updatedAt": "2026-05-01T00:00:00Z",
          "items": [
            {
              "id": "requests",
              "name": "Requests",
              "used": 1,
              "limit": 2,
              "displayStyle": "ratio",
              "status": "normal"
            }
          ],
          "chart": {
            "kind": "line",
            "period": "7d",
            "bucketUnit": "day",
            "buckets": [
              {
                "id": "2026-05-01",
                "label": "05-01",
                "segments": [
                  {"model": "glm-4.5", "tokens": 1200}
                ]
              }
            ],
            "message": "暂无可用统计数据"
          }
        }
        """.data(using: .utf8)!

        let output = try UsageBoardJSON.decoder().decode(PluginOutput.self, from: json)
        let chart = try XCTUnwrap(output.chart)
        XCTAssertEqual(chart.period, "7d")
        XCTAssertEqual(chart.buckets.first?.total, 1200)
        XCTAssertEqual(chart.message, "暂无可用统计数据")
        XCTAssertEqual(chart.buckets.first?.label, "05-01")

        let cached = PluginCachedState(updatedAt: output.updatedAt, items: output.items, chart: chart)
        let encoded = try UsageBoardJSON.encoder().encode(cached)
        let decoded = try UsageBoardJSON.decoder().decode(PluginCachedState.self, from: encoded)
        XCTAssertEqual(decoded.chart, chart)
        XCTAssertEqual(decoded.items.first?.name, "Requests")
        XCTAssertEqual(decoded.chart?.buckets.first?.label, "05-01")
    }

    func testPluginExecutorPropagatesChart() throws {
        let script = """
        import json
        print(json.dumps({
            "schemaVersion": 1,
            "updatedAt": "2026-05-01T00:00:00Z",
            "items": [
                {
                    "id": "requests",
                    "name": "Requests",
                    "used": 1,
                    "limit": 2,
                    "displayStyle": "ratio",
                    "status": "normal"
                }
            ],
            "chart": {
                "kind": "line",
            "period": "7d",
            "bucketUnit": "day",
            "buckets": [
                {
                    "id": "2026-05-01",
                    "label": "05-01",
                        "segments": [
                            {"model": "glm-4.5", "tokens": 1200}
                        ]
                    }
                ]
            }
        }))
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-\(UUID().uuidString).py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let configuration = PluginConfiguration(name: "Chart", executablePath: scriptURL.path)
        let snapshot = PluginExecutor(timeoutSeconds: 2).run(configuration: configuration, displayName: "Chart", language: .zhHans)

        XCTAssertEqual(snapshot.chart?.period, "7d")
        XCTAssertEqual(snapshot.chart?.buckets.first?.segments.first?.model, "glm-4.5")
    }

    func testProgressHandlesBoundsAndRatio() {
        let overLimit = UsageItem(id: "a", name: "A", used: 2, limit: 1, displayStyle: .percent)
        let noLimit = UsageItem(id: "b", name: "B", used: 2, limit: 0, displayStyle: .percent)
        let ratio = UsageItem(id: "c", name: "C", used: 2, limit: 1500, displayStyle: .ratio)

        XCTAssertEqual(overLimit.progress, 1)
        XCTAssertEqual(overLimit.displayValue(), "100%")
        XCTAssertEqual(noLimit.progress, 0)
        XCTAssertEqual(noLimit.displayValue(), "0%")
        XCTAssertEqual(ratio.displayValue(), "2 / 1500")
        XCTAssertEqual(ratio.resetText(), "--")
    }

    func testResetTextShowsStaticDateTime() {
        let now = ISO8601DateFormatter().date(from: "2026-04-29T00:00:00Z")!
        let resetAt = ISO8601DateFormatter().date(from: "2026-04-30T01:02:03Z")!
        let item = UsageItem(id: "a", name: "A", used: 1, limit: 2, displayStyle: .ratio, resetAt: resetAt)

        let text = item.resetText(now: now)
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "--")
        XCTAssertTrue(text.hasPrefix("明天 "))
        XCTAssertTrue(item.resetText(now: now, language: .en).hasPrefix("Tomorrow "))
        XCTAssertEqual(item.resetText(now: resetAt), "--")
    }

    func testPluginMetadataParserReadsCommentBlock() throws {
        let script = """
        #!/usr/bin/env python3
        # UsageBoardPlugin:
        # {
        #   "schemaVersion": 1,
        #   "name": "GLM",
        #   "name@en": "Zhipu",
        #   "description": "查询智谱用量",
        #   "description@en": "Query Zhipu usage",
        #   "parameters": [
        #     {"name": "API_KEY", "label": "Api Key", "label@en": "API Key", "type": "string", "required": true, "placeholder": "密钥", "placeholder@en": "Secret key"},
        #     {
        #       "name": "PROVIDER",
        #       "label": "Provider",
        #       "type": "choice",
        #       "defaultValue": "GLM",
        #       "options": [
        #         {"label": "智谱", "label@en": "GLM", "value": "GLM"},
        #         {"label": "ZAI", "value": "ZAI"}
        #       ]
        #     }
        #   ]
        # }
        # /UsageBoardPlugin
        print("ok")
        """

        let metadata = try XCTUnwrap(PluginMetadataParser.parse(text: script))
        XCTAssertEqual(metadata.name, "GLM")
        XCTAssertEqual(metadata.localizedName(language: .en), "Zhipu")
        XCTAssertEqual(metadata.localizedDescription(language: .en), "Query Zhipu usage")
        XCTAssertEqual(metadata.localizedDescription(language: .zhHans), "查询智谱用量")
        XCTAssertEqual(metadata.parameters.first?.name, "API_KEY")
        XCTAssertEqual(metadata.parameters.first?.localizedLabel(language: .en), "API Key")
        XCTAssertEqual(metadata.parameters.first?.localizedPlaceholder(language: .en), "Secret key")
        XCTAssertEqual(metadata.parameters.first?.type, .string)
        XCTAssertEqual(metadata.parameters.first?.required, true)
        XCTAssertEqual(metadata.parameters.last?.type, .choice)
        XCTAssertEqual(metadata.parameters.last?.options.map(\.value), ["GLM", "ZAI"])
        XCTAssertEqual(metadata.parameters.last?.options.first?.localizedLabel(language: .en), "GLM")
        XCTAssertEqual(metadata.parameters.last?.options.last?.localizedLabel(language: .en), "ZAI")

        let encoded = try UsageBoardJSON.encoder().encode(metadata)
        let decoded = try UsageBoardJSON.decoder().decode(PluginMetadata.self, from: encoded)
        XCTAssertEqual(decoded.localizedName(language: .en), "Zhipu")
        XCTAssertEqual(decoded.parameters.first?.localizedPlaceholder(language: .en), "Secret key")
        XCTAssertEqual(decoded.parameters.last?.options.first?.localizedLabel(language: .en), "GLM")
    }

    func testGLMPluginMetadataUsesStatPeriodWithoutProvider() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let root = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pluginURL = root.appendingPathComponent("Resources/BundledPlugins/glm-usage-plugin.py")

        let metadata = try XCTUnwrap(PluginMetadataParser.parse(fileURL: pluginURL))
        XCTAssertEqual(metadata.description, "查询智谱 / ZAI Coding Plan 用量和 token 统计")
        XCTAssertNil(metadata.parameters.first(where: { $0.name == "PROVIDER" }))

        let period = try XCTUnwrap(metadata.parameters.first(where: { $0.name == "STAT_PERIOD" }))
        XCTAssertEqual(period.defaultValue, "7d")
        XCTAssertEqual(period.options.map(\.value), ["7d", "15d", "30d"])
    }

    func testClaudePluginMetadataDoesNotExposeCalculationMode() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let root = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pluginURL = root.appendingPathComponent("Resources/BundledPlugins/claude-usage-plugin.py")

        let metadata = try XCTUnwrap(PluginMetadataParser.parse(fileURL: pluginURL))
        XCTAssertEqual(metadata.parameters.map(\.name), ["PLAN", "STAT_PERIOD", "CLAUDE_ONLY", "DATA_DIR"])
    }

    func testCodexPluginMetadataReadsParameters() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let root = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pluginURL = root.appendingPathComponent("Resources/BundledPlugins/codex-usage-plugin.py")

        let metadata = try XCTUnwrap(PluginMetadataParser.parse(fileURL: pluginURL))
        XCTAssertEqual(metadata.name, "Codex")
        XCTAssertEqual(metadata.parameters.map(\.name), ["AUTH_FILE", "DATA_DIR", "ENABLE_STATS", "STAT_PERIOD"])

        let enableStats = try XCTUnwrap(metadata.parameters.first(where: { $0.name == "ENABLE_STATS" }))
        XCTAssertEqual(enableStats.type, .boolean)
        XCTAssertEqual(enableStats.defaultValue, "true")
    }

    func testDuplicatePluginNamesGetNumbered() {
        let first = PluginConfiguration(name: "OpenAI", executablePath: "/bin/echo")
        let second = PluginConfiguration(name: "OpenAI", executablePath: "/bin/echo")
        let third = PluginConfiguration(name: "Other", executablePath: "/bin/echo")

        let names = PluginDisplayNames.make(for: [first, second, third])
        XCTAssertEqual(names[first.id], "OpenAI")
        XCTAssertEqual(names[second.id], "OpenAI 2")
        XCTAssertEqual(names[third.id], "Other")
    }

    func testLocalizedPluginDisplayNamesUseMetadataUnlessUserCustomized() {
        let metadata = PluginMetadata(name: "智谱", nameTranslations: ["en": "Zhipu"])
        let defaultName = PluginConfiguration(name: "智谱", executablePath: "/bin/echo", metadata: metadata)
        let customName = PluginConfiguration(name: "我的智谱", executablePath: "/bin/echo", metadata: metadata)
        let emptyName = PluginConfiguration(name: "", executablePath: "/bin/echo", metadata: metadata)

        let names = PluginDisplayNames.make(for: [defaultName, customName, emptyName], language: .en)

        XCTAssertEqual(names[defaultName.id], "Zhipu")
        XCTAssertEqual(names[customName.id], "我的智谱")
        XCTAssertEqual(names[emptyName.id], "Zhipu 2")
    }

    func testPluginParameterValuesBecomeArguments() {
        let executor = PluginExecutor()
        let configuration = PluginConfiguration(
            name: "GLM",
            executablePath: "/tmp/glm.py",
            parameterValues: [
                "API_KEY": "secret",
                "PROVIDER": "ZAI",
                "EMPTY": ""
            ]
        )

        XCTAssertEqual(
            executor.pluginParameterArguments(configuration: configuration),
            ["--usageboard-param", "API_KEY=secret", "--usageboard-param", "PROVIDER=ZAI"]
        )
        XCTAssertEqual(
            executor.pluginParameterArguments(configuration: configuration, language: .en),
            [
                "--usageboard-param", "API_KEY=secret",
                "--usageboard-param", "PROVIDER=ZAI",
                "--usageboard-param", "USAGEBOARD_LANGUAGE=en"
            ]
        )
    }

    func testUpdateVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.2.0", newerThan: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.2.1", newerThan: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", newerThan: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.1.9", newerThan: "1.2.0"))
    }

    func testPluginExecutorReportsInvalidJSON() {
        let configuration = PluginConfiguration(
            name: "Bad",
            executablePath: "/bin/echo"
        )

        let snapshot = PluginExecutor(timeoutSeconds: 2).run(configuration: configuration, displayName: "Bad", language: .zhHans)
        guard case .failed(let message) = snapshot.state else {
            XCTFail("Expected failed snapshot")
            return
        }
        XCTAssertTrue(message.contains("JSON 解析失败"))
    }

    func testPluginExecutorReportsDecodingPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("bad-output.py")
        try """
        print('{"updatedAt":"2026-05-15T00:00:00Z","items":[{"id":"a","name":"A","used":1,"limit":2,"displayStyle":"ratio","status":"ok"}]}')
        """.write(to: script, atomically: true, encoding: .utf8)

        let configuration = PluginConfiguration(name: "Bad", executablePath: script.path)
        let snapshot = PluginExecutor(timeoutSeconds: 2).run(configuration: configuration, displayName: "Bad", language: .zhHans)

        guard case .failed(let message) = snapshot.state else {
            XCTFail("Expected failed snapshot")
            return
        }
        XCTAssertTrue(message.contains("JSON 解析失败"))
        XCTAssertTrue(message.contains("items.Index 0.status"), message)
        XCTAssertTrue(message.contains("invalid String value ok"), message)
    }

    func testPluginExecutorForcesPythonUTF8Environment() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("encoding.py")
        try """
        import json, os, sys
        badge = "|".join([
            os.environ.get("PYTHONIOENCODING", ""),
            os.environ.get("LANG", ""),
            os.environ.get("LC_ALL", ""),
            sys.stdout.encoding or "",
        ])
        print(json.dumps({
            "updatedAt": "2026-05-15T00:00:00Z",
            "items": [{"id": "a", "name": "A", "used": 1, "limit": 2, "displayStyle": "ratio", "status": "normal"}],
            "badge": badge,
        }))
        """.write(to: script, atomically: true, encoding: .utf8)

        let configuration = PluginConfiguration(name: "Encoding", executablePath: script.path)
        let snapshot = PluginExecutor(timeoutSeconds: 2).run(configuration: configuration, displayName: "Encoding", language: .zhHans)

        guard case .ready = snapshot.state else {
            XCTFail("Expected ready snapshot, got \(snapshot.state)")
            return
        }
        XCTAssertEqual(snapshot.badge, "utf-8|en_US.UTF-8|en_US.UTF-8|utf-8")
    }

    func testPluginExecutorKillsTimedOutProcessThatIgnoresTermination() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pidURL = dir.appendingPathComponent("ignored-term.pid")
        let script = dir.appendingPathComponent("ignored-term.py")
        try """
        import os, signal, time

        signal.signal(signal.SIGTERM, lambda signum, frame: None)
        with open("\(pidURL.path)", "w", encoding="utf-8") as handle:
            handle.write(str(os.getpid()))
            handle.flush()

        while True:
            time.sleep(1)
        """.write(to: script, atomically: true, encoding: .utf8)

        let config = PluginConfiguration(name: "Ignored Term", executablePath: script.path)
        let snapshot = PluginExecutor(timeoutSeconds: 0.2).run(configuration: config, displayName: "Ignored Term", language: .zhHans)
        let pidText = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(pidText))
        defer { Darwin.kill(pid, SIGKILL) }

        guard case .failed(let message) = snapshot.state else {
            XCTFail("Expected .failed, got \(snapshot.state)")
            return
        }
        XCTAssertEqual(message, "插件执行超时")
        XCTAssertFalse(isProcessRunning(pid), "Timed-out plugin process should not keep running")
    }

    func testPluginExecutorHandlesLargeStdout() throws {
        // Regression test for pipe-buffer deadlock: stdout > 16KB used to hang
        // until 15s timeout because pipe was only drained after wait().
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("big-stdout.py")
        try """
        import json, sys
        # ~100 KB of stderr noise (must not deadlock either)
        sys.stderr.write("x" * 100_000)
        sys.stderr.flush()
        # ~150 KB of stdout JSON
        items = [{"id": f"i-{i}", "name": "x" * 200, "used": i, "limit": 1000, "displayStyle": "ratio", "status": "normal"} for i in range(500)]
        print(json.dumps({"schemaVersion": 1, "updatedAt": "2026-05-09T00:00:00Z", "items": items}))
        """.write(to: script, atomically: true, encoding: .utf8)

        let config = PluginConfiguration(name: "Big", executablePath: script.path)
        let snapshot = PluginExecutor(timeoutSeconds: 3).run(configuration: config, displayName: "Big", language: .zhHans)

        guard case .ready = snapshot.state else {
            XCTFail("Expected .ready, got \(snapshot.state)"); return
        }
        XCTAssertEqual(snapshot.items.count, 500)
    }

    func testPluginExecutorDetectsErrorJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-plugin.py")
        try """
        import json
        print(json.dumps({"error": "API Key 无效，请检查配置"}))
        """.write(to: script, atomically: true, encoding: .utf8)

        let config = PluginConfiguration(name: "Test", executablePath: script.path)
        let snapshot = PluginExecutor(timeoutSeconds: 5).run(configuration: config, displayName: "Test", language: .zhHans)

        guard case .failed(let message) = snapshot.state else {
            XCTFail("Expected .failed, got \(snapshot.state)"); return
        }
        XCTAssertEqual(message, "API Key 无效，请检查配置")
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }
}
#else
struct UsageBoardTestsPlaceholder {}
#endif
