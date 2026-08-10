# frozen_string_literal: true

# The "what are you creating?" answer from producer setup (sketch, improv,
# standup, theater, variety, other — see config/production_genres.yml).
# Nullable with no default: productions that predate the question are
# honestly unknown.
class AddGenreToProductions < ActiveRecord::Migration[8.0]
  def change
    add_column :productions, :genre, :string
    add_index :productions, :genre
  end
end
