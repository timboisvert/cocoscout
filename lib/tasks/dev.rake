# frozen_string_literal: true

namespace :dev do
  desc "Create test users with fake names and headshots (development only)"
  task :create_users, [ :count ] => :environment do |_t, args|
    count = (args[:count] || 50).to_i
    puts "Creating #{count} test users..."
    DevSeedService.create_users(count)
  end

  desc "Have test users submit audition requests to open cycles"
  task :submit_audition_requests, [ :count_per_cycle ] => :environment do |_t, args|
    count = (args[:count_per_cycle] || 10).to_i
    puts "Submitting audition requests (#{count} per cycle)..."
    DevSeedService.submit_audition_requests(count_per_cycle: count)
  end

  desc "Have test users sign up for open sign-up forms"
  task :submit_signups, [ :count_per_form ] => :environment do |_t, args|
    count = (args[:count_per_form] || 10).to_i
    puts "Submitting sign-ups (#{count} per form)..."
    DevSeedService.submit_signups(count_per_form: count)
  end

  desc "Delete all sign-up forms (development only)"
  task delete_signups: :environment do
    print "Are you sure you want to delete ALL sign-up forms? (yes/no): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "yes"
      DevSeedService.delete_all_signups
    else
      puts "Aborted."
    end
  end

  desc "Delete all test users created by dev:create_users"
  task delete_users: :environment do
    stats = DevSeedService.stats
    puts "Found #{stats[:test_users]} test users with #{stats[:test_audition_requests]} audition requests and #{stats[:test_signups]} sign-ups"
    print "Delete all test users? (yes/no): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "yes"
      DevSeedService.delete_test_users
    else
      puts "Aborted."
    end
  end

  desc "Show stats about test users and their activity"
  task stats: :environment do
    stats = DevSeedService.stats
    puts "Development Test Data Stats:"
    puts "  Test users:           #{stats[:test_users]}"
    puts "  Test people:          #{stats[:test_people]}"
    puts "  Audition requests:    #{stats[:test_audition_requests]}"
    puts "  Sign-up registrations: #{stats[:test_signups]}"
    puts "  Total sign-up forms:  #{stats[:total_signup_forms]}"
  end

  desc "Full reset: delete test users and all sign-ups"
  task reset: :environment do
    print "This will delete ALL test users AND ALL sign-up forms. Are you sure? (yes/no): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "yes"
      DevSeedService.delete_test_users
      DevSeedService.delete_all_signups
      puts "Reset complete."
    else
      puts "Aborted."
    end
  end
end
