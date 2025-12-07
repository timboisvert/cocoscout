# frozen_string_literal: true

namespace :productions do
  desc "Generate public keys for all productions that don't have one"
  task generate_public_keys: :environment do
    productions_without_keys = Production.where(public_key: nil)
    total = productions_without_keys.count

    if total.zero?
      puts "All productions already have public keys."
      next
    end

    puts "Generating public keys for #{total} productions..."

    success_count = 0
    error_count = 0

    productions_without_keys.find_each do |production|
      # Generate a unique key based on the production name
      production.public_key = PublicKeyService.generate(production.name)

      if production.save
        success_count += 1
        puts "  ✓ #{production.name} -> #{production.public_key}"
      else
        error_count += 1
        puts "  ✗ #{production.name}: #{production.errors.full_messages.join(', ')}"
      end
    end

    puts "\nCompleted: #{success_count} succeeded, #{error_count} failed"
  end

  desc "List all production public keys"
  task list_public_keys: :environment do
    puts "Production Public Keys:"
    puts "-" * 60

    Production.order(:name).each do |production|
      status = production.public_profile_enabled ? "enabled" : "disabled"
      puts "#{production.name}"
      puts "  Key: #{production.public_key || '(none)'}"
      puts "  Status: #{status}"
      puts "  URL: /#{production.public_key}" if production.public_key.present?
      puts ""
    end
  end
end
