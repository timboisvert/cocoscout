# frozen_string_literal: true

namespace :db do
  namespace :seed do
    desc "Seed email templates"
    task email_templates: :environment do
      load Rails.root.join("db/seeds/email_templates.rb")
      EmailTemplateSeeds.seed!
    end
  end
end
