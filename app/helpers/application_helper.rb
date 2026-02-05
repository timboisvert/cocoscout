# frozen_string_literal: true

module ApplicationHelper
  def impersonating?
    session[:user_doing_the_impersonating].present? || cookies.signed[:impersonator_user_id].present?
  end

  def current_user_can_manage?(production = nil)
    return false unless Current.user

    production ||= Current.production
    if production
      Current.user.manager_for_production?(production)
    else
      Current.user.manager?
    end
  end

  def current_user_can_review?(production = nil)
    return false unless Current.user

    production ||= Current.production
    return false unless production

    # Managers/viewers can always review
    return true if Current.user.role_for_production(production).present?

    # Check if user has reviewer access to any active audition cycle
    production.audition_cycles.where(active: true).any? do |cycle|
      Current.user.can_review_audition_cycle?(cycle)
    end
  end

  # Check if user has a role (manager/viewer) on the production, not just review access
  def current_user_has_role?(production = nil)
    return false unless Current.user

    production ||= Current.production
    return false unless production

    Current.user.role_for_production(production).present?
  end

  def current_user_is_global_manager?
    return false unless Current.user

    Current.user.manager?
  end

  def current_user_has_any_manage_access?
    return false unless Current.user

    # Check if user has any production company access with manager or viewer role,
    # OR has per-production permissions
    Current.user.organization_roles.exists?(company_role: %w[manager viewer]) ||
      Current.user.production_permissions.exists?
  end

  def social_platform_display_name(platform)
    case platform.to_s.downcase
    when "youtube"
      "YouTube"
    when "tiktok"
      "TikTok"
    when "linkedin"
      "LinkedIn"
    else
      platform.titleize
    end
  end

  def displayable_attachment?(attachment)
    attachment.respond_to?(:attached?) &&
      attachment.attached? &&
      attachment.respond_to?(:blob) &&
      attachment.blob.present? &&
      attachment.blob.persisted?
  end

  def pending_attachment?(attachment)
    attachment.respond_to?(:attached?) &&
      attachment.attached? &&
      (!attachment.respond_to?(:blob) || attachment.blob.blank? || !attachment.blob.persisted?)
  end

  def pagy_nav_tailwind(pagy, id: nil, aria_label: nil)
    id               = %( id="#{id}") if id
    link_classes     = "inline-flex items-center justify-center rounded-md border border-slate-200 px-3 py-1 text-sm font-medium text-slate-700 transition hover:border-pink-400 hover:bg-pink-50 hover:text-pink-600"
    active_classes   = "inline-flex items-center justify-center rounded-md border border-pink-500 bg-pink-500 px-3 py-1 text-sm font-semibold text-white"
    disabled_classes = "inline-flex items-center justify-center rounded-md border border-slate-200 px-3 py-1 text-sm text-slate-300 cursor-not-allowed"
    gap_classes      = "inline-flex items-center justify-center px-3 py-1 text-sm text-slate-400"

    anchor = lambda do |page, text = page.to_s, classes: nil, aria_label: nil|
      link_to text, pagy.page_url(page),
              class: classes,
              "aria-label": aria_label
    end

    html = %(<nav#{id} class="pagy-tailwind nav" aria-label="#{aria_label || 'Pagination'}"><ul class="flex items-center gap-2">#{
							 tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
						})

    # Build series manually: show first, last, current and nearby pages with gaps
    series = build_pagination_series(pagy.page, pagy.pages)
    series.each do |item|
      segment =
        case item
        when Integer
          if item == pagy.page
            %(<li><span class="#{active_classes}" aria-current="page">#{item}</span></li>)
          else
            %(<li>#{anchor.call(item, classes: link_classes)}</li>)
          end
        when :gap
          %(<li><span class="#{gap_classes}" aria-hidden="true">&hellip;</span></li>)
        end
      html << segment
    end
    html << %(#{tailwind_next_html(pagy, anchor, link_classes, disabled_classes)}</ul></nav>)

    html.html_safe
  end

  private

  # Build an array like [1, :gap, 4, 5, 6, :gap, 10] for pagination display
  def build_pagination_series(current_page, total_pages)
    return (1..total_pages).to_a if total_pages <= 7

    series = []
    # Always show first page
    series << 1

    # Calculate range around current page
    start_range = [ current_page - 1, 2 ].max
    end_range = [ current_page + 1, total_pages - 1 ].min

    # Add gap if needed before the range
    if start_range > 2
      series << :gap
    elsif start_range == 2
      series << 2
    end

    # Add pages in range (excluding first and last)
    (start_range..end_range).each do |p|
      series << p unless p == 1 || p == total_pages
    end

    # Add gap if needed after the range
    if end_range < total_pages - 1
      series << :gap
    elsif end_range == total_pages - 1
      series << (total_pages - 1)
    end

    # Always show last page
    series << total_pages unless total_pages == 1

    series.uniq
  end

  def tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
    if (p_prev = pagy.previous)
      %(<li>#{anchor.call(p_prev, 'Previous', classes: link_classes, aria_label: 'Previous page')}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">Previous</span></li>)
    end
  end

  def tailwind_next_html(pagy, anchor, link_classes, disabled_classes)
    if (p_next = pagy.next)
      %(<li>#{anchor.call(p_next, 'Next', classes: link_classes, aria_label: 'Next page')}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">Next</span></li>)
    end
  end

  def safe_headshot_url(entity, variant: :thumb)
    return nil unless entity

    # Handle both Person and Group
    if entity.respond_to?(:primary_headshot)
      headshot = entity.primary_headshot
      return nil unless headshot&.image&.attached?

      begin
        # Generate variant and return URL
        variant_obj = headshot.image.variant(variant)
        return rails_representation_url(variant_obj) if variant_obj
      rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
        Rails.logger.error("Failed to generate variant for #{entity.name}'s headshot: #{e.message}")
        return nil
      end
    elsif entity.respond_to?(:safe_headshot_variant)
      variant_obj = entity.safe_headshot_variant(variant)
      return url_for(variant_obj) if variant_obj
    end

    nil
  end

  def safe_poster_url(show, variant = :small)
    # Try show poster first
    variant_obj = show.safe_poster_variant(variant)
    return url_for(variant_obj) if variant_obj

    # Fall back to production's primary poster if available
    primary_poster = show.production.primary_poster
    if primary_poster
      poster_variant = primary_poster.safe_image_variant(variant)
      return url_for(poster_variant) if poster_variant
    end

    nil
  end

  def safe_logo_url(production, variant = :small)
    variant_obj = production.safe_logo_variant(variant)
    variant_obj ? url_for(variant_obj) : nil
  end

  # Returns CSS classes for event type badges
  # @param event_type [String] The event type (show, rehearsal, meeting, class, workshop)
  # @param style [Symbol] :badge for ring-style badges, :calendar for calendar-style badges
  # @param is_past [Boolean] For calendar style, whether the event is in the past (adds muted styling)
  # @return [String] Tailwind CSS classes
  def event_type_badge_classes(event_type, style: :badge, is_past: false)
    case style
    when :calendar
      if is_past
        "bg-gray-100 text-gray-600 border-gray-300"
      else
        case event_type.to_s
        when "rehearsal" then "bg-blue-100 text-blue-800 border-blue-300"
        when "meeting" then "bg-green-100 text-green-800 border-green-300"
        when "class" then "bg-purple-100 text-purple-800 border-purple-300"
        when "workshop" then "bg-amber-100 text-amber-800 border-amber-300"
        else "bg-pink-100 text-pink-800 border-pink-300"
        end
      end
    else # :badge
      case event_type.to_s
      when "rehearsal" then "bg-blue-50 text-blue-700 ring-blue-600/10"
      when "meeting" then "bg-green-50 text-green-700 ring-green-600/10"
      when "class" then "bg-purple-50 text-purple-700 ring-purple-600/10"
      when "workshop" then "bg-amber-50 text-amber-700 ring-amber-600/10"
      else "bg-pink-50 text-pink-700 ring-pink-600/10"
      end
    end
  end

  # Returns the display label for an event type from config
  def event_type_label(event_type)
    EventTypes.labels[event_type.to_s] || event_type.to_s.titleize
  end

  # Returns a display string for a show (for breadcrumbs, titles, etc.)
  # Format: "Dec 15 - Performance" or just "Performance" if include_date is false
  def show_display_name(show, include_date: true)
    name = show.display_name
    if include_date
      "#{show.date_and_time.strftime('%b %-d')} - #{name}"
    else
      name
    end
  end

  # Generate a vacancy link for a person/show combination
  def vacancy_link_for(person, show)
    token = VacancyController.generate_token(person)
    vacancy_url(show, token: token)
  end

  # Build tooltip text for sign-up registration slot display
  # Shows "Position X", "7:15 PM", or "B group" depending on slot mode
  def registration_slot_tooltip(registration)
    slot = registration.sign_up_slot
    sign_up_form = registration.sign_up_form

    slot_text = if slot&.name.present?
      # Always prefer the slot's name if it exists (covers all modes)
      slot.name
    elsif sign_up_form
      # Fallback for missing slot name
      "Position #{registration.position}"
    else
      "Position #{registration.position}"
    end

    display_name = registration.person&.name || registration.guest_name || "Guest"
    "#{display_name} - #{slot_text}"
  end

  # Render an SVG icon by name with optional CSS classes
  # Usage: icon("plus", class: "w-4 h-4 text-gray-500")
  def icon(name, options = {})
    css_class = options[:class] || "w-5 h-5"

    icons = {
      "plus" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" /></svg>',
      "eye" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" /></svg>',
      "file-text" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" /></svg>',
      "alert-triangle" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" /></svg>',
      "alert-circle" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" /></svg>',
      "check-circle" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "check" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" /></svg>',
      "x-circle" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "arrow-left" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" /></svg>',
      "arrow-right" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" /></svg>',
      "calendar" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5" /></svg>',
      "clock" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "building" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5m-18-18v18m10.5-18v18m6-13.5V21M6.75 6.75h.75m-.75 3h.75m-.75 3h.75m3-6h.75m-.75 3h.75m-.75 3h.75M6.75 21v-3.375c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21M3 3h12m-.75 4.5H21m-3.75 3.75h.008v.008h-.008v-.008Zm0 3h.008v.008h-.008v-.008Zm0 3h.008v.008h-.008v-.008Z" /></svg>',
      "user" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" /></svg>',
      "currency-dollar" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v12m-3-2.818.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "document" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" /></svg>',
      "pencil" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" /></svg>',
      "trash" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" /></svg>',
      "info" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z" /></svg>',
      "map-pin" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1 1 15 0Z" /></svg>',
      "phone" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 6.75c0 8.284 6.716 15 15 15h2.25a2.25 2.25 0 0 0 2.25-2.25v-1.372c0-.516-.351-.966-.852-1.091l-4.423-1.106c-.44-.11-.902.055-1.173.417l-.97 1.293c-.282.376-.769.542-1.21.38a12.035 12.035 0 0 1-7.143-7.143c-.162-.441.004-.928.38-1.21l1.293-.97c.363-.271.527-.734.417-1.173L6.963 3.102a1.125 1.125 0 0 0-1.091-.852H4.5A2.25 2.25 0 0 0 2.25 4.5v2.25Z" /></svg>',
      "envelope" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" /></svg>',
      "wrench" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75a4.5 4.5 0 0 1-4.884 4.484c-1.076-.091-2.264.071-2.95.904l-7.152 8.684a2.548 2.548 0 1 1-3.586-3.586l8.684-7.152c.833-.686.995-1.874.904-2.95a4.5 4.5 0 0 1 6.336-4.486l-3.276 3.276a3.004 3.004 0 0 0 2.25 2.25l3.276-3.276c.256.565.398 1.192.398 1.852Z" /></svg>',
      "dollar-sign" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v12m-3-2.818.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "file" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" /></svg>',
      "external-link" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" /></svg>',
      "banknotes" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z" /></svg>',
      "chart-pie" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 6a7.5 7.5 0 1 0 7.5 7.5h-7.5V6Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 10.5H21A7.5 7.5 0 0 0 13.5 3v7.5Z" /></svg>',
      "adjustments-horizontal" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 6h9.75M10.5 6a1.5 1.5 0 1 1-3 0m3 0a1.5 1.5 0 1 0-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-9.75 0h9.75" /></svg>',
      "plus-circle" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" /></svg>',
      "x" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" /></svg>',
      "x-mark" => '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" /></svg>'
    }

    svg = icons[name]
    return "" unless svg

    # Insert the class into the SVG tag
    svg.sub("<svg ", "<svg class=\"#{css_class}\" ").html_safe
  end

  # Simple markdown to HTML conversion for agreement content
  # Handles: headers, bold, lists, paragraphs
  def markdown_to_html(text)
    return "" if text.blank?

    html = text.dup

    # Convert headers (# Header)
    html.gsub!(/^### (.+)$/, '<h3 class="text-md font-semibold text-gray-900 mt-4 mb-2">\1</h3>')
    html.gsub!(/^## (.+)$/, '<h2 class="text-lg font-semibold text-gray-900 mt-6 mb-3">\1</h2>')
    html.gsub!(/^# (.+)$/, '<h1 class="text-xl font-bold text-gray-900 mb-4">\1</h1>')

    # Convert bold (**text**)
    html.gsub!(/\*\*(.+?)\*\*/, '<strong>\1</strong>')

    # Convert italic (*text*)
    html.gsub!(/\*(.+?)\*/, '<em>\1</em>')

    # Convert unordered lists (- item)
    html.gsub!(/^- (.+)$/, '<li class="ml-4">\1</li>')

    # Wrap consecutive list items in ul
    html.gsub!(/((?:<li[^>]*>.*<\/li>\n?)+)/) do |match|
      "<ul class=\"list-disc list-inside space-y-1 my-2\">#{match}</ul>"
    end

    html.html_safe
  end
end
