# frozen_string_literal: true

# The comp rules (Ticketing settings → Comps) as defaults by level (Tim,
# 2026-11-21): the box office (TicketingProfile) sets them for everything; a
# production (ProductionTicketing, own_comps) overrides them for its dates;
# a date (TicketListing, own_comps) overrides them for itself.
#
#   comps_enabled        comps allowed at all; off, nobody issues any
#   team_comps           the production team may issue comps themselves
#   team_comps_limit     how they're limited: all (no limit) | fixed (per
#                        show) | day (all the production's shows on one day)
#   team_comps_per_show  the number for fixed or day
#   team_comp_requests   they may request more when they run out (CompRequest)
#   contract_comps_own   productions on a contract have a limit of their
#                        own; off, they follow the production's
#   contract_comps, contract_comps_limit, contract_comps_per_show,
#   contract_comp_requests
#                        that limit, for the contractor's side: the
#                        contractor, the people on the contract and,
#                        connected, the people who run the contractor's
#                        organization
#
# Productions on a contract are a subset of productions, not peers (Tim,
# 2026-11-21), at every level: when productions can't issue comps
# themselves, neither can contractors, and the contract's questions don't
# show.
#
# The box office alone also has:
#   comps_limit, comps_per_show, house_comps_period
#                        the house limit: unlimited | fixed, a number per
#                        show or per day across everything. Productions and
#                        dates never override it.
#
# On a date, a number is for that date ("day" doesn't arise there): a
# date's own number replaces its production's per-day limit for that date.
#
# Comps are none or a number (Tim, 2026-11-17).
module CompRules
  extend ActiveSupport::Concern

  SIDE_LIMITS = %w[all fixed day].freeze
  HOUSE_PERIODS = %w[show day].freeze

  SIDE_FIELDS = %i[team_comps team_comps_limit team_comps_per_show team_comp_requests contract_comps_own
                   contract_comps contract_comps_limit contract_comps_per_show contract_comp_requests].freeze
  HOUSE_FIELDS = %i[comps_limit comps_per_show house_comps_period].freeze
  FIELDS = ([ :comps_enabled ] + SIDE_FIELDS).freeze
  # The form also sends contract_choice: what productions on a contract can
  # issue, as one question (same | own | none).
  PARAMS = (FIELDS + HOUSE_FIELDS + [ :contract_choice ]).freeze
  CONTRACT_CHOICES = %w[same own none].freeze

  # The numbers the form offers before anyone has set one.
  TEAM_COMPS_SUGGESTED = 2
  CONTRACT_COMPS_SUGGESTED = 4

  # One side's rule, wherever it comes from.
  #   issues    they may issue comps themselves
  #   limit     all | fixed | day
  #   count     the number for fixed or day
  #   requests  they may request more when they run out
  Side = Data.define(:issues, :limit, :count, :requests) do
    def limited? = issues && limit != "all"
    def per_day? = limited? && limit == "day"
  end

  # The form's fields → attributes. own: false clears a production's or a
  # date's own rules (it follows the level above again). house: true is the
  # box office, the only level with the house limit.
  def self.attributes_from(raw, own: true, house: false)
    return (FIELDS.index_with(nil)).merge(own_comps: false) unless own

    attributes = {
      comps_enabled: raw[:comps_enabled] == "1",
      team_comps: raw[:team_comps] == "1",
      team_comps_limit: raw[:team_comps_limit].presence_in(SIDE_LIMITS) || "all",
      team_comps_per_show: count_from(raw[:team_comps_per_show], TEAM_COMPS_SUGGESTED),
      team_comp_requests: raw[:team_comp_requests] == "1",
      contract_comps_own: raw[:contract_comps_own] == "1",
      contract_comps: raw[:contract_comps] == "1",
      contract_comps_limit: raw[:contract_comps_limit].presence_in(SIDE_LIMITS) || "fixed",
      contract_comps_per_show: count_from(raw[:contract_comps_per_show], CONTRACT_COMPS_SUGGESTED),
      contract_comp_requests: raw[:contract_comp_requests] == "1"
    }
    # The contract's one question stands in for its two switches.
    case raw[:contract_choice].presence_in(CONTRACT_CHOICES)
    when "same" then attributes[:contract_comps_own] = false
    when "own" then attributes.merge!(contract_comps_own: true, contract_comps: true)
    when "none" then attributes.merge!(contract_comps_own: true, contract_comps: false)
    end
    return attributes unless house

    attributes.merge(
      comps_limit: raw[:comps_limit] == "fixed" ? "fixed" : "unlimited",
      comps_per_show: count_from(raw[:comps_per_show], 10),
      house_comps_period: raw[:house_comps_period].presence_in(HOUSE_PERIODS) || "show"
    )
  end

  def self.count_from(value, fallback)
    value.to_s.strip.presence&.to_i&.clamp(0, 10_000) || fallback
  end

  # :team or :contract, as this level reads it. Contracts are under the
  # production's rule: none when it says no, the same rule unless they have
  # a limit of their own.
  def comp_side(side)
    production = stored_comp_side(:team)
    return production unless side.to_s == "contract"
    return production unless production.issues && contract_comps_own == true

    stored_comp_side(:contract)
  end

  # A side's own fields, whether or not they're followed (the form keeps them).
  def stored_comp_side(side)
    if side.to_s == "contract"
      Side.new(issues: contract_comps == true, limit: contract_comps_limit.presence_in(SIDE_LIMITS) || "fixed",
               count: contract_comps_per_show.to_i.positive? ? contract_comps_per_show : CONTRACT_COMPS_SUGGESTED,
               requests: contract_comp_requests == true)
    else
      Side.new(issues: team_comps != false, limit: team_comps_limit.presence_in(SIDE_LIMITS) || "all",
               count: team_comps_per_show || TEAM_COMPS_SUGGESTED, requests: team_comp_requests == true)
    end
  end

  # "Comps are allowed. Stargazers may issue 4 per show and may request more
  # when they run out. The same settings apply to Cora Contractor." The way a
  # save reads back the rules. names: { team: who the production is,
  # contract: who the contractor is }, contracted: whether to say what
  # applies to contracts, on_date: a date's own rules ("10 on this date").
  # The box office also reads back its house limit.
  def comp_rules_words(contracted: true, names: {}, on_date: false)
    return "Comps are not allowed." if comps_enabled == false

    team_name = names[:team] || "the production team"
    contract_name = names[:contract] || "contractors"
    lines = [ "Comps are allowed." ]
    if is_a?(TicketingProfile) && comps_limit == "fixed"
      lines << "The house limit is #{comps_per_show} #{house_comps_period == 'day' ? 'per day' : 'per show'}."
    end
    production = comp_side(:team)
    lines << comp_side_words(team_name, production, on_date)
    if contracted && production.issues
      lines << (contract_comps_own == true ? comp_side_words(contract_name, comp_side(:contract), on_date) : "The same settings apply to #{contract_name}.")
    end
    lines.join(" ")
  end

  private

  def comp_side_words(name, rule, on_date)
    name = name.upcase_first
    return "#{name} can't issue comps themselves." unless rule.issues

    how = case rule.limit
    when "fixed" then on_date ? "#{rule.count} on this date" : "#{rule.count} per show"
    when "day" then "#{rule.count} per day"
    else "as many as they like"
    end
    more = rule.limited? && rule.requests ? " and may request more when they run out" : ""
    "#{name} may issue #{how}#{more}."
  end
end
