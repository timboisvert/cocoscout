# frozen_string_literal: true

module Ticketing
  # A chart on its own, for the editor's picture (no date, so no sales):
  # every seat with its kind and whether it's killed.
  class ChartPayload
    def self.for(chart)
      {
        width: SeatChart::WIDTH, height: chart.height,
        sections: chart.sections.includes(:seats).map do |section|
          { id: section.id, name: section.name, kind: section.kind, x: section.x, y: section.y, width: section.width, height: section.height,
            standing_capacity: section.standing_capacity,
            seats: section.seats.map { |s| { id: s.id, label: s.label, x: s.x, y: s.y, kind: s.kind, status: (s.killed ? "killed" : "free"), note: s.note } } }
        end
      }
    end
  end
end
