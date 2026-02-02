# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Add ActionCable JavaScript assets
Rails.application.config.assets.paths << Rails.root.join("node_modules/@rails/actioncable/src") if Rails.root.join("node_modules/@rails/actioncable/src").exist?
Rails.application.config.assets.paths << Gem.loaded_specs["actioncable"]&.full_gem_path&.then { |p| File.join(p, "app/assets/javascripts") }
