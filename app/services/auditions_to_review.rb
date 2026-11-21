# frozen_string_literal: true

# The audition sign-ups a user still has to review: requests in an open (or
# paused) audition cycle that they haven't voted yes, no, or maybe on yet
# (Tim, 2026-11-20). Before this, "to review" counted every request that
# wasn't archived, so reviewing one never brought the number down.
#
# Only cycles where people apply and the team votes (curated); an open-mode
# cycle's booking is the audition, with nothing to vote on. A closed cycle
# stops counting, as home always did, so an old cycle's leftovers don't nag.
#
# Home's Actions line, the production page's To do line, and the Sign-ups
# page's To review box all read this, so they say the same number.
class AuditionsToReview
  Item = Data.define(:cycle, :production, :count)

  def self.for(user:, productions:)
    new(user: user, productions: productions).items
  end

  def initialize(user:, productions:)
    @user = user
    @productions = productions
  end

  def items
    @items ||= load_items
  end

  def total = items.sum(&:count)

  private

  def load_items
    return [] if @user.nil?

    cycles = AuditionCycle.where(production: @productions, active: true).signup_mode_curated
                          .includes(:production).to_a
                          .select { |c| %i[open paused].include?(c.timeline_status) }
    return [] if cycles.empty?

    voted = AuditionRequestVote.where(user: @user).select(:audition_request_id)
    counts = AuditionRequest.active.where(audition_cycle_id: cycles.map(&:id))
                            .where.not(id: voted).group(:audition_cycle_id).count

    cycles.filter_map { |c| (n = counts[c.id].to_i).positive? ? Item.new(cycle: c, production: c.production, count: n) : nil }
          .sort_by { |i| i.production.name.downcase }
  end
end
