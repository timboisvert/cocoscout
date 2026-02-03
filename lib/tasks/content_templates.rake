# frozen_string_literal: true

namespace :db do
  namespace :seed do
    desc "Seed content templates"
    task content_templates: :environment do
      load Rails.root.join("db/seeds/content_templates.rb")
      ContentTemplateSeeds.seed!
    end
  end
end
