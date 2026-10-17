# frozen_string_literal: true

# The comp rules (Ticketing settings → Comps), the same six fields on the
# box office (TicketingProfile), a production (ProductionTicketing, with
# own_comps) and a date (TicketListing, with own_comps):
#
#   comps_enabled        comps at all; off, nobody gives any
#   comps_limit          how many a date can give away, whoever gives them:
#                        unlimited | fixed (comps_per_show) | per_performer
#   team_comps           production team managers may give some
#   team_comps_limit     how many of them: all | fixed (team_comps_per_show)
#                        | per_performer
#
# A date reads the whole rule from one place (TicketListing#comp_rules).
module CompRules
  extend ActiveSupport::Concern

  FIELDS = %i[comps_enabled comps_limit comps_per_show team_comps team_comps_limit team_comps_per_show].freeze

  # The form's fields → attributes. own: false clears a production's or a
  # date's own rules (it follows the level above again).
  def self.attributes_from(raw, own: true)
    return FIELDS.index_with(nil).merge(own_comps: false) unless own

    {
      comps_enabled: raw[:comps_enabled] == "1",
      comps_limit: raw[:comps_limit].presence_in(TicketingProfile::COMPS_LIMITS) || "unlimited",
      comps_per_show: raw[:comps_per_show].to_s.strip.presence&.to_i || 10,
      team_comps: raw[:team_comps] == "1",
      team_comps_limit: raw[:team_comps_limit].presence_in(TicketingProfile::TEAM_COMPS_LIMITS) || "all",
      team_comps_per_show: raw[:team_comps_per_show].to_s.strip.presence&.to_i || 2
    }
  end

  # "comps on · no limit per date · production team managers may give any of
  # them", the way the production's and the date's Comps tabs read back the
  # rules they follow.
  def comp_rules_words
    return "comps off" if comps_enabled == false

    per_date = case comps_limit.presence || "unlimited"
    when "fixed" then "#{comps_per_show || 10} per date"
    when "per_performer" then "one per performer cast"
    else "no limit per date"
    end
    team = if team_comps == false
      "production team managers don't give them"
    else
      case team_comps_limit.presence || "all"
      when "fixed" then "production team managers may give #{team_comps_per_show || 2} of them"
      when "per_performer" then "production team managers may give one per performer"
      else "production team managers may give any of them"
      end
    end
    "comps on · #{per_date} · #{team}"
  end
end
