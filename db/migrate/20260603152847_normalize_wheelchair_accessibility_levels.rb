# frozen_string_literal: true

# Accessibility was boolean (`wheelchair: true/false` in the jsonb).
# Upgrade to three levels so producers can describe the situation
# accurately:
#
#   "fully"  — building + stage + restrooms accessible
#   "partial" — building accessible, but stage and/or restrooms may not be
#   "none"   — not wheelchair accessible
#
# We rewrite existing data in-place: anything that was `wheelchair: true`
# becomes `wheelchair_level: "fully"`. Anything explicitly `false` stays
# blank (we don't want to claim "not accessible" when the producer never
# answered — we don't know).
class NormalizeWheelchairAccessibilityLevels < ActiveRecord::Migration[8.1]
  def up
    rewrite_for(Mic)
    rewrite_for(Venue)
  end

  def down
    [ Mic, Venue ].each do |klass|
      klass.where("accessibility ? 'wheelchair_level'").find_each do |row|
        access = (row.accessibility || {}).dup
        level  = access.delete("wheelchair_level")
        access["wheelchair"] = true if level == "fully"
        row.update_columns(accessibility: access)
      end
    end
  end

  private

  def rewrite_for(klass)
    klass.where("accessibility ? 'wheelchair'").find_each do |row|
      access = (row.accessibility || {}).dup
      val    = access.delete("wheelchair")
      access["wheelchair_level"] = "fully" if val == true
      # `val == false` → drop the key; we don't auto-flag rows as
      # inaccessible without explicit producer confirmation.
      row.update_columns(accessibility: access)
    end
  end
end
