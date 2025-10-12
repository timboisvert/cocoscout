module ApplicationHelper
  include Pagy::Frontend

  def pagy_nav_tailwind(pagy, id: nil, aria_label: nil)
    id               = %( id="#{id}") if id
    link_classes     = "inline-flex items-center justify-center rounded-md border border-slate-200 px-3 py-1 text-sm font-medium text-slate-700 transition hover:border-pink-400 hover:bg-pink-50 hover:text-pink-600"
    active_classes   = "inline-flex items-center justify-center rounded-md border border-pink-500 bg-pink-500 px-3 py-1 text-sm font-semibold text-white"
    disabled_classes = "inline-flex items-center justify-center rounded-md border border-slate-200 px-3 py-1 text-sm text-slate-300 cursor-not-allowed"
    gap_classes      = "inline-flex items-center justify-center px-3 py-1 text-sm text-slate-400"

    anchor = pagy_anchor(pagy)

    html  = %(<nav#{id} class="pagy-tailwind nav" #{nav_aria_label(pagy, aria_label:)}><ul class="flex items-center gap-2">#{
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
      %(<li>#{anchor.(p_prev, pagy_t('pagy.prev'), classes: link_classes, aria_label: pagy_t('pagy.aria_label.prev'))}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">#{pagy_t('pagy.prev')}</span></li>)
    end
  end

  def tailwind_next_html(pagy, anchor, link_classes, disabled_classes)
    if (p_next = pagy.next)
      %(<li>#{anchor.(p_next, pagy_t('pagy.next'), classes: link_classes, aria_label: pagy_t('pagy.aria_label.next'))}</li>)
    else
      %(<li><span class="#{disabled_classes}" aria-disabled="true">#{pagy_t('pagy.next')}</span></li>)
    end
  end
end
