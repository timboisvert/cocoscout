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

  def current_user_is_global_manager?
    return false unless Current.user
    Current.user.manager?
  end

  def current_user_has_any_manage_access?
    return false unless Current.user
    # Check if user has any production company access with manager or viewer role,
    # OR has per-production permissions
    Current.user.user_roles.exists?(company_role: [ "manager", "viewer" ]) ||
      Current.user.production_permissions.exists?
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

    anchor = ->(page, text = pagy.label_for(page), classes: nil, aria_label: nil) do
      link_to text, pagy.url_for(page),
              class: classes,
              "aria-label": aria_label
    end

    html  = %(<nav#{id} class="pagy-tailwind nav" aria-label="#{aria_label || 'Pagination'}"><ul class="flex items-center gap-2">#{
							 tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
						 })
        pagy.series.each do |item|
          segment =
            case item
            when Integer
              %(<li>#{anchor.(item, classes: link_classes)}</li>)
            when String
              %(<li><span class="#{active_classes}" aria-current="page">#{pagy.label_for(item)}</span></li>)
            when :gap
              %(<li><span class="#{gap_classes}" aria-hidden="true">&hellip;</span></li>)
            else
              raise Pagy::InternalError, "expected item types in series to be Integer, String or :gap; got #{item.inspect}"
            end
        html << segment
    end
    html << %(#{tailwind_next_html(pagy, anchor, link_classes, disabled_classes)}</ul></nav>)

    html.html_safe
  end

  private

  def tailwind_prev_html(pagy, anchor, link_classes, disabled_classes)
    if (p_prev = pagy.prev)
      %(<li>#{anchor.(p_prev, 'Previous', classes: link_classes, aria_label: 'Previous page')}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">Previous</span></li>)
    end
  end

  def tailwind_next_html(pagy, anchor, link_classes, disabled_classes)
    if (p_next = pagy.next)
      %(<li>#{anchor.(p_next, 'Next', classes: link_classes, aria_label: 'Next page')}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">Next</span></li>)
    end
  end

  def safe_headshot_url(person, variant = :thumb)
    variant_obj = person.safe_headshot_variant(variant)
    variant_obj ? url_for(variant_obj) : nil
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
end
