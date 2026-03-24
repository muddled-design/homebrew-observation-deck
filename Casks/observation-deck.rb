cask "observation-deck" do
  version "1.0.0"
  sha256 "612dac8a173e80b036103b6671267b17b826c0a1baba87843a869570c1283479"

  url "https://github.com/muddled-design/ObservationDeck/releases/download/v#{version}/ClaudeMonitor-#{version}.dmg"
  name "Observation Deck"
  desc "Floating macOS dashboard that monitors all active Claude Code sessions"
  homepage "https://github.com/muddled-design/ObservationDeck"

  depends_on macos: ">= :sonoma"

  app "ClaudeMonitor.app"

  postflight do
    # Install the monitor hook script
    hook_dest = File.expand_path("~/.claude/monitor-hook.sh")
    status_dir = File.expand_path("~/.claude/monitor-status")
    settings_file = File.expand_path("~/.claude/settings.json")

    FileUtils.mkdir_p(File.dirname(hook_dest))
    FileUtils.mkdir_p(status_dir)

    # Write the hook script
    File.write(hook_dest, HOOK_SCRIPT)
    FileUtils.chmod(0755, hook_dest)

    # Register hooks in settings.json
    require "json"
    hook_command = "bash ~/.claude/monitor-hook.sh"
    events = %w[Stop Notification PreToolUse PostToolUse SubagentStart SubagentStop]

    settings = if File.exist?(settings_file)
      JSON.parse(File.read(settings_file))
    else
      {}
    end

    hooks = settings["hooks"] || {}
    hook_entry = { "type" => "command", "command" => hook_command, "async" => true }

    events.each do |event|
      rules = hooks[event] || []
      found = rules.any? { |r| (r["hooks"] || []).any? { |h| h["command"] == hook_command } }
      unless found
        if rules.empty?
          rules << { "hooks" => [hook_entry] }
        else
          rules[0]["hooks"] ||= []
          rules[0]["hooks"] << hook_entry
        end
        hooks[event] = rules
      end
    end

    settings["hooks"] = hooks
    File.write(settings_file, JSON.pretty_generate(settings))

    # Launch the app
    system_command "/usr/bin/open", args: ["#{appdir}/ClaudeMonitor.app"]
  end

  uninstall_postflight do
    # Remove hook script
    hook_path = File.expand_path("~/.claude/monitor-hook.sh")
    File.delete(hook_path) if File.exist?(hook_path)

    # Remove hook entries from settings.json
    settings_file = File.expand_path("~/.claude/settings.json")
    if File.exist?(settings_file)
      require "json"
      settings = JSON.parse(File.read(settings_file))
      hooks = settings["hooks"] || {}
      hook_command = "bash ~/.claude/monitor-hook.sh"

      hooks.each do |event, rules|
        rules.each do |rule|
          (rule["hooks"] || []).reject! { |h| h["command"] == hook_command }
        end
        rules.reject! { |r| (r["hooks"] || []).empty? }
      end
      hooks.reject! { |_, v| v.empty? }

      settings["hooks"] = hooks
      File.write(settings_file, JSON.pretty_generate(settings))
    end
  end

  HOOK_SCRIPT = <<~'BASH'
    #!/bin/bash
    # Claude Code hook script for Observation Deck
    # Reads hook event JSON from stdin and writes a status signal file.

    INPUT=$(cat)

    eval "$(echo "$INPUT" | /usr/bin/python3 -c "
    import sys, json, os
    d = json.load(sys.stdin)
    sid = d.get('session_id', '')
    event = d.get('hook_event_name', '')
    ntype = d.get('notification_type', '')
    cwd = d.get('cwd', '')
    tp = d.get('transcript_path', '')
    tsid = os.path.splitext(os.path.basename(tp))[0] if tp else sid
    print(f'SESSION_ID=\"{sid}\"')
    print(f'HOOK_EVENT=\"{event}\"')
    print(f'NOTIF_TYPE=\"{ntype}\"')
    print(f'CWD=\"{cwd}\"')
    print(f'TRANSCRIPT_SESSION_ID=\"{tsid}\"')
    " 2>/dev/null)"

    [ -z "$SESSION_ID" ] && exit 0

    STATUS_DIR="$HOME/.claude/monitor-status"
    mkdir -p "$STATUS_DIR"

    case "$HOOK_EVENT" in
      Stop)
        STATUS="idle"
        ;;
      Notification)
        case "$NOTIF_TYPE" in
          permission_prompt|elicitation_dialog)
            STATUS="needs_input"
            ;;
          *)
            STATUS="idle"
            ;;
        esac
        ;;
      PreToolUse|SubagentStart|PostToolUse|SubagentStop)
        STATUS="running"
        ;;
      *)
        STATUS="running"
        ;;
    esac

    echo "{\"session_id\":\"$SESSION_ID\",\"transcript_session_id\":\"$TRANSCRIPT_SESSION_ID\",\"status\":\"$STATUS\",\"event\":\"$HOOK_EVENT\",\"notification_type\":\"$NOTIF_TYPE\",\"cwd\":\"$CWD\",\"timestamp\":$(date +%s)}" > "$STATUS_DIR/$SESSION_ID.json"

    if [ "$TRANSCRIPT_SESSION_ID" != "$SESSION_ID" ] && [ -n "$TRANSCRIPT_SESSION_ID" ]; then
        cp "$STATUS_DIR/$SESSION_ID.json" "$STATUS_DIR/$TRANSCRIPT_SESSION_ID.json"
    fi
  BASH
end
