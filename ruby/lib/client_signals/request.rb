# frozen_string_literal: true

require_relative "../client_signals"

module ClientSignals
  # Bounded server-side classification and route helpers for incoming
  # client-signal headers.
  #
  # The operator and agent values returned here are safe to use as metric
  # labels: every one of them comes from a fixed set, and a caller-supplied
  # agent name never reaches a label unless the marker table already knows it.
  #
  # This is aggregate observability only. Client signals are self-reported and
  # must not be used for authentication, authorization, rate limiting,
  # enforcement, or any other per-request trust decision. See
  # ../spec/request-metrics.md for the contract this implements.
  module Request
    OPERATOR_CI = "ci"
    OPERATOR_AGENT = "agent"
    OPERATOR_INTERACTIVE = "interactive"
    OPERATOR_AUTOMATED_UNATTRIBUTED = "automated_unattributed"
    OPERATOR_UNINSTRUMENTED = "uninstrumented"

    AGENT_NONE = "none"
    AGENT_OTHER = "other"

    UNINSTRUMENTED = { operator: OPERATOR_UNINSTRUMENTED, agent: AGENT_NONE }.freeze

    INTERACTIVE_HEADER = "Fly-Client-Interactive"
    AGENT_HEADER = "Fly-Client-Agent"
    CI_HEADER = "Fly-Client-CI"

    TRUE_VALUES = %w[1 t true].freeze
    FALSE_VALUES = %w[0 f false].freeze

    UNKNOWN_METHOD = "UNKNOWN"
    UNMATCHED_ROUTE = "unmatched"

    module_function

    # Classifies incoming header values into bounded operator and agent labels.
    #
    # interactive is the instrumentation sentinel: a request without a valid one
    # is uninstrumented whatever else it sent. Parent is deliberately not
    # considered, because parent-process lookup is not reliable enough to
    # classify a request. CI takes precedence over agent, which takes precedence
    # over interactive, and the agent label survives a CI classification so the
    # overlap stays visible in aggregate.
    def classify(interactive, agent, ci)
      interactive = parse_bool(interactive)
      return UNINSTRUMENTED if interactive.nil?

      agent = normalize_agent(agent)

      operator = if parse_bool(ci)
        OPERATOR_CI
      elsif agent != AGENT_NONE
        OPERATOR_AGENT
      elsif interactive
        OPERATOR_INTERACTIVE
      else
        OPERATOR_AUTOMATED_UNATTRIBUTED
      end

      { operator: operator, agent: agent }
    end

    # classify, reading the three headers off anything that responds to [] with
    # a canonical header name. That covers a plain Hash, Rack::Utils::HeaderHash
    # and ActionDispatch::Http::Headers alike.
    def classify_headers(headers)
      classify(headers[INTERACTIVE_HEADER], headers[AGENT_HEADER], headers[CI_HEADER])
    end

    # Returns [route_label, tracked]. A matched route template is always
    # preferred; for an unmatched request the raw path decides only whether the
    # request falls under a tracked prefix and is never returned, because a raw
    # path in a metric label is unbounded cardinality.
    def tracked_route(method, route_template, request_path, prefixes)
      method = method.to_s.strip.upcase
      method = UNKNOWN_METHOD if method.empty?

      if present?(route_template)
        return [method + " " + route_template, true] if matches_prefix?(route_template, prefixes)

        # A template outside the tracked prefixes is not tracked, even when the
        # raw path looks like it belongs. This stops a catch-all route from
        # being counted as a specific tracked one.
        return ["", false]
      end

      return [method + " " + UNMATCHED_ROUTE, true] if matches_prefix?(request_path, prefixes)

      ["", false]
    end

    # The bounded agent label: the normalized name when the marker table knows
    # it, "other" for a well-formed name it does not, "none" for anything that
    # is not a bare tool-name identifier.
    def normalize_agent(agent)
      name, ok = ClientSignals.sanitize_invoked_by(agent)
      return AGENT_NONE unless ok

      ClientSignals.known_agents.include?(name) ? name : AGENT_OTHER
    end

    # true, false, or nil for a value that is not a supported boolean. The nil
    # case is what separates an uninstrumented request from an instrumented
    # non-interactive one.
    def parse_bool(value)
      return nil unless value.is_a?(String)

      value = value.strip.downcase
      return true if TRUE_VALUES.include?(value)
      return false if FALSE_VALUES.include?(value)

      nil
    end

    # Prefix matching happens on path-segment boundaries, so /v1 matches /v1 and
    # /v1/... but not /v10. A trailing slash is insignificant, and "/" selects
    # every absolute path.
    def matches_prefix?(path, prefixes)
      return false unless path.is_a?(String)

      prefixes.any? do |prefix|
        prefix = prefix.to_s.sub(%r{/\z}, "")

        if prefix.empty?
          path.start_with?("/")
        else
          path == prefix || path.start_with?(prefix + "/")
        end
      end
    end

    def present?(value)
      value.is_a?(String) && !value.empty?
    end
  end
end
