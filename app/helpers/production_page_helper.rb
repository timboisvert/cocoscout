# frozen_string_literal: true

# A production's own page (ProductionPage; manage/productions/show).
module ProductionPageHelper
  CARD = "bg-white border border-gray-200 rounded-lg overflow-hidden"
  ROW = "flex items-center gap-3 px-4 py-2.5 border-b border-gray-100 last:border-b-0 text-sm"
  FOOT = "block px-4 py-2.5 text-sm font-medium text-pink-600 hover:text-pink-700"
  ROW_LINK = "flex-shrink-0 text-sm font-medium text-pink-600 hover:text-pink-700 whitespace-nowrap"
  TEAM_ROLES = { "manager" => "Production team manager", "viewer" => "Production team viewer" }.freeze

  # "Tonight", "Today", "Tomorrow", else "Sat, Nov 28".
  def production_page_day(time)
    date = time.to_date
    if date == Date.current then time.hour >= 17 ? "Tonight" : "Today"
    elsif date == Date.current + 1 then "Tomorrow"
    else time.strftime("%a, %b %-d")
    end
  end

  # Where a Needs doing line goes (ProductionPage::NeedsDoing#path).
  def production_page_needs_path(production, item)
    kind, record = item.path
    case kind
    when :vacancy then manage_casting_vacancy_path(production, record)
    when :auditions then manage_signups_auditions_path(production)
    when :changes then manage_show_changes_path(record)
    when :tell_canceled then manage_tell_canceled_show_path(record)
    end
  end

  # A show's room, with what it is ahead of it when it isn't a show:
  # "Rehearsal · Main Stage". kind: false leaves that out, for a course's
  # session that says "Class 4 of 8" instead.
  def production_page_where(show, kind: true)
    kind = kind && show.event_type.to_s != "show" ? event_type_label(show.event_type) : nil
    [ kind, show.location_space&.name || show.location&.name ].compact.join(" · ")
  end

  # A date's chips as Home draws them (HomeHelper#home_row_chips), without
  # the cast one on a production that isn't cast here (a course, a contract
  # production).
  def production_page_chips(page, row)
    chips = home_row_chips(row, staffing_on: page.home.staffing_on?)
    page.cast? ? chips : chips.reject { |key, _chip, _icon| key == "cast" }
  end

  # The Go to list, by what the production is and who's reading.
  def production_page_destinations(page)
    production = page.production
    pro = ->(text) { safe_join([ text, " ", render("shared/pro_marker") ]) }
    items = []
    items << { text: page.course? ? "Sessions and events" : "Shows and events", description: "The list and the calendar",
               path: manage_production_shows_path(production),
               icon: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" }
    page.runs.each do |run|
      items << { text: run.title, description: "Roster, attendance, registration", path: manage_course_offering_path(run),
                 icon: "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" }
    end
    if page.cast?
      items << { text: "Casting", description: "Who's in each show", path: manage_casting_production_path(production),
                 icon: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" }
      items << { text: "Availability", description: "Who can make which date", path: manage_casting_availability_path(production),
                 icon: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" }
      items << { text: "Sign-ups and auditions", description: "Forms, requests, sessions", path: manage_signups_production_path(production),
                 icon: "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 7h6m-6 4h4" }
    end
    if page.contract && page.contract_open?
      items << { text: pro.call("The contract"), description: "Terms, people, payments", path: manage_contract_path(page.contract),
                 icon: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" }
    end
    if page.tickets_box? && production.tickets_mode == "cocoscout"
      items << { text: pro.call("Ticketing"), description: "Dates on sale, orders, links", path: manage_production_ticketing_path(production),
                 icon: "M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z" }
    elsif page.team_sales_level == :full
      items << { text: "Ticket sales", description: "How each date is selling", path: manage_production_sales_path(production),
                 icon: "M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z" }
    end
    if page.money?
      items << { text: pro.call("Money"), description: "Show by show, payouts, expenses", path: manage_money_production_financials_path(production),
                 icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" }
    elsif page.contract && page.pro_manager? && page.organization.feature_available?(:money)
      items << { text: pro.call("Money"), description: "Incoming payments, show by show", path: manage_money_production_incoming_path(production),
                 icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" }
    end
    items << { text: "Messages", description: page.course? ? "What's been sent to the students" : "What's been sent to this production",
               path: production_manage_messages_path(production),
               icon: "M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" }
    items << { text: "Documents", description: page.course? ? "Shared with the students" : "Shared with the cast",
               path: manage_production_documents_path(production),
               icon: "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" }
    if page.manager?
      items << { text: "Settings", description: "Name, images, team, public listing", path: edit_manage_production_path(production),
                 icon: [ "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z", "M15 12a3 3 0 11-6 0 3 3 0 016 0z" ] }
    end
    items
  end
end
