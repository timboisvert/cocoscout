# frozen_string_literal: true

# A production's answer to whether people are cast in it (Tim, 2026-11-18):
# "We cast people in this production" or "We don't cast people in this
# production" (Production#casts_people), and which of its dates are cast.
#
# The answer is the production's; each date keeps its own switch
# (shows.casting_enabled), which is what every screen reads. So changing the
# answer brings the coming dates into line with it, and nothing else:
#
#   off!  every coming date nobody is cast in has casting switched off. A
#         date with people already cast keeps them, and its casting stays on.
#         Nothing in the past is touched.
#   on!   every coming date of a kind that starts with casting on (a show, a
#         class, a workshop, an open mic) has casting switched on. Rehearsals
#         and meetings stay as they are.
#
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
      switch(upcoming(production).where(casting_enabled: false, event_type: EventTypes.casting_enabled_defaults), true)
    end
    true
  end

  # Which of the coming dates are cast: the ones in show_ids have casting on,
  # the rest have it off. Nobody already cast is removed either way.
  def choose_dates!(production, show_ids)
    chosen = Array(show_ids).map(&:to_i)
    Production.transaction do
      switch(upcoming(production).where(casting_enabled: false, id: chosen), true)
      switch(upcoming(production).where(casting_enabled: true).where.not(id: chosen), false)
    end
  end

  # The coming dates, soonest first, canceled ones included: a date that
  # comes back keeps the answer it was given.
  def upcoming(production)
    production.shows.where("shows.date_and_time >= ?", Time.current).order(:date_and_time, :id)
  end

  # Whether a coming date starts ticked on the "Which dates are cast?" step
  # of set-up: its kind starts with casting on, or somebody is already cast
  # in it.
  def starts_cast?(show, cast_ids)
    EventTypes.casting_enabled_default(show.event_type) || cast_ids.include?(show.id)
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
