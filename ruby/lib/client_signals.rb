# frozen_string_literal: true

require_relative "client_signals/version"

# Coarse, privacy-safe signals that help estimate whether a process is being
# driven by a human or an AI agent.
#
# This package is intentionally self-contained: nothing here reaches beyond the
# Ruby standard library, so it can be dropped into any application without
# dragging dependencies along.
#
# See docs/signals.md at the root of this repository for the reasoning behind
# each field, its known reliability caveats, and how they are meant to be
# combined. No single field here is sufficient on its own, and none should ever
# drive gating or enforcement decisions.
module ClientSignals
  DEFAULT_HEADER_PREFIX = "Fly"

  MAX_INVOKED_BY_LEN = 64
  INVOKED_BY_PATTERN = /\A[a-z0-9][a-z0-9-]{0,63}\z/.freeze

  OPERATOR_CI = "ci"
  OPERATOR_AGENT = "agent"
  OPERATOR_INTERACTIVE = "interactive"
  OPERATOR_UNKNOWN = "unknown"

  PARENT_NODE = "node"
  PARENT_PYTHON = "python"
  PARENT_SHELL = "shell"
  PARENT_OTHER = "other"

  PYTHON_NAMES = %w[python python3 python2].freeze
  SHELL_NAMES = %w[bash zsh fish sh dash ksh tcsh csh cmd powershell pwsh].freeze

  # Mirrors ../spec/markers.json. The table is duplicated in native source in
  # every language package so runtime behaviour stays dependency-free; the
  # spec-contract test is what keeps this copy honest.
  KNOWN_MARKERS = [
    { agent: "claude-code", env: "CLAUDECODE", kind: :exact_value, values: ["1"] },
    { agent: "claude-code", env: "CLAUDE_CODE_ENTRYPOINT", kind: :presence },
    { agent: "pi", env: "PI_CODING_AGENT", kind: :exact_value, values: ["true"] },
    { agent: "openclaw", env: "OPENCLAW_SHELL", kind: :exact_value, values: ["exec"] },
    { agent: "openclaw", env: "OPENCLAW_CLI", kind: :exact_value, values: ["1"] },
    { agent: "goose", env: "GOOSE_TERMINAL", kind: :exact_value, values: ["1"] },
    { agent: "hermes", env: "HERMES_SESSION_ID", kind: :presence },
    { agent: "codex", env: "CODEX_SANDBOX", kind: :presence },
    { agent: "codex", env: "CODEX_THREAD_ID", kind: :presence },
    { agent: "cursor", env: "CURSOR_TRACE_ID", kind: :presence },
    { agent: "cursor", env: "CURSOR_AGENT", kind: :presence },
    { agent: "gemini-cli", env: "GEMINI_CLI", kind: :presence },
    { agent: "kiro", env: "TERM_PROGRAM", kind: :exact_value, values: ["kiro"] },
    { agent: "antigravity", env: "ANTIGRAVITY_AGENT", kind: :presence },
    { agent: "augment", env: "AUGMENT_AGENT", kind: :presence },
    { agent: "replit", env: "REPL_ID", kind: :presence },
    { agent: "opencode", env: "OPENCODE", kind: :presence },
    { agent: "opencode", env: "OPENCODE_CALLER", kind: :presence },
    { agent: "opencode", env: "OPENCODE_CLIENT", kind: :presence },
    { agent: "copilot", env: "COPILOT_MODEL", kind: :presence },
    { agent: "copilot", env: "COPILOT_ALLOW_ALL", kind: :presence },
    { agent: "kilo-code", env: "KILO_PLATFORM", kind: :exact_value, values: ["vscode"] },
    # GROK_AGENT is dual-use: Grok Build sets it to "1" in the environment of
    # the subprocesses its tools spawn, but it is also a documented user-facing
    # setting whose value is a custom agent name or definition path. Matching
    # the exact value "1" keeps this to the tool-set form.
    { agent: "grok", env: "GROK_AGENT", kind: :exact_value, values: ["1"] },
  ].freeze

  # The set of coarse signals computed once per process.
  Signals = Struct.new(:interactive, :parent, :agent, :agent_source, :ci, keyword_init: true) do
    # One classification for the process's operator, by the precedence
    # ci > agent > interactive > unknown.
    #
    # This is a convenience for callers that want a single label describing who
    # is driving. The raw fields stay available for anything needing finer
    # grain.
    def operator
      return OPERATOR_CI if ci
      return OPERATOR_AGENT if agent && !agent.empty?
      return OPERATOR_INTERACTIVE if interactive

      OPERATOR_UNKNOWN
    end

    # The {prefix}-Client-* headers describing these signals. Agent headers are
    # omitted entirely when there is no agent, and the CI header only appears
    # when CI was detected, so absence carries no claim either way.
    def headers(prefix: DEFAULT_HEADER_PREFIX)
      result = {
        "#{prefix}-Client-Interactive" => interactive ? "true" : "false",
        "#{prefix}-Client-Parent" => parent.to_s,
      }

      unless agent.nil? || agent.empty?
        result["#{prefix}-Client-Agent"] = agent
        result["#{prefix}-Client-Agent-Source"] = agent_source.to_s
      end

      result["#{prefix}-Client-CI"] = "true" if ci

      result
    end

    # Merges the headers into target, which is anything responding to []=.
    def apply_headers(target, prefix: DEFAULT_HEADER_PREFIX)
      headers(prefix: prefix).each { |name, value| target[name] = value }

      target
    end

    # The parenthesised token to append to an outgoing User-Agent.
    def user_agent_suffix
      suffix = "interactive=#{interactive ? "true" : "false"}; parent=#{parent}"
      suffix += "; agent=#{agent}" unless agent.nil? || agent.empty?

      "(#{suffix})"
    end
  end

  class << self
    # Computes the current process's signals fresh. Pure aside from reading
    # process state, and deliberately uncached: callers wanting one value for
    # the process lifetime should use detect_once.
    def detect
      agent, source = detect_agent

      Signals.new(
        interactive: interactive?,
        parent: parent_bucket,
        agent: agent,
        agent_source: source,
        ci: ci?,
      )
    end

    # The process-wide signals, computed once and cached. Detection reads the
    # environment and the parent process, so long-lived clients should fetch
    # this once at construction time rather than per request.
    def detect_once
      @detect_once ||= detect
    end

    # Clears the detect_once cache. Tests only.
    def reset_cache_for_test
      @detect_once = nil
    end

    def known_agents
      @known_agents ||= KNOWN_MARKERS.map { |marker| marker[:agent] }.uniq.freeze
    end

    # Validates and normalizes a self-declared agent name before it is ever put
    # on the wire. Returns [name, true] for a bare tool-name identifier and
    # ["", false] for anything else, which callers should treat as no
    # declaration rather than emitting a rejected value.
    def sanitize_invoked_by(value)
      return ["", false] unless value.is_a?(String)

      sanitized = value.strip.downcase
      return ["", false] if sanitized.empty? || sanitized.length > MAX_INVOKED_BY_LEN
      return ["", false] unless INVOKED_BY_PATTERN.match?(sanitized)

      [sanitized, true]
    end

    # Buckets a raw parent-process name into one of node, python, shell or
    # other. Never returns the raw name.
    def classify_parent_name(raw)
      name = File.basename(raw.to_s).downcase
      name = name.delete_suffix(".exe")

      return PARENT_NODE if name == PARENT_NODE
      return PARENT_PYTHON if PYTHON_NAMES.include?(name)
      return PARENT_SHELL if SHELL_NAMES.include?(name)

      PARENT_OTHER
    end

    private

    def detect_agent
      if ENV.key?("FLY_INVOKED_BY")
        agent, ok = sanitize_invoked_by(ENV["FLY_INVOKED_BY"])
        return [agent, "env:FLY_INVOKED_BY"] if ok
      end

      KNOWN_MARKERS.each do |marker|
        next unless ENV.key?(marker[:env])

        case marker[:kind]
        when :presence
          return [marker[:agent], "env:#{marker[:env]}"]
        when :exact_value
          return [marker[:agent], "env:#{marker[:env]}"] if marker[:values].include?(ENV[marker[:env]])
        end
      end

      if ENV.key?("AGENT")
        agent, ok = sanitize_invoked_by(ENV["AGENT"])
        return [agent, "env:AGENT"] if ok
      end

      ["", ""]
    end

    def interactive?
      $stdout.tty?
    rescue StandardError
      false
    end

    # Presence, not a non-empty value: some CI systems set CI to the empty
    # string and that still means CI.
    def ci?
      ENV.key?("CI") || ENV.key?("GITHUB_ACTIONS")
    end

    def parent_bucket
      classify_parent_name(lookup_parent_name(Process.ppid))
    end

    # Reads the parent's name from procfs. There is deliberately no fallback
    # for platforms without /proc, macOS included: spawning a subprocess to ask
    # is forbidden, and "other" is an honest answer. The python package makes
    # the same trade.
    def lookup_parent_name(ppid)
      File.read("/proc/#{ppid}/comm").strip
    rescue StandardError
      ""
    end
  end
end
