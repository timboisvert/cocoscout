# frozen_string_literal: true

# SignUpFormStatusService provides a unified API for understanding the current
# state and timing of a sign-up form. This centralizes all the logic for:
# - What is the overall status of the form?
# - When does registration open/close?
# - What should be displayed to users?
#
# This replaces scattered query logic in views with a single source of truth.
class SignUpFormStatusService
  attr_reader :sign_up_form

  def initialize(sign_up_form)
    @sign_up_form = sign_up_form
    @now = Time.current
  end

  # ===========================================
  # MAIN STATUS API
  # ===========================================

  # Returns a status hash with all the information needed to display the form's state
  def status
    @status ||= build_status
  end

  # Quick accessors
  def accepting_registrations?
    status[:accepting_registrations]
  end

  def status_label
    status[:label]
  end

  def status_color
    status[:color]
  end

  def next_event
    status[:next_event]
  end

  def next_opening
    status[:next_opening]
  end

  # Returns an array of human-readable explanation strings for the current status
  def status_explanation
    @status_explanation ||= build_status_explanation
  end

  # ===========================================
  # REPEATED EVENT SPECIFIC
  # ===========================================

  # Get all upcoming instances with their status
  def upcoming_instances
    return [] unless sign_up_form.repeated?

    @upcoming_instances ||= sign_up_form.sign_up_form_instances
      .includes(:show, :sign_up_slots)
      .joins(:show)
      .where("shows.date_and_time > ?", @now)
      .where.not(status: "cancelled")
      .where.not("shows.canceled = ?", true)
      .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")
      .map { |instance| build_instance_status(instance) }
  end

  # Get instances that are currently accepting registrations
  def open_instances
    upcoming_instances.select { |i| i[:status] == "open" }
  end

  # Get instances that will open in the future
  def scheduled_instances
    upcoming_instances.select { |i| i[:status] == "scheduled" }
  end

  # Get instances that are still initializing
  def initializing_instances
    upcoming_instances.select { |i| i[:status] == "initializing" }
  end

  # Get instances that are updating (settings recently changed)
  def updating_instances
    upcoming_instances.select { |i| i[:status] == "updating" }
  end

  private

  def build_status
    case sign_up_form.scope
    when "repeated"
      build_repeated_status
    when "single_event"
      build_single_event_status
    when "shared_pool"
      build_shared_pool_status
    else
      build_unknown_status
    end
  end

  def build_repeated_status
    # Find currently open instances (for upcoming events)
    open = open_instances.first
    scheduled = scheduled_instances.first
    next_upcoming = upcoming_instances.first

    # Calculate totals for open instances
    total_regs = open_instances.sum { |i| i[:registration_count] }
    total_cap = open_instances.sum { |i| i[:total_capacity] }
    total_spots_remaining = open_instances.sum { |i| i[:spots_remaining] }

    if !sign_up_form.active?
      {
        state: :paused,
        label: "Paused",
        color: "gray",
        accepting_registrations: false,
        next_event: next_upcoming,
        next_opening: nil,
        open_count: 0,
        scheduled_count: 0,
        total_registrations: 0,
        total_capacity: 0
      }
    elsif open && total_spots_remaining <= 0
      # All open instances are full
      {
        state: :full,
        label: "Full",
        color: "gray",
        accepting_registrations: false,
        next_event: open,
        next_opening: scheduled,
        open_count: open_instances.count,
        scheduled_count: scheduled_instances.count,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif open
      {
        state: :accepting,
        label: "Accepting Sign-ups",
        color: "green",
        accepting_registrations: true,
        next_event: open,
        next_opening: nil,
        open_count: open_instances.count,
        scheduled_count: scheduled_instances.count,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif scheduled
      days_until = days_until_date(scheduled[:opens_at])
      {
        state: :scheduled,
        label: format_opens_in(days_until),
        color: "amber",
        accepting_registrations: false,
        next_event: next_upcoming,
        next_opening: scheduled,
        open_count: 0,
        scheduled_count: scheduled_instances.count,
        total_registrations: 0,
        total_capacity: 0
      }
    elsif updating_instances.any?
      # Has upcoming events but they're updating after settings change
      {
        state: :updating,
        label: "Updating...",
        color: "blue",
        accepting_registrations: false,
        next_event: next_upcoming,
        next_opening: nil,
        open_count: 0,
        scheduled_count: 0,
        total_registrations: 0,
        total_capacity: 0
      }
    elsif initializing_instances.any?
      # Has upcoming events but they're still initializing
      {
        state: :initializing,
        label: "Initializing...",
        color: "blue",
        accepting_registrations: false,
        next_event: next_upcoming,
        next_opening: nil,
        open_count: 0,
        scheduled_count: 0,
        total_registrations: 0,
        total_capacity: 0
      }
    elsif next_upcoming
      # Has upcoming events but no opens_at set (instant open?)
      {
        state: :accepting,
        label: "Accepting Sign-ups",
        color: "green",
        accepting_registrations: true,
        next_event: next_upcoming,
        next_opening: nil,
        open_count: 1,
        scheduled_count: 0,
        total_registrations: next_upcoming[:registration_count],
        total_capacity: next_upcoming[:total_capacity]
      }
    else
      {
        state: :no_events,
        label: "No upcoming events",
        color: "gray",
        accepting_registrations: false,
        next_event: nil,
        next_opening: nil,
        open_count: 0,
        scheduled_count: 0,
        total_registrations: 0,
        total_capacity: 0
      }
    end
  end

  def build_single_event_status
    instance = sign_up_form.sign_up_form_instances.includes(:sign_up_slots, :sign_up_registrations).first
    show = instance&.show

    # Calculate totals
    total_regs = instance&.registration_count || 0
    total_cap = instance&.total_capacity || 0

    if !sign_up_form.active?
      {
        state: :paused,
        label: "Paused",
        color: "gray",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: instance&.status,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif instance.nil?
      {
        state: :initializing,
        label: "Initializing...",
        color: "blue",
        accepting_registrations: false,
        event_date: nil,
        instance_status: nil,
        total_registrations: 0,
        total_capacity: 0
      }
    elsif instance.status == "initializing"
      {
        state: :initializing,
        label: "Initializing...",
        color: "blue",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: "initializing",
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif instance.status == "updating"
      {
        state: :updating,
        label: "Updating...",
        color: "blue",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: "updating",
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif instance.status == "open"
      # Check if full before allowing registrations
      if instance.spots_remaining <= 0
        {
          state: :full,
          label: "Full",
          color: "gray",
          accepting_registrations: false,
          event_date: show&.date_and_time,
          instance_status: "open",
          total_registrations: total_regs,
          total_capacity: total_cap
        }
      else
        {
          state: :accepting,
          label: "Accepting Sign-ups",
          color: "green",
          accepting_registrations: true,
          event_date: show&.date_and_time,
          instance_status: "open",
          total_registrations: total_regs,
          total_capacity: total_cap
        }
      end
    elsif instance.status == "scheduled" && instance.opens_at
      days_until = days_until_date(instance.opens_at)
      {
        state: :scheduled,
        label: format_opens_in(days_until),
        color: "amber",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: "scheduled",
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif instance.status == "closed"
      {
        state: :closed,
        label: "Closed",
        color: "gray",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: "closed",
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    else
      {
        state: :unknown,
        label: instance.status.titleize,
        color: "gray",
        accepting_registrations: false,
        event_date: show&.date_and_time,
        instance_status: instance.status,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    end
  end

  def build_shared_pool_status
    # Calculate totals for shared pool (slots are directly on the form)
    total_regs = sign_up_form.sign_up_registrations.active.count
    total_cap = sign_up_form.sign_up_slots.where(is_held: false).sum(:capacity)

    if !sign_up_form.active?
      {
        state: :paused,
        label: "Paused",
        color: "gray",
        accepting_registrations: false,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif sign_up_form.opens_at.present? && sign_up_form.opens_at > @now
      days_until = days_until_date(sign_up_form.opens_at)
      {
        state: :scheduled,
        label: format_opens_in(days_until),
        color: "amber",
        accepting_registrations: false,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif sign_up_form.closes_at.present? && sign_up_form.closes_at <= @now
      {
        state: :closed,
        label: "Closed",
        color: "gray",
        accepting_registrations: false,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    elsif total_regs >= total_cap && total_cap > 0
      # All spots filled
      {
        state: :full,
        label: "Full",
        color: "gray",
        accepting_registrations: false,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    else
      {
        state: :accepting,
        label: "Accepting Sign-ups",
        color: "green",
        accepting_registrations: true,
        total_registrations: total_regs,
        total_capacity: total_cap
      }
    end
  end

  def build_unknown_status
    {
      state: :unknown,
      label: "Unknown",
      color: "gray",
      accepting_registrations: false,
      total_registrations: 0,
      total_capacity: 0
    }
  end

  def build_instance_status(instance)
    show = instance.show

    {
      instance_id: instance.id,
      show_id: show.id,
      show_date: show.date_and_time,
      show_name: show.respond_to?(:name_with_date) ? show.name_with_date : show.event_type.titleize,
      days_until_show: days_until_date(show.date_and_time),
      opens_at: instance.opens_at,
      closes_at: instance.closes_at,
      days_until_opens: instance.opens_at ? days_until_date(instance.opens_at) : nil,
      days_until_closes: instance.closes_at ? days_until_date(instance.closes_at) : nil,
      status: instance.status,
      is_open: instance.status == "open",
      is_initializing: instance.status == "initializing",
      spots_remaining: instance.spots_remaining,
      total_capacity: instance.total_capacity,
      registration_count: instance.registration_count
    }
  end

  def days_until_date(date)
    return nil unless date
    ((date - @now) / 1.day).to_f
  end

  def format_opens_in(days)
    return "Opens soon" if days.nil?

    if days < 0
      "Open now"
    elsif days < 1
      hours = (days * 24).ceil
      hours <= 1 ? "Opens in 1 hour" : "Opens in #{hours} hours"
    elsif days < 2
      "Opens tomorrow"
    else
      "Opens in #{days.floor} days"
    end
  end

  def build_status_explanation
    explanations = []

    # Form active/inactive state
    if sign_up_form.active?
      explanations << { check: true, text: "Sign-up form is turned on" }
    else
      explanations << { check: false, text: "Sign-up form is turned off" }
      return explanations # No point explaining more if form is off
    end

    case sign_up_form.scope
    when "repeated"
      build_repeated_explanation(explanations)
    when "single_event"
      build_single_event_explanation(explanations)
    when "shared_pool"
      build_shared_pool_explanation(explanations)
    end

    explanations
  end

  def build_repeated_explanation(explanations)
    # Check event matching rules
    case sign_up_form.event_matching
    when "all"
      explanations << { check: true, text: "Applies to all events" }
    when "event_types"
      if sign_up_form.event_type_filter.present?
        types = sign_up_form.event_type_filter.map(&:titleize).to_sentence
        explanations << { check: true, text: "Applies to event types: #{types}" }
      else
        explanations << { check: true, text: "Applies to all event types" }
      end
    when "manual"
      count = sign_up_form.sign_up_form_shows.count
      explanations << { check: count > 0, text: "#{count} specific events selected" }
    end

    # Count instances and their statuses
    open_count = open_instances.count
    scheduled_count = scheduled_instances.count
    total_upcoming = upcoming_instances.count

    if total_upcoming == 0
      explanations << { check: false, text: "No upcoming events match the criteria" }
    else
      explanations << { check: true, text: "#{total_upcoming} upcoming event#{'s' if total_upcoming != 1} match" }
    end

    if open_count > 0
      # Show timing context for open events
      next_open = open_instances.first
      timing_context = build_repeated_timing_context(next_open)
      if timing_context
        explanations << { check: true, text: "#{open_count} event#{'s' if open_count != 1} currently accepting sign-ups (#{timing_context})" }
      else
        explanations << { check: true, text: "#{open_count} event#{'s' if open_count != 1} currently accepting sign-ups" }
      end
    elsif scheduled_count > 0
      next_open = scheduled_instances.first
      if next_open && next_open[:opens_at]
        days_until = (next_open[:opens_at].to_date - @now.to_date).to_i
        time_context = if days_until == 0
          "today at #{next_open[:opens_at].strftime('%-l:%M %p').strip}"
        elsif days_until == 1
          "tomorrow at #{next_open[:opens_at].strftime('%-l:%M %p').strip}"
        else
          next_open[:opens_at].strftime("%B %d at %-l:%M %p").strip
        end
        explanations << { check: false, text: "Next event opens #{time_context}" }
      else
        explanations << { check: false, text: "#{scheduled_count} event#{'s' if scheduled_count != 1} scheduled to open" }
      end
    end
  end

  def build_single_event_explanation(explanations)
    instance = sign_up_form.sign_up_form_instances.includes(:show).first
    show = instance&.show

    if show.nil?
      explanations << { check: false, text: "Waiting for event setup to complete" }
      return
    end

    # Show event info with date context
    days_until = (show.date_and_time.to_date - @now.to_date).to_i
    event_info = "#{show.event_type.titleize} on #{show.date_and_time.strftime('%B %d, %Y at %-I:%M %p')}"
    if days_until == 0
      event_info += " (today)"
    elsif days_until == 1
      event_info += " (tomorrow)"
    elsif days_until > 0 && days_until <= 7
      event_info += " (in #{days_until} days)"
    end
    explanations << { check: true, text: event_info }

    if show.date_and_time < @now
      explanations << { check: false, text: "Event has already passed" }
      return
    end

    case instance&.status
    when "open"
      # Include open date context if there was a scheduled opens_at
      if instance.opens_at.present?
        opened_on = instance.opens_at.strftime("%B %-d").strip
        explanations << { check: true, text: "Registration window is open (opened #{opened_on})" }
      else
        explanations << { check: true, text: "Registration window is open" }
      end
    when "scheduled"
      # For fixed schedule forms, use the form's opens_at if instance doesn't have one
      effective_opens_at = instance.opens_at || @sign_up_form.opens_at
      if effective_opens_at
        days_until = (effective_opens_at.to_date - @now.to_date).to_i
        time_context = if days_until == 0
          "today at #{effective_opens_at.strftime('%-l:%M %p').strip}"
        elsif days_until == 1
          "tomorrow at #{effective_opens_at.strftime('%-l:%M %p').strip}"
        else
          effective_opens_at.strftime("%B %d at %-l:%M %p").strip
        end
        explanations << { check: false, text: "Registration opens #{time_context}" }
      else
        explanations << { check: false, text: "Registration is scheduled to open" }
      end
    when "closed"
      explanations << { check: false, text: "Registration window has closed" }
    when "initializing"
      explanations << { check: false, text: "Setting up registration slots..." }
    end

    if instance&.closes_at && instance.closes_at > @now
      days_until = (instance.closes_at.to_date - @now.to_date).to_i
      time_context = if days_until == 0
        "today at #{instance.closes_at.strftime('%-l:%M %p').strip}"
      elsif days_until == 1
        "tomorrow at #{instance.closes_at.strftime('%-l:%M %p').strip}"
      else
        instance.closes_at.strftime("%B %d at %-l:%M %p").strip
      end
      explanations << { check: true, text: "Closes #{time_context}" }
    end
  end

  def build_repeated_timing_context(instance_status)
    return nil unless instance_status

    # Build a context string like "opens 7 days before, closes when event starts"
    parts = []

    # Opening info
    if sign_up_form.schedule_mode == "relative" && sign_up_form.opens_days_before.present? && sign_up_form.opens_days_before > 0
      parts << "opens #{sign_up_form.opens_days_before} day#{'s' if sign_up_form.opens_days_before != 1} before"
    end

    # Closing info
    if sign_up_form.schedule_mode == "relative"
      case sign_up_form.closes_mode
      when "event_start"
        parts << "closes when event starts"
      when "event_end"
        parts << "closes when event ends"
      when "custom"
        if sign_up_form.closes_offset_value.present?
          value = sign_up_form.closes_offset_value.abs
          unit = sign_up_form.closes_offset_unit || "hours"
          direction = sign_up_form.closes_offset_value < 0 ? "after" : "before"
          parts << "closes #{value} #{unit} #{direction} event"
        end
      end
    end

    # Add next event timing
    if instance_status[:days_until_show]
      days = instance_status[:days_until_show].floor
      if days == 0
        parts << "next event today"
      elsif days == 1
        parts << "next event tomorrow"
      elsif days > 0
        parts << "next event in #{days} days"
      end
    end

    parts.any? ? parts.join(", ") : nil
  end

  def build_shared_pool_explanation(explanations)
    # Check opens_at
    if sign_up_form.opens_at.present?
      if sign_up_form.opens_at > @now
        days_until = (sign_up_form.opens_at.to_date - @now.to_date).to_i
        time_context = if days_until == 0
          "today at #{sign_up_form.opens_at.strftime('%-l:%M %p').strip}"
        elsif days_until == 1
          "tomorrow at #{sign_up_form.opens_at.strftime('%-l:%M %p').strip}"
        else
          sign_up_form.opens_at.strftime("%B %d at %-l:%M %p").strip
        end
        explanations << { check: false, text: "Opens #{time_context}" }
      else
        explanations << { check: true, text: "Opened on #{sign_up_form.opens_at.strftime('%B %d')}" }
      end
    else
      explanations << { check: true, text: "Open immediately (no scheduled start)" }
    end

    # Check closes_at
    if sign_up_form.closes_at.present?
      if sign_up_form.closes_at <= @now
        explanations << { check: false, text: "Closed on #{sign_up_form.closes_at.strftime('%B %d')}" }
      else
        days_until = (sign_up_form.closes_at.to_date - @now.to_date).to_i
        time_context = if days_until == 0
          "today at #{sign_up_form.closes_at.strftime('%-l:%M %p').strip}"
        elsif days_until == 1
          "tomorrow at #{sign_up_form.closes_at.strftime('%-l:%M %p').strip}"
        else
          sign_up_form.closes_at.strftime("%B %d at %-l:%M %p").strip
        end
        explanations << { check: true, text: "Closes #{time_context}" }
      end
    else
      explanations << { check: true, text: "No closing date set" }
    end

    # Slot info
    available_slots = sign_up_form.sign_up_slots.where(is_held: false).count
    total_capacity = sign_up_form.sign_up_slots.where(is_held: false).sum(:capacity)
    explanations << { check: available_slots > 0, text: "#{available_slots} slot#{'s' if available_slots != 1} available (#{total_capacity} total capacity)" }
  end
end
