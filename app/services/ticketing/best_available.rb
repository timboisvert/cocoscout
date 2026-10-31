# frozen_string_literal: true

module Ticketing
  # The best seats free for a party (advanced ticketing plan §1): a block
  # together in one row of the type's zone, the best row first and the middle
  # of the row first (Seat#best_rank); when no row has room for the whole
  # party, the best seats one by one, flagged as not together. Accessible
  # seats (wheelchair spaces, companions) are never picked unless asked for.
  class BestAvailable
    Pick = Data.define(:seats, :together)

    def self.pick(listing, tier, count, seating: nil, accessible: false)
      seating ||= Seating.new(listing)
      free = seating.free_seats(tier).reject { |s| !accessible && s.accessible? }
      return nil if count <= 0 || free.size < count

      free.group_by { |s| [ s.seat_section_id, s.row_label ] }.each_value.sort_by { |row| row.map(&:best_rank).min }.each do |row|
        run = contiguous_run(row.sort_by(&:number), count)
        return Pick.new(seats: run, together: true) if run
      end
      Pick.new(seats: free.first(count), together: false)
    end

    # The best run of `count` seats with consecutive numbers in a row, by the
    # run's best rank.
    def self.contiguous_run(row, count)
      best = nil
      row.each_cons(count) do |run|
        next unless run.each_cons(2).all? { |a, b| b.number == a.number + 1 }

        rank = run.sum(&:best_rank)
        best = run if best.nil? || rank < best.sum(&:best_rank)
      end
      best
    end
  end
end
