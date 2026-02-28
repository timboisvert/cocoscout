# frozen_string_literal: true

module ShowTicketingsHelper
  # Engine status badge classes
  def engine_status_badge_classes(status)
    base = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
    colors = case status.to_s
    when "active" then "bg-green-100 text-green-800"
    when "syncing" then "bg-blue-100 text-blue-800 animate-pulse"
    when "paused" then "bg-yellow-100 text-yellow-800"
    when "draft" then "bg-gray-100 text-gray-800"
    when "archived" then "bg-gray-100 text-gray-500"
    else "bg-gray-100 text-gray-800"
    end
    "#{base} #{colors}"
  end

  # Determine show status from remote events
  def determine_show_status(remote_events)
    return "pending" if remote_events.empty?

    statuses = remote_events.map(&:sync_status)
    if statuses.any? { |s| s.to_s == "error" }
      "error"
    elsif statuses.any? { |s| s.to_s.include?("pending") }
      "syncing"
    elsif statuses.all? { |s| s.to_s == "synced" }
      "listed"
    else
      "pending"
    end
  end

  # Show status indicator classes (the colored dot)
  def show_status_indicator_classes(status)
    base = "w-3 h-3 rounded-full flex-shrink-0"
    colors = case status.to_s
    when "listed" then "bg-green-500"
    when "syncing" then "bg-blue-400 animate-pulse"
    when "error" then "bg-red-500"
    else "bg-gray-300"
    end
    "#{base} #{colors}"
  end

  # Show status text classes
  def show_status_text_classes(status)
    case status.to_s
    when "listed" then "text-green-600"
    when "syncing" then "text-blue-600"
    when "error" then "text-red-600"
    else "text-gray-500"
    end
  end

  # Show status label
  def show_status_label(status)
    case status.to_s
    when "listed" then "Listed"
    when "syncing" then "Syncing..."
    when "error" then "Error"
    else "Pending"
    end
  end

  # Show status tooltip
  def show_status_tooltip(status, remote_events)
    case status.to_s
    when "listed"
      providers = remote_events.map { |e| e.ticketing_provider.name }.join(", ")
      "Listed on #{providers}"
    when "syncing"
      "Sync in progress..."
    when "error"
      errors = remote_events.select { |e| e.sync_status.to_s == "error" }
        .map { |e| "#{e.ticketing_provider.name}: #{e.last_sync_error}" }
        .join("; ")
      "Errors: #{errors}"
    else
      "Waiting for sync"
    end
  end

  # Provider badge classes based on sync status
  def provider_badge_classes(sync_status)
    case sync_status.to_s
    when "synced"
      "bg-green-100 text-green-700"
    when "error"
      "bg-red-100 text-red-700"
    when "pending_create", "pending_update", "pending_delete"
      "bg-blue-100 text-blue-700"
    else
      "bg-gray-100 text-gray-700"
    end
  end

  # Activity icon based on event type
  def activity_icon(event_type)
    icon_svg = case event_type.to_s
    when "sync_started"
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />'
    when "sync_complete"
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />'
    when "listing_created"
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />'
    when "sales_received"
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />'
    when "error"
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />'
    else
                 '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />'
    end

    bg_color = case event_type.to_s
    when "sync_started" then "bg-blue-100"
    when "sync_complete" then "bg-green-100"
    when "listing_created" then "bg-purple-100"
    when "sales_received" then "bg-pink-100"
    when "error" then "bg-red-100"
    else "bg-gray-100"
    end

    text_color = case event_type.to_s
    when "sync_started" then "text-blue-600"
    when "sync_complete" then "text-green-600"
    when "listing_created" then "text-purple-600"
    when "sales_received" then "text-pink-600"
    when "error" then "text-red-600"
    else "text-gray-600"
    end

    %(<div class="w-8 h-8 rounded-full #{bg_color} flex items-center justify-center">
      <svg class="w-4 h-4 #{text_color}" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        #{icon_svg}
      </svg>
    </div>).html_safe
  end
end
