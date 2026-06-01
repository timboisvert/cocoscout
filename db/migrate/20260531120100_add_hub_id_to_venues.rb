# frozen_string_literal: true

# Venues keep their real city/state (used for maps + distance), but a
# venue can optionally roll up to a CityHub. When a venue's `city_hub_id`
# is set, the venue appears on the hub's listing page even if its real
# city is "Forest Park", "Berwyn", etc. The hub becomes the public
# rollup; the venue's actual city stays for geocoding + map markers.
class AddHubIdToVenues < ActiveRecord::Migration[8.1]
  def change
    add_reference :venues, :city_hub, null: true, foreign_key: true
  end
end
