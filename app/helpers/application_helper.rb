# frozen_string_literal: true

module ApplicationHelper
  def impersonating?
    session[:user_doing_the_impersonating].present?
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

    anchor = lambda do |page, text = pagy.label_for(page), classes: nil, aria_label: nil|
      link_to text, pagy.url_for(page),
              class: classes,
              "aria-label": aria_label
    end

    html = %(<nav#{id} class="pagy-tailwind nav" aria-label="#{aria_label || 'Pagination'}"><ul class="flex items-center gap-2">#{
							 tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
						})
    pagy.series.each do |item|
      segment =
        case item
        when Integer
          %(<li>#{anchor.call(item, classes: link_classes)}</li>)
        when String
          %(<li><span class="#{active_classes}" aria-current="page">#{pagy.label_for(item)}</span></li>)
        when :gap
          %(<li><span class="#{gap_classes}" aria-hidden="true">&hellip;</span></li>)
        else
          raise Pagy::InternalError,
                "expected item types in series to be Integer, String or :gap; got #{item.inspect}"
        end
      html << segment
    end
    html << %(#{tailwind_next_html(pagy, anchor, link_classes, disabled_classes)}</ul></nav>)

    html.html_safe
  end

  private

  def tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
    if (p_prev = pagy.prev)
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

  # Generate a vacancy link for a person/show combination
  def vacancy_link_for(person, show)
    token = VacancyController.generate_token(person)
    vacancy_url(show, token: token)
  end
end
