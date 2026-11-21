# frozen_string_literal: true

# A production's answer to whether people are cast in it (Tim, 2026-11-18):
# "We cast people in this production" or "We don't cast people in this
# production" (Production#casts_people), and which of its dates are cast
# (Production#casting_event_matching: all performances, only some kinds of
# events, or only the dates picked).
#
# The answer is the production's; each date keeps its own switch
# (shows.casting_enabled), which is what every screen reads. So changing the
# answer brings the coming dates into line with it, and nothing else:
#
#   off!          every coming date nobody is cast in has casting switched
#                 off. A date with people already cast keeps them, and its
#                 casting stays on.
#   on!           every coming date the production's choice covers has
#                 casting switched on.
#   choose_rule!  the choice itself, then the coming dates: the ones it
#                 covers on, the others off.
#
# Nothing in the past is touched, and nobody already cast is ever removed.
# New dates follow the answer from then on (Show.casting_default_for).
module CastingAnswer
  module_function

  def off!(production)
    return false unless production.casts_people?

    Production.transaction do
      production.update!(casts_people: false)
      switch(upcoming(production).where(casting_enabled: true).where.not(id: cast_show_ids(production)), false)
    end
    true
  end

  def on!(production)
    return false if production.casts_people?

    Production.transaction do
      production.update!(casts_people: true)
      switch(upcoming(production).where(casting_enabled: false, event_type: production.casting_event_types), true)
    end
    true
  end

  # Which dates are cast: "all" (every show, class, workshop, and open mic),
  # "event_types" (only the kinds given), or "manual" (only the dates in
  # show_ids). The coming dates the choice covers get casting on, and the
  # rest get it off.
  def choose_rule!(production, matching:, event_types: [], show_ids: [])
    matching = Production::CASTING_EVENT_MATCHING.include?(matching.to_s) ? matching.to_s : "all"
    Production.transaction do
      production.update!(casting_event_matching: matching, casting_event_type_filter: matching == "event_types" ? Array(event_types) : [])
      choose_dates!(production, covered_ids(production, upcoming(production).to_a, show_ids))
    end
  end

  # The coming dates in show_ids have casting on, the rest have it off.
  def choose_dates!(production, show_ids)
    chosen = Array(show_ids).map(&:to_i)
    Production.transaction do
      switch(upcoming(production).where(casting_enabled: false, id: chosen), true)
      switch(upcoming(production).where(casting_enabled: true).where.not(id: chosen), false)
    end
  end

  # Of these dates, the ids the production's choice covers: the picked ones
  # when dates are picked by hand, else the ones of a kind it casts.
  def covered_ids(production, dates, show_ids = [])
    if production.casting_event_matching == "manual"
      Array(show_ids).map(&:to_i) & dates.map(&:id)
    else
      kinds = production.casting_event_types
      dates.select { |show| kinds.include?(show.event_type.to_s) }.map(&:id)
    end
  end

  # The coming dates, soonest first, canceled ones included: a date that
  # comes back keeps the answer it was given.
  def upcoming(production)
    production.shows.where("shows.date_and_time >= ?", Time.current).order(:date_and_time, :id)
  end

  # The coming dates somebody is cast in.
  def cast_show_ids(production)
    ShowPersonRoleAssignment.where(show_id: upcoming(production).reorder(nil).select(:id)).distinct.pluck(:show_id)
  end

  # update_all: a date that follows another organization's contract refuses
  # ordinary saves of some fields, and nothing about a date's casting switch
  # needs its callbacks.
  def switch(scope, to)
    scope.reorder(nil).update_all(casting_enabled: to, updated_at: Time.current)
  end
end
