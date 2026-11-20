# frozen_string_literal: true

# The comp rules (Ticketing settings → Comps), the same seven fields on the
# box office (TicketingProfile), a production (ProductionTicketing, with
# own_comps) and a date (TicketListing, with own_comps):
#
#   comps_enabled        comps at all; off, nobody gives any
#   comps_limit          how many a date can give away, whoever gives them:
#                        unlimited | fixed (comps_per_show)
#   team_comps           production team managers may issue some
#   team_comps_limit     how many of them: all | fixed (team_comps_per_show)
#   contract_comps_per_show  how many the people on a contract may issue for
#                        a date the contract covers: 0 is none. One number
#                        between all of them (TicketSalesAccess.comp_allowance).
#   team_comp_requests   production team managers may request more comps for
#                        one date (CompRequest; Tim, 2026-11-20)
#   contract_comp_requests  the contract's side may request more comps for one date
#
# Comps are none or a number (Tim, 2026-11-17): "one per performer" was an
# option until then, and is gone until someone asks for it.
#
# A date reads the whole rule from one place (TicketListing#comp_rules).
module CompRules
  extend ActiveSupport::Concern

  FIELDS = %i[comps_enabled comps_limit comps_per_show team_comps team_comps_limit team_comps_per_show contract_comps_per_show
             team_comp_requests contract_comp_requests].freeze
  # What the form sends: the fields, and the switch beside the contract's
  # number (off saves 0).
  PARAMS = (FIELDS + %i[contract_comps]).freeze
  # The number the form offers before anyone has set one.
  CONTRACT_COMPS_SUGGESTED = 4

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
      team_comps_per_show: raw[:team_comps_per_show].to_s.strip.presence&.to_i || 2,
      contract_comps_per_show: raw[:contract_comps] == "1" ? raw[:contract_comps_per_show].to_i.clamp(0, 10_000) : 0,
      team_comp_requests: raw[:team_comp_requests] == "1",
      contract_comp_requests: raw[:contract_comp_requests] == "1"
    }
  end

  # "comps on · no limit per date · production team managers may issue any of
  # them · people on a contract may issue 4 of them", the way the production's and the date's Comps tabs read back the
  # rules they follow.
  def comp_rules_words
    return "comps off" if comps_enabled == false

    per_date = case comps_limit.presence || "unlimited"
    when "fixed" then "#{comps_per_show || 10} per date"
    else "no limit per date"
    end
    team = if team_comps == false
      "production team managers don't issue them"
    else
      case team_comps_limit.presence || "all"
      when "fixed" then "production team managers may issue #{team_comps_per_show || 2} of them"
      else "production team managers may issue any of them"
      end
    end
    contract = contract_comps_per_show.to_i.positive? ? "people on a contract may issue #{contract_comps_per_show} of them" : "people on a contract don't issue them"
    requests = [ ("production team managers" if team_comp_requests), ("contractors" if contract_comp_requests) ].compact
    requests = requests.any? ? " · #{requests.join(' and ')} may request more" : ""
    "comps on · #{per_date} · #{team} · #{contract}#{requests}"
  end
end
